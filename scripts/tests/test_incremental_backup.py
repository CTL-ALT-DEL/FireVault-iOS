#!/usr/bin/env python3
"""End-to-end shell + real rclone encryption fixtures; no live backend access."""
import hashlib
import contextlib
import io
from unittest.mock import patch
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('storage', ROOT / 'scripts/backup-storage.py')
storage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(storage)


class BackupFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='firevault-backup-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ('source', 'pool', 'bin', 'target'):
            (self.root / name).mkdir()
        self.source = self.root / 'source'
        (self.root / 'bin/rclone').symlink_to(ROOT / 'scripts/tests/fixture-rclone.py')
        dump = self.root / 'bin/supabase'
        dump.write_text('#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\nPath(sys.argv[sys.argv.index("-f")+1]).write_text("-- fixture SQL dump\\n")\n')
        dump.chmod(0o755)
        sql = self.root / 'bin/psql'
        sql.write_text('#!/bin/sh\necho Unexpected SQL in storage-only fixture >&2\nexit 64\n')
        sql.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
                        FIXTURE_SOURCE=str(self.source), FIXTURE_POOL=str(self.root / 'pool'),
                        FIXTURE_TARGET=str(self.root / 'target'), FIXTURE_LOG=str(self.root / 'calls.jsonl'),
                        SUPABASE_DB_URL='postgresql://example.invalid/postgres', SUPABASE_PROJECT_REF='source-ref',
                        SUPABASE_STORAGE_ENDPOINT='https://source.invalid/storage/v1/s3', SUPABASE_STORAGE_REGION='test',
                        SUPABASE_STORAGE_ACCESS_KEY_ID='fixture', SUPABASE_STORAGE_SECRET_ACCESS_KEY='fixture',
                        R2_ENDPOINT='https://r2.invalid', R2_BUCKET='fixture', R2_ACCESS_KEY_ID='fixture',
                        R2_SECRET_ACCESS_KEY='fixture', BACKUP_ENCRYPTION_PASSWORD='fixture-password',
                        BACKUP_ENCRYPTION_SALT='fixture-salt', GITHUB_RUN_ATTEMPT='1')
        self.env['RCLONE_CONFIG_R2CRYPT_PASSWORD'] = self.rc('obscure', 'fixture-password').decode().strip()
        self.env['RCLONE_CONFIG_R2CRYPT_PASSWORD2'] = self.rc('obscure', 'fixture-salt').decode().strip()

    def rc(self, *args):
        return subprocess.check_output([str(self.root / 'bin/rclone'), *args], env=self.env, stderr=subprocess.PIPE)

    def write(self, key, content):
        file = self.source / key
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(content)

    def snapshot(self, day):
        return f'2026-10-{day:02d}T08-23-00Z-{day}-1'

    def calls(self):
        return [json.loads(line) for line in (self.root / 'calls.jsonl').read_text().splitlines()]

    def run_backup(self, day, expected=0, **extra):
        before = len(self.calls())
        result = subprocess.run(['bash', str(ROOT / 'scripts/backup-supabase-to-r2.sh')],
            env=dict(self.env, BACKUP_CREATED_AT=f'2026-10-{day:02d}T08:23:00Z', GITHUB_RUN_ID=str(day), **extra),
            capture_output=True, text=True)
        if expected == 0:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        downloaded = [c[1][len('supabase:'):] for c in self.calls()[before:]
                      if c[0] == 'copyto' and c[1].startswith('supabase:')]
        return downloaded

    def manifest(self, day):
        return json.loads(self.rc('cat', f'r2crypt:firevault/{self.snapshot(day)}/manifest.json'))

    def expected(self):
        return {p.relative_to(self.source).as_posix(): p.read_bytes() for p in self.source.rglob('*') if p.is_file()}

    def recover(self, day, expected, fail=False, latest=False, **extra):
        output = self.root / f'recovered-{day}-{len(list(self.root.glob("recovered-*")))}'
        result = subprocess.run(['bash', str(ROOT / 'scripts/recover-supabase-from-r2.sh'), 'download',
                                 '--snapshot', 'latest' if latest else self.snapshot(day), '--output', str(output)],
                                env=dict(self.env, **extra), capture_output=True, text=True)
        if fail:
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())
            return
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        actual = {p.relative_to(output / 'storage').as_posix(): p.read_bytes()
                  for p in (output / 'storage').rglob('*') if p.is_file()}
        self.assertEqual(actual, expected)
        for filename in ('roles.sql.gz', 'schema.sql.gz', 'data.sql.gz', 'SHA256SUMS'):
            self.assertTrue((output / 'database' / filename).is_file())
        return output

    def pool_hashes(self):
        return {str(p.relative_to(self.root / 'pool')): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in (self.root / 'pool').rglob('*') if p.is_file()}

    def assert_old_preserved(self, before):
        current = self.pool_hashes()
        self.assertTrue(all(current.get(k) == v for k, v in before.items()))

    def test_versions_and_historical_restore(self):
        self.write('media/photo.jpg', b'photo-one')
        self.write('media/nested/space \u2603 file', b'document')
        self.write('media/zero', b'')
        (self.source / 'empty').mkdir()
        first = self.expected()
        self.assertEqual(set(self.run_backup(1)), set(first))
        old_pool = self.pool_hashes()
        original_manifest = self.manifest(1)
        self.assertEqual(self.run_backup(2), [])
        self.assertEqual(self.manifest(2)['storage'], original_manifest['storage'])
        self.assert_old_preserved(old_pool)
        # Same-size and even same-mtime edits must be detected by checksum.
        photo = self.source / 'media/photo.jpg'
        stamp = photo.stat().st_mtime_ns
        self.write('media/photo.jpg', b'photo-two')
        os.utime(photo, ns=(stamp, stamp))
        self.write('new-bucket/new', b'new')
        self.assertEqual(set(self.run_backup(3)), {'media/photo.jpg', 'new-bucket/new'})
        third = self.expected()
        (self.source / 'media/photo.jpg').unlink()
        shutil.rmtree(self.source / 'new-bucket')
        self.assertEqual(self.run_backup(4), [])
        fourth = self.expected()
        self.write('media/photo.jpg', b'photo-three')
        self.assertEqual(self.run_backup(5), ['media/photo.jpg'])
        fifth = self.expected()
        self.assert_old_preserved(old_pool)
        for day, payload in ((1, first), (2, first), (3, third), (4, fourth), (5, fifth)):
            self.recover(day, payload)
        self.recover(5, fifth, latest=True)
        # Exercise the actual guarded Storage restore into separate local target
        # fixtures for both the current and original historical snapshot.
        for day, payload in ((1, first), (5, fifth)):
            target = self.root / 'target'
            shutil.rmtree(target)
            target.mkdir()
            for bucket in self.manifest(day)['storage']['buckets']:
                (target / bucket['name']).mkdir()
            result = subprocess.run(['bash', str(ROOT / 'scripts/recover-supabase-from-r2.sh'),
                'restore', '--snapshot', self.snapshot(day), '--phase', 'storage', '--apply',
                '--confirm-target-project-ref', 'target-ref'], capture_output=True, text=True,
                env=dict(self.env, TARGET_SUPABASE_PROJECT_REF='target-ref',
                    TARGET_SUPABASE_STORAGE_REGION='test', TARGET_SUPABASE_STORAGE_ACCESS_KEY_ID='fixture',
                    TARGET_SUPABASE_STORAGE_SECRET_ACCESS_KEY='fixture'))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            actual = {p.relative_to(target).as_posix(): p.read_bytes() for p in target.rglob('*') if p.is_file()}
            self.assertEqual(actual, payload)
        target_copies = [c for c in self.calls() if c[0] == 'copyto' and c[2].startswith('targetsupabase:')]
        self.assertTrue(any('content-type=image/jpeg' in c for c in target_copies))
        self.assertTrue(any(c[0] == 'check' and c[2].startswith('targetsupabase:') and '--download' in c for c in self.calls()))
        # Same identity is a true no-op, including its existing DB/manifest bytes.
        before = self.pool_hashes()
        self.assertEqual(self.run_backup(5), [])
        self.assertEqual(self.pool_hashes(), before)
        listing = self.rc('lsf', 'r2crypt:firevault', '--dirs-only').decode()
        self.assertIn('_storage-versions/', listing)
        result = subprocess.run(['bash', str(ROOT / 'scripts/recover-supabase-from-r2.sh'), 'list'], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('_storage-versions', result.stdout)
        print('PASS: baseline; unchanged=0 downloads; same-size edit; add/delete/recreate; five historical restores; latest; current/historical target restore; repeat=no writes')

    def test_interruptions_fail_closed_and_retry(self):
        self.write('media/photo', b'original')
        self.run_backup(1)
        original = self.expected()
        old_pool = self.pool_hashes()
        self.write('media/photo', b'updated')
        self.run_backup(2, expected=1, FIXTURE_FAIL_VERSION='1')
        self.recover(2, {}, fail=True)
        self.assert_old_preserved(old_pool)
        self.assertEqual(self.run_backup(2), ['media/photo'])
        self.recover(2, self.expected())
        self.write('media/new', b'new-file')
        self.run_backup(3, expected=1, FIXTURE_FAIL_MARKER='1')
        self.recover(3, {}, fail=True)
        self.recover(1, original)
        self.assertEqual(self.run_backup(3), ['media/new'])
        self.recover(3, self.expected())
        self.run_backup(4, expected=1, FIXTURE_FAIL_LIST='1')
        self.recover(4, {}, fail=True)
        self.write('media/new', b'new-content')
        self.run_backup(5, expected=1, FIXTURE_MUTATE_SOURCE='1')
        self.recover(5, {}, fail=True)
        self.run_backup(5)
        self.recover(5, self.expected())
        print('PASS: interrupted version/marker; no false success; retry; failed listing; concurrent mutation; historical preservation')

    def test_missing_hashes_and_corrupt_recovery(self):
        self.write('media/photo', b'12345678')
        self.run_backup(1, FIXTURE_NO_HASH='photo')
        self.assertEqual(self.run_backup(2, FIXTURE_NO_HASH='photo'), ['media/photo'])
        self.recover(2, self.expected())
        manifest = self.manifest(2)
        version = manifest['storage']['buckets'][0]['objects'][0]['version']
        corrupt = self.root / 'corrupt'
        corrupt.write_bytes(b'87654321')  # Same-size corruption, valid crypt encoding.
        self.rc('copyto', str(corrupt), 'r2crypt:' + version, '--ignore-times')
        self.recover(2, {}, fail=True)
        self.recover(1, self.expected())
        print('PASS: missing checksum retransfers; same-size corrupted payload rejected; prior version restores')

    def test_legacy_migration_without_full_source_download(self):
        import gzip
        self.write('media/photo', b'original-photo')
        self.write('media/document', b'original-document')
        first = self.expected()
        package = self.root / 'legacy'
        (package / 'database').mkdir(parents=True)
        shutil.copytree(self.source, package / 'storage')
        sums = []
        for name in ('roles.sql.gz', 'schema.sql.gz', 'data.sql.gz'):
            file = package / 'database' / name
            file.write_bytes(gzip.compress(b'-- fixture SQL'))
            sums.append(hashlib.sha256(file.read_bytes()).hexdigest() + '  ' + name)
        (package / 'database/SHA256SUMS').write_text('\n'.join(sums) + '\n')
        manifest = {
            'format_version': 1, 'created_at': '2026-10-01T08:23:00Z',
            'source': {'provider': 'supabase', 'project_ref': 'source-ref'},
            'destination': {'provider': 'cloudflare-r2', 'snapshot_path': 'firevault/' + self.snapshot(1)},
            'database': {'files': ['roles.sql.gz', 'schema.sql.gz', 'data.sql.gz'], 'checksum_algorithm': 'SHA-256'},
            'storage': {'bucket_count': 1, 'buckets': [{'name': 'media', 'object_count': 2,
                        'bytes': sum(len(v) for v in first.values())}]}}
        (package / 'manifest.json').write_text(json.dumps(manifest))
        (package / '_SUCCESS').write_text(manifest['created_at'] + '\n')
        self.rc('copy', str(package), 'r2crypt:firevault/' + self.snapshot(1))
        before = self.pool_hashes()
        self.recover(1, first)
        # One source file changed since the full backup; only that file downloads.
        self.write('media/photo', b'updated-photo!')
        self.assertEqual(self.run_backup(2), ['media/photo'])
        self.assert_old_preserved(before)
        self.recover(1, first)
        self.recover(2, self.expected())
        self.assertEqual(self.run_backup(3), [])
        self.recover(3, self.expected())
        print('PASS: real encrypted legacy restore; R2 seeding; only changed source downloaded; legacy bytes untouched')

    def test_readback_failure_and_missing_version_repair(self):
        self.write('media/photo', b'original')
        self.run_backup(1, expected=1, FIXTURE_CORRUPT_VERSION='1')
        self.recover(1, {}, fail=True)
        self.run_backup(1)
        before = self.pool_hashes()
        self.assertEqual(self.run_backup(2, FIXTURE_HIDE_VERSIONS='1'), ['media/photo'])
        self.assert_old_preserved(before)
        self.recover(1, self.expected())
        self.recover(2, self.expected())
        print('PASS: upload readback corruption blocks success; missing reference recopied; original versions preserved')

    def test_environment_guards(self):
        result = subprocess.run(['bash', str(ROOT / 'scripts/backup-supabase-to-r2.sh')],
                                env={'PATH': self.env['PATH']}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Required environment variable SUPABASE_DB_URL is missing', result.stderr)
        self.run_backup(1, expected=1, R2_ENDPOINT='https://r2.invalid/bucket')
        self.assertFalse(any(c[0] in ('copy', 'copyto') for c in self.calls()))
        print('PASS: missing credentials and bucket-scoped endpoint rejected before any writes')

    def test_metadata_only_change_is_preserved(self):
        self.write('media/photo.jpg', b'photo')
        self.run_backup(1, FIXTURE_SOURCE_METADATA='{"content-type":"image/jpeg","cache-control":"private, max-age=60"}')
        self.assertEqual(self.run_backup(2, FIXTURE_SOURCE_METADATA='{"content-type":"image/jpeg","cache-control":"private, max-age=60"}'), [])
        self.assertEqual(self.run_backup(3, FIXTURE_SOURCE_METADATA='{"content-type":"image/jpeg","cache-control":"no-cache"}'), ['media/photo.jpg'])
        first = self.manifest(1)['storage']['buckets'][0]['objects'][0]
        third = self.manifest(3)['storage']['buckets'][0]['objects'][0]
        self.assertEqual(first['metadata']['cache-control'], 'private, max-age=60')
        self.assertEqual(third['metadata']['cache-control'], 'no-cache')
        self.assertNotEqual(first['version'], third['version'])
        self.recover(1, self.expected())
        self.recover(3, self.expected())
        print('PASS: MIME/cache metadata inventoried; metadata-only change versioned; historical metadata retained')

    def test_latest_read_errors_do_not_select_older_snapshot(self):
        self.write('media/photo', b'first')
        self.run_backup(1)
        self.write('media/photo', b'second')
        self.run_backup(2)
        for fault in ('FIXTURE_FAIL_MARKER_READ', 'FIXTURE_FAIL_SNAPSHOT_LIST', 'FIXTURE_INVALID_SNAPSHOT_LIST'):
            before = len(self.calls())
            self.recover(2, {}, fail=True, latest=True, **{fault: '1'})
            new_calls = self.calls()[before:]
            self.assertFalse(any(c[0] in ('copy', 'copyto') for c in new_calls))
        self.recover(2, {}, fail=True, FIXTURE_FAIL_MARKER_READ='1')
        self.recover(2, self.expected(), latest=True)
        print('PASS: latest marker/list failures abort before download; no silent fallback to older state')

    def test_recovery_preflight_counts_shared_versions_and_enforces_cap(self):
        self.write('media/photo', b'x' * 100)
        self.run_backup(1)
        manifest = self.manifest(1)
        with patch.dict(os.environ, self.env):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                storage.preflight('firevault', self.snapshot(1), str(300 * 1024 * 1024))
            stats = json.loads(out.getvalue())
            self.assertEqual(stats['referenced_storage_bytes'], 100)
            self.assertEqual(stats['logical_recovery_bytes'], stats['snapshot_prefix_bytes'] + 100)
            before = len(self.calls())
            with self.assertRaises(ValueError):
                storage.preflight('firevault', self.snapshot(1), str(stats['snapshot_prefix_bytes'] + 99))
            self.assertFalse(any(c[0] in ('copy', 'copyto') for c in self.calls()[before:]))
            with contextlib.redirect_stdout(io.StringIO()):
                storage.preflight('firevault', 'latest', str(300 * 1024 * 1024))
        print('PASS: read-only recovery preflight includes shared versions; over-cap aborts before payload download')

    def test_unsafe_manifest_rejected_before_reads(self):
        self.write('media/photo', b'original')
        self.run_backup(1)
        manifest = self.manifest(1)
        for bad in ('../escape', '/absolute', 'folder/../escape', 'folder//name', 'control\nname', 'encoded\u240aname'):
            manifest['storage']['buckets'][0]['objects'][0]['key'] = bad
            with self.assertRaises(ValueError):
                storage.validate(manifest['storage'], 'firevault')
        manifest = self.manifest(1)
        manifest['storage']['buckets'][0]['objects'][0]['version'] = 'other-prefix/_storage-versions/' + '0' * 32
        with self.assertRaises(ValueError):
            storage.validate(manifest['storage'], 'firevault')
        print('PASS: unsafe object keys and cross-prefix references rejected')


if __name__ == '__main__':
    if not os.environ.get('FIREVAULT_TEST_RCLONE'):
        raise SystemExit('Set FIREVAULT_TEST_RCLONE to the installed rclone binary (tests require no live credentials).')
    unittest.main(verbosity=2)
