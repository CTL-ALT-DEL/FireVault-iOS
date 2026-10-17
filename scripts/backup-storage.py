#!/usr/bin/env python3
"""Format-2 immutable Storage versions. No remote deletions or source writes."""
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path, PurePosixPath


SNAPSHOT_ID = r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9TZ-]+-[A-Za-z0-9._-]+'


def rc(*args):
    return subprocess.check_output(['rclone', *map(str, args)])


def load(remote):
    return json.loads(rc('cat', remote))


def safe_path(value):
    if not isinstance(value, str) or not value or '\\' in value or '\x00' in value:
        raise ValueError('Invalid object path')
    if any(ord(c) < 32 or 0x2400 <= ord(c) <= 0x2421 or 0xff00 <= ord(c) <= 0xff60 or c == '‛' for c in value):
        raise ValueError('Object key requires unsupported rclone filename encoding')
    if value.startswith('/') or any(p in ('', '.', '..') for p in value.split('/')):
        raise ValueError('Unsafe object path')
    return value


def inventory():
    result = []
    for bucket in json.loads(rc('lsjson', 'supabase:', '--dirs-only')):
        name = bucket['Name']
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name):
            raise ValueError('Invalid bucket name')
        objects = []
        for obj in json.loads(rc('lsjson', f'supabase:{name}', '--recursive', '--files-only', '--hash', '--metadata')):
            key = safe_path(obj['Path'])
            size = obj['Size']
            if type(size) is not int or size < 0:
                raise ValueError('Invalid source size')
            hashes = {k.lower(): v for k, v in obj.get('Hashes', {}).items()}
            md5 = hashes.get('md5', '').lower()
            # Multipart/missing hashes are never reused based only on size/time.
            if not re.fullmatch('[0-9a-f]{32}', md5):
                md5 = ''
            metadata = {k.lower(): v for k, v in obj.get('Metadata', {}).items()
                        if k.lower() not in ('atime', 'uid', 'gid', 'mode', 'rdev')}
            metadata.setdefault('content-type', obj.get('MimeType') or 'application/octet-stream')
            objects.append({'key': key, 'size': size, 'md5': md5, 'modtime': obj['ModTime'], 'metadata': metadata})
        objects.sort(key=lambda x: x['key'])
        if len({o['key'] for o in objects}) != len(objects):
            raise ValueError('Duplicate source object')
        result.append({'name': name, 'objects': objects})
    result.sort(key=lambda x: x['name'])
    if len({b['name'] for b in result}) != len(result):
        raise ValueError('Duplicate source bucket')
    return result


def validate(storage, prefix):
    seen = set()
    if storage['bucket_count'] != len(storage['buckets']):
        raise ValueError('Invalid bucket count')
    for bucket in storage['buckets']:
        name = bucket['name']
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name) or name in seen:
            raise ValueError('Invalid or duplicate bucket')
        seen.add(name)
        keys = set()
        for obj in bucket['objects']:
            key = safe_path(obj['key'])
            if key in keys:
                raise ValueError('Duplicate object')
            keys.add(key)
            if type(obj['size']) is not int or obj['size'] < 0:
                raise ValueError('Invalid size')
            if not re.fullmatch('[0-9a-f]{64}', obj['sha256']):
                raise ValueError('Invalid checksum')
            if not re.fullmatch(re.escape(prefix) + r'/_storage-versions/[0-9a-f]{32}', obj['version']):
                raise ValueError('Invalid version reference')
            if not isinstance(obj['md5'], str) or (obj['md5'] and not re.fullmatch('[0-9a-f]{32}', obj['md5'])):
                raise ValueError('Invalid source checksum')
            if not isinstance(obj['metadata'], dict) or not all(
                    isinstance(k, str) and k and '=' not in k and isinstance(v, str)
                    for k, v in obj['metadata'].items()):
                raise ValueError('Invalid object metadata')
            if not isinstance(obj['modtime'], str):
                raise ValueError('Invalid source modification time')
        for key in keys:
            if any(str(p) in keys for p in PurePosixPath(key).parents if str(p) != '.'):
                raise ValueError('Conflicting object paths')
        if bucket['object_count'] != len(keys) or bucket['bytes'] != sum(o['size'] for o in bucket['objects']):
            raise ValueError('Invalid bucket totals')


def previous(prefix, project):
    entries = json.loads(rc('lsjson', f'r2crypt:{prefix}', '--dirs-only'))
    for entry in sorted(entries, key=lambda x: x['Name'], reverse=True):
        name = entry['Name']
        if not re.fullmatch(SNAPSHOT_ID, name):
            continue
        root = f'r2crypt:{prefix}/{name}'
        # List failures abort; missing markers identify incomplete runs.
        files = json.loads(rc('lsjson', root, '--files-only'))
        if '_SUCCESS' not in {f['Name'] for f in files}:
            continue
        manifest = load(root + '/manifest.json')
        if rc('cat', root + '/_SUCCESS').decode().strip() != manifest['created_at']:
            raise ValueError('Invalid completed snapshot marker')
        if manifest['source']['project_ref'] != project:
            raise ValueError('Backup prefix belongs to another project')
        if manifest['destination']['snapshot_path'] != f'{prefix}/{name}':
            raise ValueError('Invalid snapshot destination')
        if manifest['format_version'] == 1:
            # Bootstrap from the existing full R2 snapshot, without downloading
            # unchanged payloads from Supabase. Content is checked below against
            # the current source checksum before it becomes a new version.
            legacy = {}
            for bucket in manifest['storage']['buckets']:
                bucket_name = bucket['name']
                if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', bucket_name):
                    raise ValueError('Invalid legacy bucket')
                remote = root + '/storage/' + bucket_name
                listing = json.loads(rc('lsjson', remote, '--recursive', '--files-only'))
                if (len(listing) != bucket['object_count']
                        or sum(o['Size'] for o in listing) != bucket['bytes']):
                    raise ValueError('Legacy snapshot totals do not match manifest')
                for obj in listing:
                    key = safe_path(obj['Path'])
                    legacy[(bucket_name, key)] = {'size': obj['Size'], 'legacy': remote + '/' + key}
            return legacy
        if manifest['format_version'] != 2:
            raise ValueError('Unsupported backup format')
        validate(manifest['storage'], prefix)
        return {(b['name'], o['key']): o for b in manifest['storage']['buckets'] for o in b['objects']}
    return {}


def digest(path, algorithm='sha256'):
    h = hashlib.new(algorithm)
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def backup(prefix, project, output):
    old = previous(prefix, project)
    source = inventory()
    all_objects = [o for b in source for o in b['objects']]
    hashless = [o for o in all_objects if not o['md5']]
    print(f'[firevault-backup] Storage inventory: {len(all_objects)} objects; '
          f'{sum(o["size"] for o in all_objects)} bytes; '
          f'{len(hashless)} without reusable MD5 ({sum(o["size"] for o in hashless)} bytes)', flush=True)
    # Existence and decrypted sizes of reused versions; no content downloads.
    versions = {o['Path']: o['Size'] for o in json.loads(rc(
        'lsjson', f'r2crypt:{prefix}/_storage-versions', '--recursive', '--files-only'))}
    buckets = []
    transferred = 0
    seeded = 0
    with tempfile.TemporaryDirectory() as temp:
        local = Path(temp) / 'object'
        check = Path(temp) / 'check'
        for bucket in source:
            objects = []
            for obj in bucket['objects']:
                prior = old.get((bucket['name'], obj['key']))
                if (prior and 'version' in prior and obj['md5'] and all(prior[k] == obj[k] for k in ('size', 'md5', 'modtime', 'metadata'))
                        and versions.get(prior['version'].split('/_storage-versions/')[1]) == obj['size']):
                    item = dict(prior)
                else:
                    from_legacy = False
                    if prior and 'legacy' in prior and obj['md5'] and prior['size'] == obj['size']:
                        rc('copyto', prior['legacy'], local, '--metadata', '--ignore-times')
                        from_legacy = local.stat().st_size == obj['size'] and digest(local, 'md5') == obj['md5']
                    if from_legacy:
                        seeded += obj['size']
                    else:
                        rc('copyto', f"supabase:{bucket['name']}/{obj['key']}", local, '--metadata', '--ignore-times')
                        transferred += obj['size']
                    if local.stat().st_size != obj['size'] or (obj['md5'] and digest(local, 'md5') != obj['md5']):
                        raise ValueError('Source changed during download')
                    item = dict(obj, sha256=digest(local), version=f'{prefix}/_storage-versions/{uuid.uuid4().hex}')
                    rc('copyto', local, 'r2crypt:' + item['version'], '--immutable', *metadata_flags(item))
                    rc('copyto', 'r2crypt:' + item['version'], check, '--ignore-times')
                    if check.stat().st_size != item['size'] or digest(check) != item['sha256']:
                        raise ValueError('R2 version failed readback checksum')
                objects.append(item)
            buckets.append({'name': bucket['name'], 'objects': objects,
                            'object_count': len(objects), 'bytes': sum(o['size'] for o in objects)})
    if source != inventory():
        raise ValueError('Storage inventory changed during backup; retry in a quiet window')
    storage = {'bucket_count': len(buckets), 'buckets': buckets}
    validate(storage, prefix)
    Path(output).write_text(json.dumps(storage, indent=2) + '\n')
    print(f'[firevault-backup] Storage payload downloaded from Supabase: {transferred} bytes; seeded from legacy R2: {seeded} bytes')


def preflight(prefix, selector, cap):
    """Read-only logical recovery-size check, including format-2 references."""
    cap = int(cap)
    if cap <= 0:
        raise ValueError('Invalid recovery cap')
    if selector == 'latest':
        entries = json.loads(rc('lsjson', f'r2crypt:{prefix}', '--dirs-only'))
        selected = None
        for entry in sorted(entries, key=lambda x: x['Name'], reverse=True):
            name = entry['Name']
            if not re.fullmatch(SNAPSHOT_ID, name):
                continue
            files = json.loads(rc('lsjson', f'r2crypt:{prefix}/{name}', '--files-only'))
            if any(f['Name'] == '_SUCCESS' for f in files):
                selected = name
                break
        if selected is None:
            raise ValueError('No completed snapshots')
    else:
        selected = selector.removeprefix(prefix + '/') if hasattr(selector, 'removeprefix') else selector
        if not re.fullmatch(SNAPSHOT_ID, selected):
            raise ValueError('Invalid snapshot selector')
    root = f'r2crypt:{prefix}/{selected}'
    rows = json.loads(rc('lsjson', root, '--recursive', '--files-only'))
    files = {}
    for row in rows:
        if type(row['Size']) is not int or row['Size'] < 0 or row['Path'] in files:
            raise ValueError('Invalid snapshot listing')
        files[row['Path']] = row['Size']
    package_bytes = sum(files.values())
    if package_bytes > cap:
        raise ValueError('Snapshot prefix exceeds authorized cap')
    if not (0 < files.get('manifest.json', 0) <= 1024 * 1024
            and 0 < files.get('_SUCCESS', 0) <= 128):
        raise ValueError('Missing or oversized commit records')
    raw_manifest = rc('cat', root + '/manifest.json')
    marker = rc('cat', root + '/_SUCCESS')
    manifest = json.loads(raw_manifest)
    if (manifest['destination']['snapshot_path'] != f'{prefix}/{selected}'
            or manifest['source']['provider'] != 'supabase'
            or marker.decode().strip() != manifest['created_at']):
        raise ValueError('Invalid snapshot commit identity')
    version = manifest['format_version']
    reference_bytes = 0
    references = []
    if version == 2:
        validate(manifest['storage'], prefix)
        allowed = {'manifest.json', '_SUCCESS', 'database/SHA256SUMS',
                   'database/roles.sql.gz', 'database/schema.sql.gz', 'database/data.sql.gz'}
        if set(files) != allowed:
            raise ValueError('Unexpected format-2 snapshot files')
        references = [o for b in manifest['storage']['buckets'] for o in b['objects']]
        reference_bytes = sum(o['size'] for o in references)
    elif version != 1:
        raise ValueError('Unsupported backup format')
    total = package_bytes + reference_bytes
    if total > cap:
        raise ValueError('Recovery package exceeds authorized cap')
    for obj in references:
        stat = json.loads(rc('lsjson', 'r2crypt:' + obj['version'], '--stat'))
        if stat.get('IsDir', True) or stat.get('Size') != obj['size']:
            raise ValueError('Missing or mismatched referenced version')
    result = {'snapshot_id': selected, 'format_version': version,
              'snapshot_prefix_bytes': package_bytes, 'referenced_storage_bytes': reference_bytes,
              'logical_recovery_bytes': total, 'logical_cap_bytes': cap,
              'metadata_probe_bytes': len(raw_manifest) + len(marker)}
    print(json.dumps(result, sort_keys=True))


def metadata_flags(obj):
    flags = ['--metadata']
    for key, value in sorted(obj['metadata'].items()):
        flags.extend(['--metadata-set', key + '=' + value])
    return flags


def restore_bucket(prefix, manifest_file, snapshot_dir, bucket_name):
    # The shell configures only the separately confirmed target project remote.
    manifest = json.loads(Path(manifest_file).read_text())
    validate(manifest['storage'], prefix)
    bucket = next(b for b in manifest['storage']['buckets'] if b['name'] == bucket_name)
    for obj in bucket['objects']:
        source = Path(snapshot_dir) / 'storage' / bucket_name / obj['key']
        rc('copyto', source, f"targetsupabase:{bucket_name}/{obj['key']}",
           '--ignore-times', '--no-update-modtime', *metadata_flags(obj))


def materialize(prefix, snapshot_path, manifest_file, destination):
    manifest = json.loads(Path(manifest_file).read_text())
    if manifest['format_version'] != 2 or manifest['destination']['snapshot_path'] != snapshot_path:
        raise ValueError('Invalid snapshot identity')
    storage = manifest['storage']
    validate(storage, prefix)
    root = Path(destination)
    if root.exists():
        raise ValueError('Storage staging path already exists')
    root.mkdir()
    for bucket in storage['buckets']:
        directory = root / bucket['name']
        directory.mkdir()
        for obj in bucket['objects']:
            target = directory / obj['key']
            target.parent.mkdir(parents=True, exist_ok=True)
            rc('copyto', 'r2crypt:' + obj['version'], target, '--metadata')
            if target.stat().st_size != obj['size'] or digest(target) != obj['sha256']:
                raise ValueError('Recovered Storage object failed checksum')


if __name__ == '__main__':
    if sys.argv[1] == 'backup':
        backup(*sys.argv[2:])
    elif sys.argv[1] == 'preflight':
        preflight(*sys.argv[2:])
    elif sys.argv[1] == 'restore-bucket':
        restore_bucket(*sys.argv[2:])
    elif sys.argv[1] == 'materialize':
        materialize(*sys.argv[2:])
    else:
        raise SystemExit('Unknown operation')
