#!/usr/bin/env bash

set -Eeuo pipefail

readonly project_root="$(cd "$(dirname "$0")/.." && pwd)"
readonly script_under_test="$project_root/scripts/recover-supabase-from-r2.sh"

test_root="$(mktemp -d)"
cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

readonly mock_bin="$test_root/bin"
readonly fixture_dir="$test_root/fixture"
readonly call_log="$test_root/calls.log"
mkdir -p "$mock_bin" "$fixture_dir/database" "$fixture_dir/storage/csv-imports" "$fixture_dir/storage/firevault-user-files"
: > "$call_log"

printf '%s\n' '-- roles' > "$fixture_dir/database/roles.sql"
printf '%s\n' '-- schema' > "$fixture_dir/database/schema.sql"
printf '%s\n' '-- data' > "$fixture_dir/database/data.sql"
gzip -n "$fixture_dir/database/roles.sql" "$fixture_dir/database/schema.sql" "$fixture_dir/database/data.sql"

sha256_for_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

for filename in roles.sql.gz schema.sql.gz data.sql.gz; do
  printf '%s  %s\n' "$(sha256_for_file "$fixture_dir/database/$filename")" "$filename" >> "$fixture_dir/database/SHA256SUMS"
done

printf 'abc' > "$fixture_dir/storage/csv-imports/import.csv"
printf 'hello' > "$fixture_dir/storage/firevault-user-files/photo.jpg"
printf '%s\n' '2026-09-06T17:03:15Z' > "$fixture_dir/_SUCCESS"
jq -n '{
  format_version: 1,
  created_at: "2026-09-06T17:03:15Z",
  source: {provider: "supabase", project_ref: "source-ref"},
  destination: {
    provider: "cloudflare-r2",
    snapshot_path: "firevault/2026-09-06T17-03-15Z-34047103028-2"
  },
  database: {
    files: ["roles.sql.gz", "schema.sql.gz", "data.sql.gz"],
    checksum_algorithm: "SHA-256"
  },
  storage: {
    bucket_count: 2,
    buckets: [
      {name: "csv-imports", object_count: 1, bytes: 3},
      {name: "firevault-user-files", object_count: 1, bytes: 5}
    ]
  }
}' > "$fixture_dir/manifest.json"

cat > "$mock_bin/rclone" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'rclone %s\n' "$*" >> "$MOCK_CALL_LOG"

case "$1" in
  obscure)
    printf 'obscured-value\n'
    ;;
  lsf)
    if [[ "$2" == 'r2crypt:firevault' ]]; then
      printf '%s\n' \
        '2026-09-06T17-03-15Z-34047103028-2/' \
        '2026-09-05T17-03-15Z-111-1/' \
        '2026-09-07T17-03-15Z-incomplete-1/'
    elif [[ "$2" == 'targetsupabase:' ]]; then
      printf '%s\n' 'csv-imports/' 'firevault-user-files/'
    else
      printf 'Unexpected lsf path: %s\n' "$2" >&2
      exit 64
    fi
    ;;
  cat)
    if [[ "$2" == *'incomplete'* ]]; then
      exit 1
    fi
    printf '%s\n' '2026-09-06T17:03:15Z'
    ;;
  copy)
    if [[ "$2" == r2crypt:* ]]; then
      cp -R "$MOCK_FIXTURE_DIR/." "$3/"
    fi
    ;;
  size)
    case "$2" in
      */csv-imports|targetsupabase:csv-imports)
        printf '{"count":1,"bytes":3}\n'
        ;;
      */firevault-user-files|targetsupabase:firevault-user-files)
        printf '{"count":1,"bytes":5}\n'
        ;;
      *)
        printf 'Unexpected size path: %s\n' "$2" >&2
        exit 64
        ;;
    esac
    ;;
  *)
    printf 'Unexpected rclone command: %s\n' "$1" >&2
    exit 64
    ;;
esac
MOCK

cat > "$mock_bin/psql" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'psql %s\n' "$*" >> "$MOCK_CALL_LOG"
if [[ " $* " == *' --tuples-only '* ]]; then
  printf '%s\n' "${MOCK_TARGET_STATE:-0:0:0}"
fi
MOCK

chmod +x "$mock_bin/rclone" "$mock_bin/psql"

run_recovery() {
  env \
    PATH="$mock_bin:$PATH" \
    MOCK_CALL_LOG="$call_log" \
    MOCK_FIXTURE_DIR="${TEST_FIXTURE_DIR:-$fixture_dir}" \
    MOCK_TARGET_STATE="${TEST_MOCK_TARGET_STATE:-0:0:0}" \
    R2_ENDPOINT='https://account.example.invalid' \
    R2_BUCKET='firevault-disaster-backups' \
    R2_ACCESS_KEY_ID='r2-key' \
    R2_SECRET_ACCESS_KEY='r2-secret' \
    BACKUP_ENCRYPTION_PASSWORD='encryption-password' \
    BACKUP_ENCRYPTION_SALT='encryption-salt' \
    TARGET_SUPABASE_PROJECT_REF="${TEST_TARGET_PROJECT_REF:-target-ref}" \
    TARGET_SUPABASE_DB_URL="${TEST_TARGET_DB_URL:-postgresql://postgres.target-ref:password@example.invalid/postgres}" \
    TARGET_SUPABASE_STORAGE_REGION='us-test-1' \
    TARGET_SUPABASE_STORAGE_ACCESS_KEY_ID='target-key' \
    TARGET_SUPABASE_STORAGE_SECRET_ACCESS_KEY='target-secret' \
    "$script_under_test" \
    "$@"
}

assert_contains() {
  local expected="$1"
  grep -F -- "$expected" "$call_log" >/dev/null || {
    printf 'Expected call log to contain: %s\n' "$expected" >&2
    exit 1
  }
}

list_output="$(run_recovery list)"
expected_list=$'2026-09-05T17-03-15Z-111-1\n2026-09-06T17-03-15Z-34047103028-2'
[[ "$list_output" == "$expected_list" ]] || {
  printf 'Unexpected completed-snapshot list:\n%s\n' "$list_output" >&2
  exit 1
}

download_dir="$test_root/downloaded"
run_recovery download --snapshot latest --output "$download_dir"
[[ -f "$download_dir/manifest.json" ]]
[[ -f "$download_dir/database/SHA256SUMS" ]]
assert_contains 'rclone copy r2crypt:firevault/2026-09-06T17-03-15Z-34047103028-2'

corrupt_fixture="$test_root/corrupt-fixture"
cp -R "$fixture_dir" "$corrupt_fixture"
printf 'corrupt' >> "$corrupt_fixture/database/data.sql.gz"
if TEST_FIXTURE_DIR="$corrupt_fixture" run_recovery download \
  --snapshot 2026-09-06T17-03-15Z-34047103028-2 \
  --output "$test_root/corrupt-download" > "$test_root/corrupt.log" 2>&1; then
  printf 'Expected a corrupt database artifact to fail verification.\n' >&2
  exit 1
fi
grep -E 'FAILED|checksum' "$test_root/corrupt.log" >/dev/null
[[ ! -e "$test_root/corrupt-download" ]]

if run_recovery restore \
  --confirm-target-project-ref target-ref > "$test_root/no-apply.log" 2>&1; then
  printf 'Expected restore without --apply to fail.\n' >&2
  exit 1
fi
grep -F 'Restore requires --apply' "$test_root/no-apply.log" >/dev/null

if TEST_TARGET_PROJECT_REF=source-ref \
  TEST_TARGET_DB_URL=postgresql://postgres.source-ref:password@example.invalid/postgres \
  run_recovery restore --apply --confirm-target-project-ref source-ref \
  > "$test_root/source-target.log" 2>&1; then
  printf 'Expected restore over the source project to fail.\n' >&2
  exit 1
fi
grep -F 'Refusing to restore over source project' "$test_root/source-target.log" >/dev/null

run_recovery restore \
  --snapshot 2026-09-06T17-03-15Z-34047103028-2 \
  --phase all \
  --apply \
  --confirm-target-project-ref target-ref
assert_contains 'psql --no-psqlrc --single-transaction'
assert_contains 'rclone copy '
assert_contains 'targetsupabase:csv-imports'
assert_contains 'targetsupabase:firevault-user-files'

if TEST_MOCK_TARGET_STATE=1:0:0 run_recovery restore --phase database --apply \
  --confirm-target-project-ref target-ref > "$test_root/nonempty.log" 2>&1; then
  printf 'Expected a database restore into a non-empty target to fail.\n' >&2
  exit 1
fi
grep -F 'Target project is not blank' "$test_root/nonempty.log" >/dev/null

printf 'Disaster-recovery script tests passed.\n'
