#!/usr/bin/env bash

set -Eeuo pipefail

readonly project_root="$(cd "$(dirname "$0")/.." && pwd)"
readonly script_under_test="$project_root/scripts/backup-supabase-to-r2.sh"

test_root="$(mktemp -d)"
cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

readonly mock_bin="$test_root/bin"
readonly call_log="$test_root/calls.log"
mkdir -p "$mock_bin"
: > "$call_log"

cat > "$mock_bin/supabase" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'supabase %s\n' "$*" >> "$MOCK_CALL_LOG"
output=''
while (($#)); do
  if [[ "$1" == '-f' ]]; then
    output="$2"
    break
  fi
  shift
done
[[ -n "$output" ]]
printf '%s\n' '-- mock dump' > "$output"
MOCK

cat > "$mock_bin/rclone" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'rclone %s\n' "$*" >> "$MOCK_CALL_LOG"
case "$1" in
  obscure)
    printf 'obscured-value\n'
    ;;
  lsf)
    printf 'csv-imports/\nfirevault-user-files/\n'
    ;;
  size)
    if [[ "${MOCK_SIZE_MISMATCH:-0}" == '1' && "$2" == r2crypt:* ]]; then
      printf '{"count":2,"bytes":201}\n'
    else
      printf '{"count":2,"bytes":200}\n'
    fi
    ;;
  copy|check)
    ;;
  copyto)
    if [[ "$3" == *'/_SUCCESS' ]]; then
      : > "$MOCK_SUCCESS_MARKER"
    fi
    ;;
  *)
    printf 'Unexpected rclone command: %s\n' "$1" >&2
    exit 64
    ;;
esac
MOCK

chmod +x "$mock_bin/supabase" "$mock_bin/rclone"

run_backup() {
  env \
    PATH="$mock_bin:$PATH" \
    MOCK_CALL_LOG="$call_log" \
    MOCK_SUCCESS_MARKER="$test_root/success" \
    SUPABASE_DB_URL='postgresql://example.invalid/postgres' \
    SUPABASE_PROJECT_REF='project-ref' \
    SUPABASE_STORAGE_ENDPOINT='https://project-ref.storage.example.invalid/storage/v1/s3' \
    SUPABASE_STORAGE_REGION='us-test-1' \
    SUPABASE_STORAGE_ACCESS_KEY_ID='source-key' \
    SUPABASE_STORAGE_SECRET_ACCESS_KEY='source-secret' \
    R2_ENDPOINT='https://account.example.invalid' \
    R2_BUCKET='firevault-backups' \
    R2_ACCESS_KEY_ID='destination-key' \
    R2_SECRET_ACCESS_KEY='destination-secret' \
    BACKUP_ENCRYPTION_PASSWORD='encryption-password' \
    BACKUP_ENCRYPTION_SALT='encryption-salt' \
    BACKUP_CREATED_AT='2026-09-06T08:23:00Z' \
    GITHUB_RUN_ID='12345' \
    GITHUB_RUN_ATTEMPT='1' \
    "$@" \
    "$script_under_test"
}

assert_contains() {
  local expected="$1"
  grep -F -- "$expected" "$call_log" >/dev/null || {
    printf 'Expected call log to contain: %s\n' "$expected" >&2
    exit 1
  }
}

run_backup env
[[ -f "$test_root/success" ]]
assert_contains 'supabase db dump'
assert_contains 'rclone copy supabase:csv-imports r2crypt:firevault/2026-09-06T08-23-00Z-12345-1/storage/csv-imports'
assert_contains 'rclone copy supabase:firevault-user-files r2crypt:firevault/2026-09-06T08-23-00Z-12345-1/storage/firevault-user-files'
assert_contains 'rclone check'
assert_contains 'rclone copyto'

rm -f "$test_root/success"
if run_backup env MOCK_SIZE_MISMATCH=1 > "$test_root/mismatch.log" 2>&1; then
  printf 'Expected mismatched bucket sizes to fail.\n' >&2
  exit 1
fi
[[ ! -f "$test_root/success" ]]
grep -F 'Byte-count verification failed' "$test_root/mismatch.log" >/dev/null

if env PATH="$mock_bin:$PATH" "$script_under_test" > "$test_root/missing-env.log" 2>&1; then
  printf 'Expected missing environment to fail.\n' >&2
  exit 1
fi
grep -F 'Required environment variable SUPABASE_DB_URL is missing' "$test_root/missing-env.log" >/dev/null

if run_backup env R2_ENDPOINT='https://account.example.invalid/firevault-backups' > "$test_root/endpoint.log" 2>&1; then
  printf 'Expected a bucket path in R2_ENDPOINT to fail.\n' >&2
  exit 1
fi
grep -F 'R2_ENDPOINT must be the account-level HTTPS endpoint' "$test_root/endpoint.log" >/dev/null

printf 'Nightly disaster-backup script tests passed.\n'
