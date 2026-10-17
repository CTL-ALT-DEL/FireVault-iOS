#!/usr/bin/env bash
set -Eeuo pipefail
readonly project_root="$(cd "$(dirname "$0")/.." && pwd)"
export FIREVAULT_TEST_RCLONE="${FIREVAULT_TEST_RCLONE:-$(command -v rclone || true)}"
python3 "$project_root/scripts/tests/test_incremental_backup.py"
