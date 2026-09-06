#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly REQUIRED_R2_ENV=(
  R2_ENDPOINT
  R2_BUCKET
  R2_ACCESS_KEY_ID
  R2_SECRET_ACCESS_KEY
  BACKUP_ENCRYPTION_PASSWORD
  BACKUP_ENCRYPTION_SALT
)

readonly REQUIRED_TARGET_DATABASE_ENV=(
  TARGET_SUPABASE_DB_URL
)

readonly REQUIRED_TARGET_STORAGE_ENV=(
  TARGET_SUPABASE_STORAGE_REGION
  TARGET_SUPABASE_STORAGE_ACCESS_KEY_ID
  TARGET_SUPABASE_STORAGE_SECRET_ACCESS_KEY
)

readonly BACKUP_PREFIX="${BACKUP_PREFIX:-firevault}"
temporary_paths=()

log() {
  printf '[firevault-recovery] %s\n' "$*"
}

fail() {
  printf '[firevault-recovery] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  recover-supabase-from-r2.sh list
  recover-supabase-from-r2.sh download [--snapshot latest|ID] --output DIRECTORY
  recover-supabase-from-r2.sh restore [--snapshot latest|ID] \
    --phase database|storage|all --confirm-target-project-ref PROJECT_REF --apply

All commands read the encrypted R2 credentials from the environment. Restore
also requires TARGET_SUPABASE_PROJECT_REF plus the target database and/or
Storage environment variables documented in docs/DISASTER_RECOVERY_RUNBOOK.md.

Restore is intentionally limited to a separate Supabase project. It will not
restore over the source project recorded in the snapshot manifest.
USAGE
}

cleanup() {
  local path
  for path in "${temporary_paths[@]:-}"; do
    [[ -n "$path" && -d "$path" && "$path" == *'.firevault-recovery.'* ]] || continue
    rm -rf -- "$path"
  done
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' is not installed."
}

require_environment_names() {
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || fail "Required environment variable ${name} is missing."
  done
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

configure_r2_remote() {
  require_environment_names "${REQUIRED_R2_ENV[@]}"
  validate_identifier "R2_BUCKET" "$R2_BUCKET"
  [[ "$BACKUP_PREFIX" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "$BACKUP_PREFIX" != *..* ]] || \
    fail "BACKUP_PREFIX contains unsupported characters."
  reject_whitespace "R2_ENDPOINT" "$R2_ENDPOINT"
  reject_whitespace "R2_ACCESS_KEY_ID" "$R2_ACCESS_KEY_ID"
  reject_whitespace "R2_SECRET_ACCESS_KEY" "$R2_SECRET_ACCESS_KEY"
  reject_whitespace "BACKUP_ENCRYPTION_PASSWORD" "$BACKUP_ENCRYPTION_PASSWORD"
  reject_whitespace "BACKUP_ENCRYPTION_SALT" "$BACKUP_ENCRYPTION_SALT"
  [[ "$R2_ENDPOINT" =~ ^https://[^/]+/?$ ]] || fail "R2_ENDPOINT must be the account-level HTTPS endpoint without a bucket path."

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
  export RCLONE_CONFIG_R2CRYPT_STRICT_NAMES=true
}

list_completed_snapshots() {
  local listing entry snapshot_id
  listing="$(rclone lsf "r2crypt:${BACKUP_PREFIX}" --dirs-only)"
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -n "$entry" ]] || continue
    snapshot_id="${entry%/}"
    validate_identifier "Snapshot ID" "$snapshot_id"
    if rclone cat "r2crypt:${BACKUP_PREFIX}/${snapshot_id}/_SUCCESS" >/dev/null 2>&1; then
      printf '%s\n' "$snapshot_id"
    fi
  done <<< "$listing"
}

resolve_snapshot_id() {
  local selector="$1"
  local snapshot_id

  if [[ "$selector" == latest ]]; then
    snapshot_id="$(list_completed_snapshots | LC_ALL=C sort | tail -n 1)"
    [[ -n "$snapshot_id" ]] || fail "No completed snapshots were found."
  else
    snapshot_id="${selector#${BACKUP_PREFIX}/}"
    validate_identifier "Snapshot ID" "$snapshot_id"
    rclone cat "r2crypt:${BACKUP_PREFIX}/${snapshot_id}/_SUCCESS" >/dev/null 2>&1 || \
      fail "Snapshot '${snapshot_id}' is missing its _SUCCESS marker."
  fi

  printf '%s\n' "$snapshot_id"
}

verify_checksum_manifest() {
  local database_dir="$1"
  local checksums_file="$database_dir/SHA256SUMS"
  local filename

  [[ -f "$checksums_file" ]] || fail "Snapshot is missing database/SHA256SUMS."
  [[ "$(wc -l < "$checksums_file" | tr -d ' ')" == 3 ]] || fail "SHA256SUMS must contain exactly three entries."

  for filename in roles.sql.gz schema.sql.gz data.sql.gz; do
    [[ -f "$database_dir/$filename" ]] || fail "Snapshot is missing database/${filename}."
    grep -Eq "^[0-9a-fA-F]{64}  ${filename}$" "$checksums_file" || \
      fail "SHA256SUMS has no valid entry for ${filename}."
  done

  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$database_dir" && sha256sum --check SHA256SUMS)
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$database_dir" && shasum -a 256 --check SHA256SUMS)
  else
    fail "Required command 'sha256sum' or 'shasum' is not installed."
  fi

  gzip -t "$database_dir/roles.sql.gz" "$database_dir/schema.sql.gz" "$database_dir/data.sql.gz"
}

verify_storage_payload() {
  local snapshot_dir="$1"
  local manifest_file="$snapshot_dir/manifest.json"
  local bucket_row bucket expected_count expected_bytes stats actual_count actual_bytes

  while IFS= read -r bucket_row || [[ -n "$bucket_row" ]]; do
    [[ -n "$bucket_row" ]] || continue
    bucket="$(jq -er '.name' <<< "$bucket_row")"
    expected_count="$(jq -er '.object_count | numbers' <<< "$bucket_row")"
    expected_bytes="$(jq -er '.bytes | numbers' <<< "$bucket_row")"
    validate_identifier "Storage bucket name" "$bucket"

    if [[ ! -d "$snapshot_dir/storage/$bucket" ]]; then
      [[ "$expected_count" == 0 && "$expected_bytes" == 0 ]] || \
        fail "Downloaded snapshot is missing Storage bucket '${bucket}'."
      continue
    fi

    stats="$(rclone size "$snapshot_dir/storage/$bucket" --json)"
    actual_count="$(jq -er '.count | numbers' <<< "$stats")"
    actual_bytes="$(jq -er '.bytes | numbers' <<< "$stats")"
    [[ "$actual_count" == "$expected_count" ]] || fail "Object-count verification failed for bucket '${bucket}'."
    [[ "$actual_bytes" == "$expected_bytes" ]] || fail "Byte-count verification failed for bucket '${bucket}'."
  done < <(jq -c '.storage.buckets[]' "$manifest_file")
}

verify_snapshot_directory() {
  local snapshot_dir="$1"
  local snapshot_id="$2"
  local manifest_file="$snapshot_dir/manifest.json"
  local expected_path="${BACKUP_PREFIX}/${snapshot_id}"
  local created_at success_value

  [[ -f "$snapshot_dir/_SUCCESS" ]] || fail "Downloaded snapshot is missing _SUCCESS."
  [[ -f "$manifest_file" ]] || fail "Downloaded snapshot is missing manifest.json."

  jq -e \
    --arg expected_path "$expected_path" \
    '.format_version == 1
      and (.created_at | type == "string")
      and (.source.provider == "supabase")
      and (.source.project_ref | type == "string")
      and (.destination.provider == "cloudflare-r2")
      and (.destination.snapshot_path == $expected_path)
      and (.database.checksum_algorithm == "SHA-256")
      and (.storage.bucket_count == (.storage.buckets | length))
      and all(.storage.buckets[];
        (.name | type == "string")
        and (.object_count | type == "number")
        and (.bytes | type == "number"))' \
    "$manifest_file" >/dev/null || fail "Snapshot manifest is invalid or does not match the selected snapshot."

  created_at="$(jq -er '.created_at' "$manifest_file")"
  success_value="$(tr -d '\r\n' < "$snapshot_dir/_SUCCESS")"
  [[ "$success_value" == "$created_at" ]] || fail "_SUCCESS does not match the manifest creation time."

  verify_checksum_manifest "$snapshot_dir/database"
  verify_storage_payload "$snapshot_dir"
  log "Snapshot ${snapshot_id} passed manifest, checksum, gzip, and Storage-size verification."
}

download_snapshot() {
  local snapshot_id="$1"
  local output_dir="$2"
  local output_parent staging_dir

  [[ -n "$output_dir" ]] || fail "--output is required for download."
  [[ ! -e "$output_dir" ]] || fail "Output path already exists: ${output_dir}"
  output_parent="$(dirname "$output_dir")"
  mkdir -p -- "$output_parent"
  staging_dir="$(mktemp -d "${output_parent}/.firevault-recovery.XXXXXX")"
  temporary_paths+=("$staging_dir")

  log "Downloading and decrypting snapshot ${snapshot_id}."
  rclone copy "r2crypt:${BACKUP_PREFIX}/${snapshot_id}" "$staging_dir" \
    --checkers 8 \
    --transfers 4 \
    --retries 3 \
    --low-level-retries 10
  verify_snapshot_directory "$staging_dir" "$snapshot_id"
  mv -- "$staging_dir" "$output_dir"
  log "Verified recovery package written to ${output_dir}."
}

configure_target_storage_remote() {
  require_environment_names TARGET_SUPABASE_PROJECT_REF "${REQUIRED_TARGET_STORAGE_ENV[@]}"
  validate_identifier "TARGET_SUPABASE_PROJECT_REF" "$TARGET_SUPABASE_PROJECT_REF"
  reject_whitespace "TARGET_SUPABASE_STORAGE_REGION" "$TARGET_SUPABASE_STORAGE_REGION"
  reject_whitespace "TARGET_SUPABASE_STORAGE_ACCESS_KEY_ID" "$TARGET_SUPABASE_STORAGE_ACCESS_KEY_ID"
  reject_whitespace "TARGET_SUPABASE_STORAGE_SECRET_ACCESS_KEY" "$TARGET_SUPABASE_STORAGE_SECRET_ACCESS_KEY"

  export RCLONE_CONFIG_TARGETSUPABASE_TYPE=s3
  export RCLONE_CONFIG_TARGETSUPABASE_PROVIDER=Other
  export RCLONE_CONFIG_TARGETSUPABASE_ENV_AUTH=false
  export RCLONE_CONFIG_TARGETSUPABASE_ACCESS_KEY_ID="$TARGET_SUPABASE_STORAGE_ACCESS_KEY_ID"
  export RCLONE_CONFIG_TARGETSUPABASE_SECRET_ACCESS_KEY="$TARGET_SUPABASE_STORAGE_SECRET_ACCESS_KEY"
  export RCLONE_CONFIG_TARGETSUPABASE_ENDPOINT="https://${TARGET_SUPABASE_PROJECT_REF}.storage.supabase.co/storage/v1/s3"
  export RCLONE_CONFIG_TARGETSUPABASE_REGION="$TARGET_SUPABASE_STORAGE_REGION"
  export RCLONE_CONFIG_TARGETSUPABASE_FORCE_PATH_STYLE=true
  export RCLONE_CONFIG_TARGETSUPABASE_LIST_VERSION=2
}

restore_database() {
  local snapshot_dir="$1"
  local sql_dir="$2"
  local target_state

  require_environment_names "${REQUIRED_TARGET_DATABASE_ENV[@]}"
  reject_whitespace "TARGET_SUPABASE_DB_URL" "$TARGET_SUPABASE_DB_URL"
  [[ "$TARGET_SUPABASE_DB_URL" == *"$TARGET_SUPABASE_PROJECT_REF"* ]] || \
    fail "TARGET_SUPABASE_DB_URL does not appear to belong to TARGET_SUPABASE_PROJECT_REF."

  target_state="$(psql --no-psqlrc --tuples-only --no-align \
    --command "SELECT (SELECT count(*) FROM pg_tables WHERE schemaname = 'public') || ':' || (SELECT count(*) FROM auth.users) || ':' || (SELECT count(*) FROM storage.objects);" \
    --dbname "$TARGET_SUPABASE_DB_URL")"
  target_state="$(tr -d '[:space:]' <<< "$target_state")"
  [[ "$target_state" == '0:0:0' ]] || \
    fail "Target project is not blank (public tables:auth users:storage objects = ${target_state})."

  mkdir -p "$sql_dir"
  gzip -dc "$snapshot_dir/database/roles.sql.gz" > "$sql_dir/roles.sql"
  gzip -dc "$snapshot_dir/database/schema.sql.gz" > "$sql_dir/schema.sql"
  gzip -dc "$snapshot_dir/database/data.sql.gz" > "$sql_dir/data.sql"

  log "Restoring roles, schema, and data in one database transaction."
  psql \
    --no-psqlrc \
    --single-transaction \
    --variable ON_ERROR_STOP=1 \
    --file "$sql_dir/roles.sql" \
    --file "$sql_dir/schema.sql" \
    --command 'SET session_replication_role = replica' \
    --file "$sql_dir/data.sql" \
    --dbname "$TARGET_SUPABASE_DB_URL"
  log "Database restore completed."
}

restore_storage() {
  local snapshot_dir="$1"
  local manifest_file="$snapshot_dir/manifest.json"
  local target_buckets_file="$2"
  local bucket_row bucket expected_count expected_bytes stats actual_count actual_bytes

  configure_target_storage_remote
  rclone lsf targetsupabase: --dirs-only > "$target_buckets_file"

  while IFS= read -r bucket_row || [[ -n "$bucket_row" ]]; do
    [[ -n "$bucket_row" ]] || continue
    bucket="$(jq -er '.name' <<< "$bucket_row")"
    expected_count="$(jq -er '.object_count | numbers' <<< "$bucket_row")"
    expected_bytes="$(jq -er '.bytes | numbers' <<< "$bucket_row")"
    grep -Fx -- "${bucket}/" "$target_buckets_file" >/dev/null || \
      fail "Target Storage bucket '${bucket}' does not exist after the database restore."

    if [[ -d "$snapshot_dir/storage/$bucket" ]]; then
      log "Restoring Storage bucket '${bucket}'."
      rclone copy "$snapshot_dir/storage/$bucket" "targetsupabase:${bucket}" \
        --metadata \
        --checkers 8 \
        --transfers 4 \
        --retries 3 \
        --low-level-retries 10
    fi

    stats="$(rclone size "targetsupabase:${bucket}" --json)"
    actual_count="$(jq -er '.count | numbers' <<< "$stats")"
    actual_bytes="$(jq -er '.bytes | numbers' <<< "$stats")"
    [[ "$actual_count" == "$expected_count" ]] || fail "Target object-count verification failed for bucket '${bucket}'."
    [[ "$actual_bytes" == "$expected_bytes" ]] || fail "Target byte-count verification failed for bucket '${bucket}'."
  done < <(jq -c '.storage.buckets[]' "$manifest_file")
  log "Storage restore completed and verified."
}

command_name="${1:-}"
[[ -n "$command_name" ]] || {
  usage
  exit 64
}
shift

snapshot_selector=latest
output_dir=''
restore_phase=all
confirmed_target=''
apply_restore=false

while (($#)); do
  case "$1" in
    --snapshot)
      (($# >= 2)) || fail "--snapshot requires a value."
      snapshot_selector="$2"
      shift 2
      ;;
    --output)
      (($# >= 2)) || fail "--output requires a value."
      output_dir="$2"
      shift 2
      ;;
    --phase)
      (($# >= 2)) || fail "--phase requires a value."
      restore_phase="$2"
      shift 2
      ;;
    --confirm-target-project-ref)
      (($# >= 2)) || fail "--confirm-target-project-ref requires a value."
      confirmed_target="$2"
      shift 2
      ;;
    --apply)
      apply_restore=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

require_command rclone
require_command jq
require_command gzip
require_command grep
configure_r2_remote

case "$command_name" in
  list)
    [[ -z "$output_dir" && "$snapshot_selector" == latest && "$restore_phase" == all && -z "$confirmed_target" && "$apply_restore" == false ]] || \
      fail "The list command does not accept options."
    list_completed_snapshots | LC_ALL=C sort
    ;;
  download)
    [[ "$restore_phase" == all && -z "$confirmed_target" && "$apply_restore" == false ]] || \
      fail "The download command does not accept restore-only options."
    snapshot_id="$(resolve_snapshot_id "$snapshot_selector")"
    download_snapshot "$snapshot_id" "$output_dir"
    ;;
  restore)
    [[ -z "$output_dir" ]] || fail "The restore command does not accept --output."
    require_command psql
    require_environment_names TARGET_SUPABASE_PROJECT_REF
    validate_identifier "TARGET_SUPABASE_PROJECT_REF" "$TARGET_SUPABASE_PROJECT_REF"
    [[ "$restore_phase" == database || "$restore_phase" == storage || "$restore_phase" == all ]] || \
      fail "--phase must be database, storage, or all."
    [[ "$apply_restore" == true ]] || fail "Restore requires --apply."
    [[ "$confirmed_target" == "$TARGET_SUPABASE_PROJECT_REF" ]] || \
      fail "--confirm-target-project-ref must exactly match TARGET_SUPABASE_PROJECT_REF."

    snapshot_id="$(resolve_snapshot_id "$snapshot_selector")"
    recovery_root="$(mktemp -d "${TMPDIR:-/tmp}/.firevault-recovery.XXXXXX")"
    temporary_paths+=("$recovery_root")
    recovery_snapshot="$recovery_root/snapshot"
    download_snapshot "$snapshot_id" "$recovery_snapshot"
    source_project_ref="$(jq -er '.source.project_ref' "$recovery_snapshot/manifest.json")"
    [[ "$TARGET_SUPABASE_PROJECT_REF" != "$source_project_ref" ]] || \
      fail "Refusing to restore over source project ${source_project_ref}; create a separate recovery project."

    if [[ "$restore_phase" == database || "$restore_phase" == all ]]; then
      restore_database "$recovery_snapshot" "$recovery_root/sql"
    fi
    if [[ "$restore_phase" == storage || "$restore_phase" == all ]]; then
      restore_storage "$recovery_snapshot" "$recovery_root/target-buckets.txt"
    fi
    log "Recovery phase '${restore_phase}' completed for target project ${TARGET_SUPABASE_PROJECT_REF}."
    ;;
  *)
    usage
    exit 64
    ;;
esac
