#!/usr/bin/env python3
"""One-time S3 metadata inventory. No object GET, writes, or raw-data output."""
import json
import re
import subprocess
import sys


def listing(remote, *flags):
    result = subprocess.run(
        ['rclone', 'lsjson', remote, *flags, '--retries', '1',
         '--low-level-retries', '1', '--contimeout', '10s', '--timeout', '30s'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=300)
    if result.returncode or len(result.stdout) > 10 * 1024 * 1024:
        raise ValueError('Inventory unavailable or exceeds metadata budget')
    value = json.loads(result.stdout)
    if not isinstance(value, list):
        raise ValueError('Invalid inventory')
    return value


def unsafe(key):
    return (not isinstance(key, str) or not key or '\\' in key or key.startswith('/')
            or any(p in ('', '.', '..') for p in key.split('/'))
            or any(ord(c) < 32 or 0x2400 <= ord(c) <= 0x2421
                   or 0xff00 <= ord(c) <= 0xff60 or c == '‛' for c in key))


def main():
    totals = dict(bucket_count=0, object_count=0, source_logical_bytes=0,
                  reusable_md5_objects=0, reusable_md5_bytes=0,
                  metadata_mime_objects=0, unsupported_keys=0,
                  invalid_metadata_objects=0, source_payload_bytes_downloaded=0)
    for bucket in listing('supabase:', '--dirs-only'):
        name = bucket['Name']
        if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name):
            raise ValueError('Unsupported bucket')
        totals['bucket_count'] += 1
        for obj in listing('supabase:' + name, '--recursive', '--files-only', '--hash', '--metadata'):
            size = obj['Size']
            if type(size) is not int or size < 0:
                raise ValueError('Invalid size')
            totals['object_count'] += 1
            if totals['object_count'] > 10000:
                raise ValueError('Object count exceeds diagnostic budget')
            totals['source_logical_bytes'] += size
            hashes = {k.lower(): v for k, v in obj.get('Hashes', {}).items()}
            md5 = hashes.get('md5', '')
            if isinstance(md5, str) and re.fullmatch('[0-9a-fA-F]{32}', md5):
                totals['reusable_md5_objects'] += 1
                totals['reusable_md5_bytes'] += size
            metadata = obj.get('Metadata', {})
            valid_metadata = isinstance(metadata, dict) and all(
                isinstance(k, str) and k and '=' not in k and isinstance(v, str)
                for k, v in metadata.items())
            totals['invalid_metadata_objects'] += not valid_metadata
            if valid_metadata and (metadata.get('content-type') or obj.get('MimeType')):
                totals['metadata_mime_objects'] += 1
            totals['unsupported_keys'] += unsafe(obj['Path'])
    print(json.dumps(totals, sort_keys=True))
    if totals['unsupported_keys'] or totals['invalid_metadata_objects']:
        raise ValueError('Unsupported inventory fields')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Never disclose bucket/object names, metadata, credentials, or raw errors.
        sys.exit('S3 metadata diagnostic failed; raw diagnostics suppressed.')
