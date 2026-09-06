#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly REQUIRED_ENV=(
  SUPABASE_DB_URL
  SUPABASE_PROJECT_REF
  SUPABASE_STORAGE_ENDPOINT
  SUPABASE_STORAGE_REGION
  SUPABASE_STORAGE_ACCESS_KEY_ID
  SUPABASE_STORAGE_SECRET_ACCESS_KEY
  R2_ENDPOINT
  R2_BUCKET
  R2_ACCESS_KEY_ID
  R2_SECRET_ACCESS_KEY
  BACKUP_ENCRYPTION_PASSWORD
  BACKUP_ENCRYPTION_SALT
)

log() {
  printf '[firevault-backup] %s\n' "$*"
}

fail() {
  printf '[firevault-backup] ERROR: %s\n' "$*" >&2
  exit 1
}

require_environment() {
  local name
  for name in "${REQUIRED_ENV[@]}"; do
    if [[ -z "${!name:-}" ]]; then
      fail "Required environment variable ${name} is missing."
    fi
  done
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' is not installed."
}

validate_identifier() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "${label} contains unsupported characters."
}

reject_whitespace() {
  local label="$1"
  local value="$2"
  [[ ! "$value" =~ [[:space:]] ]] || fail "${label} cannot contain spaces or line breaks."
}

sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

require_environment
require_command supabase
require_command rclone
require_command gzip
require_command jq
require_command awk

validate_identifier "SUPABASE_PROJECT_REF" "$SUPABASE_PROJECT_REF"
validate_identifier "R2_BUCKET" "$R2_BUCKET"
reject_whitespace "SUPABASE_DB_URL" "$SUPABASE_DB_URL"
reject_whitespace "SUPABASE_STORAGE_ENDPOINT" "$SUPABASE_STORAGE_ENDPOINT"
reject_whitespace "SUPABASE_STORAGE_ACCESS_KEY_ID" "$SUPABASE_STORAGE_ACCESS_KEY_ID"
reject_whitespace "SUPABASE_STORAGE_SECRET_ACCESS_KEY" "$SUPABASE_STORAGE_SECRET_ACCESS_KEY"
reject_whitespace "R2_ENDPOINT" "$R2_ENDPOINT"
reject_whitespace "R2_ACCESS_KEY_ID" "$R2_ACCESS_KEY_ID"
reject_whitespace "R2_SECRET_ACCESS_KEY" "$R2_SECRET_ACCESS_KEY"
reject_whitespace "BACKUP_ENCRYPTION_PASSWORD" "$BACKUP_ENCRYPTION_PASSWORD"
reject_whitespace "BACKUP_ENCRYPTION_SALT" "$BACKUP_ENCRYPTION_SALT"
[[ "$R2_ENDPOINT" =~ ^https://[^/]+/?$ ]] || fail "R2_ENDPOINT must be the account-level HTTPS endpoint without a bucket path."

readonly BACKUP_PREFIX="${BACKUP_PREFIX:-firevault}"
[[ "$BACKUP_PREFIX" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || fail "BACKUP_PREFIX contains unsupported characters."
[[ "$BACKUP_PREFIX" != *..* ]] || fail "BACKUP_PREFIX cannot contain '..'."

readonly CREATED_AT="${BACKUP_CREATED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
[[ "$CREATED_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || fail "BACKUP_CREATED_AT must be an ISO-8601 UTC timestamp."

readonly TIMESTAMP_PATH="${CREATED_AT//:/-}"
readonly RUN_ID="${GITHUB_RUN_ID:-manual}"
readonly RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"
validate_identifier "GITHUB_RUN_ID" "$RUN_ID"
validate_identifier "GITHUB_RUN_ATTEMPT" "$RUN_ATTEMPT"
readonly SNAPSHOT_PATH="${BACKUP_PREFIX}/${TIMESTAMP_PATH}-${RUN_ID}-${RUN_ATTEMPT}"

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf -- "$work_dir"
}
trap cleanup EXIT

readonly database_dir="$work_dir/database"
readonly bucket_rows="$work_dir/storage-buckets.jsonl"
mkdir -p "$database_dir"
: > "$bucket_rows"

# Environment-backed rclone remotes keep all credentials out of files and logs.
export RCLONE_CONFIG_SUPABASE_TYPE=s3
export RCLONE_CONFIG_SUPABASE_PROVIDER=Other
export RCLONE_CONFIG_SUPABASE_ENV_AUTH=false
export RCLONE_CONFIG_SUPABASE_ACCESS_KEY_ID="$SUPABASE_STORAGE_ACCESS_KEY_ID"
export RCLONE_CONFIG_SUPABASE_SECRET_ACCESS_KEY="$SUPABASE_STORAGE_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_SUPABASE_ENDPOINT="$SUPABASE_STORAGE_ENDPOINT"
export RCLONE_CONFIG_SUPABASE_REGION="$SUPABASE_STORAGE_REGION"
export RCLONE_CONFIG_SUPABASE_FORCE_PATH_STYLE=true
export RCLONE_CONFIG_SUPABASE_LIST_VERSION=2

export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ENV_AUTH=false
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2_ENDPOINT="${R2_ENDPOINT%/}"
export RCLONE_CONFIG_R2_REGION=auto
export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true

export RCLONE_CONFIG_R2CRYPT_TYPE=crypt
export RCLONE_CONFIG_R2CRYPT_REMOTE="r2:${R2_BUCKET}"
export RCLONE_CONFIG_R2CRYPT_PASSWORD
export RCLONE_CONFIG_R2CRYPT_PASSWORD2
RCLONE_CONFIG_R2CRYPT_PASSWORD="$(rclone obscure "$BACKUP_ENCRYPTION_PASSWORD")"
RCLONE_CONFIG_R2CRYPT_PASSWORD2="$(rclone obscure "$BACKUP_ENCRYPTION_SALT")"
export RCLONE_CONFIG_R2CRYPT_FILENAME_ENCRYPTION=standard
export RCLONE_CONFIG_R2CRYPT_DIRECTORY_NAME_ENCRYPTION=true

log "Creating logical database dump."
supabase db dump --db-url "$SUPABASE_DB_URL" -f "$database_dir/roles.sql" --role-only
supabase db dump --db-url "$SUPABASE_DB_URL" -f "$database_dir/schema.sql"
supabase db dump \
  --db-url "$SUPABASE_DB_URL" \
  -f "$database_dir/data.sql" \
  --use-copy \
  --data-only \
  -x storage.buckets_vectors \
  -x storage.vector_indexes

gzip -9 "$database_dir/roles.sql" "$database_dir/schema.sql" "$database_dir/data.sql"

readonly checksums_file="$database_dir/SHA256SUMS"
: > "$checksums_file"
for artifact in "$database_dir/roles.sql.gz" "$database_dir/schema.sql.gz" "$database_dir/data.sql.gz"; do
  printf '%s  %s\n' "$(sha256_hex "$artifact")" "$(basename "$artifact")" >> "$checksums_file"
done

log "Copying every Supabase Storage bucket."
readonly buckets_file="$work_dir/buckets.txt"
rclone lsf supabase: --dirs-only > "$buckets_file"

bucket_count=0
while IFS= read -r bucket_entry || [[ -n "$bucket_entry" ]]; do
  [[ -n "$bucket_entry" ]] || continue
  bucket="${bucket_entry%/}"
  validate_identifier "Supabase Storage bucket name" "$bucket"

  destination="r2crypt:${SNAPSHOT_PATH}/storage/${bucket}"
  log "Copying Storage bucket '${bucket}'."
  rclone copy "supabase:${bucket}" "$destination" \
    --metadata \
    --checkers 8 \
    --transfers 4 \
    --retries 3 \
    --low-level-retries 10

  source_stats="$(rclone size "supabase:${bucket}" --json)"
  destination_stats="$(rclone size "$destination" --json)"
  source_count="$(jq -er '.count | numbers' <<< "$source_stats")"
  source_bytes="$(jq -er '.bytes | numbers' <<< "$source_stats")"
  destination_count="$(jq -er '.count | numbers' <<< "$destination_stats")"
  destination_bytes="$(jq -er '.bytes | numbers' <<< "$destination_stats")"

  [[ "$source_count" == "$destination_count" ]] || fail "Object-count verification failed for bucket '${bucket}'."
  [[ "$source_bytes" == "$destination_bytes" ]] || fail "Byte-count verification failed for bucket '${bucket}'."

  jq -nc \
    --arg name "$bucket" \
    --argjson object_count "$source_count" \
    --argjson bytes "$source_bytes" \
    '{name: $name, object_count: $object_count, bytes: $bytes}' >> "$bucket_rows"
  bucket_count=$((bucket_count + 1))
done < "$buckets_file"

readonly manifest_file="$work_dir/manifest.json"
jq -s \
  --arg created_at "$CREATED_AT" \
  --arg project_ref "$SUPABASE_PROJECT_REF" \
  --arg snapshot_path "$SNAPSHOT_PATH" \
  --argjson bucket_count "$bucket_count" \
  '{
    format_version: 1,
    created_at: $created_at,
    source: {provider: "supabase", project_ref: $project_ref},
    destination: {provider: "cloudflare-r2", snapshot_path: $snapshot_path},
    database: {files: ["roles.sql.gz", "schema.sql.gz", "data.sql.gz"], checksum_algorithm: "SHA-256"},
    storage: {bucket_count: $bucket_count, buckets: .}
  }' "$bucket_rows" > "$manifest_file"

log "Uploading and verifying the database artifacts."
readonly database_destination="r2crypt:${SNAPSHOT_PATH}/database"
rclone copy "$database_dir" "$database_destination" \
  --checkers 4 \
  --transfers 4 \
  --retries 3 \
  --low-level-retries 10
rclone check "$database_dir" "$database_destination" --one-way --size-only

rclone copyto "$manifest_file" "r2crypt:${SNAPSHOT_PATH}/manifest.json"

# This marker is the commit record. Snapshots without it are incomplete and must
# never be selected for a restore.
readonly success_file="$work_dir/_SUCCESS"
printf '%s\n' "$CREATED_AT" > "$success_file"
rclone copyto "$success_file" "r2crypt:${SNAPSHOT_PATH}/_SUCCESS"

log "Backup completed successfully at ${SNAPSHOT_PATH}."
