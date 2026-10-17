#!/usr/bin/env python3
"""Local-only adapter: real rclone crypt, fake S3 paths, fault injection.

Invocations cannot reach a network backend, even if real credentials are present.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

args = sys.argv[1:]
env = {k: v for k, v in os.environ.items() if not k.startswith('RCLONE_')}
env.update({
    'RCLONE_CONFIG': os.devnull,
    'RCLONE_CONFIG_R2CRYPT_TYPE': 'crypt',
    'RCLONE_CONFIG_R2CRYPT_REMOTE': os.environ['FIXTURE_POOL'],
    'RCLONE_CONFIG_R2CRYPT_PASSWORD': os.environ.get('RCLONE_CONFIG_R2CRYPT_PASSWORD', ''),
    'RCLONE_CONFIG_R2CRYPT_PASSWORD2': os.environ.get('RCLONE_CONFIG_R2CRYPT_PASSWORD2', ''),
    'RCLONE_CONFIG_R2CRYPT_FILENAME_ENCRYPTION': 'standard',
    'RCLONE_CONFIG_R2CRYPT_DIRECTORY_NAME_ENCRYPTION': 'true',
    'RCLONE_CONFIG_R2CRYPT_STRICT_NAMES': 'true',
})
if args[0] not in ('obscure', 'lsjson', 'lsf', 'size', 'copyto', 'copy', 'cat', 'check'):
    raise SystemExit('Unapproved fixture command')
if args[0] in ('copy', 'copyto') and args[2].startswith('supabase:'):
    raise SystemExit('Source write attempted')
with open(os.environ['FIXTURE_LOG'], 'a') as f:
    f.write(json.dumps(args) + '\n')
if os.environ.get('FIXTURE_FAIL_MARKER') and args[0] == 'copyto' and args[2].endswith('/_SUCCESS'):
    raise SystemExit(23)
if os.environ.get('FIXTURE_FAIL_LIST') and args[:2] == ['lsjson', 'r2crypt:firevault']:
    raise SystemExit(23)
if os.environ.get('FIXTURE_FAIL_VERSION') and args[0] == 'copyto' and '/_storage-versions/' in args[2]:
    raise SystemExit(23)
if os.environ.get('FIXTURE_FAIL_MARKER_READ') and args[0] == 'cat' and args[1].endswith('/_SUCCESS') and '2026-10-02' in args[1]:
    raise SystemExit(23)
if os.environ.get('FIXTURE_FAIL_SNAPSHOT_LIST') and args[0] == 'lsjson' and '2026-10-02' in args[1]:
    raise SystemExit(23)
original = list(args)
if os.environ.get('FIXTURE_CORRUPT_VERSION') and args[0] == 'copyto' and '/_storage-versions/' in args[2]:
    local = Path(args[1])
    local.write_bytes(b'X' * local.stat().st_size)
for i, arg in enumerate(args):
    for remote, directory in [('supabase:', 'FIXTURE_SOURCE'), ('targetsupabase:', 'FIXTURE_TARGET')]:
        if arg.startswith(remote):
            args[i] = str(Path(os.environ[directory]) / arg[len(remote):])
    path_positions = (1, 2) if args[0] in ('copy', 'copyto', 'check') else (1,)
    if i in path_positions and ':' in args[i] and not args[i].startswith(('r2crypt:', '/')) and args[0] != 'obscure':
        raise SystemExit('Unexpected remote in local fixture')
result = subprocess.run([os.environ['FIREVAULT_TEST_RCLONE'], *args], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
# S3 lists nonexistent prefixes as empty. Local filesystem returns exit 3.
if result.returncode == 3 and original[0] == 'lsjson' and original[1].startswith('r2crypt:'):
    result = subprocess.CompletedProcess(args, 0, b'[]\n', b'')
if result.returncode == 0 and original[0] == 'lsjson' and original[1].startswith('supabase:') and os.environ.get('FIXTURE_NO_HASH'):
    data = json.loads(result.stdout)
    for item in data:
        if item.get('Path') == os.environ['FIXTURE_NO_HASH']:
            item['Hashes'] = {}
    result.stdout = json.dumps(data).encode()
if result.returncode == 0 and original[0] == 'lsjson' and '2026-10-02' in original[1] and os.environ.get('FIXTURE_INVALID_SNAPSHOT_LIST'):
    result.stdout = b'not-json'
if result.returncode == 0 and original[:2] == ['lsjson', 'r2crypt:firevault/_storage-versions'] and os.environ.get('FIXTURE_HIDE_VERSIONS'):
    result.stdout = b'[]'
if result.returncode == 0 and original[0] == 'lsjson' and original[1].startswith('supabase:') and os.environ.get('FIXTURE_SOURCE_METADATA'):
    data = json.loads(result.stdout)
    for item in data:
        if not item['IsDir']:
            item.setdefault('Metadata', {}).update(json.loads(os.environ['FIXTURE_SOURCE_METADATA']))
    result.stdout = json.dumps(data).encode()
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
if result.returncode == 0 and original[0] == 'copyto' and original[1].startswith('supabase:') and os.environ.get('FIXTURE_MUTATE_SOURCE'):
    source = Path(os.environ['FIXTURE_SOURCE']) / original[1][len('supabase:'):]
    source.write_bytes(source.read_bytes() + b'changed concurrently')
raise SystemExit(result.returncode)
