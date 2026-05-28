#!/usr/bin/env bash
set -euo pipefail

START="${1:-${SOURCE_START:-0}}"
LIMIT="${2:-${SOURCE_LIMIT:-10}}"
TIMEOUT_SECONDS="${SOURCE_TIMEOUT_SECONDS:-20}"
CONCURRENCY="${SOURCE_CONCURRENCY:-6}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

quickjs_lib="$("${SCRIPT_DIR}/with_quickjs_env.sh" python3 - <<'PY'
import os
print(os.environ.get("LIBQUICKJSC_TEST_PATH", ""))
PY
)"

echo "[source-validation] start=${START} limit=${LIMIT}"
echo "[source-validation] timeout=${TIMEOUT_SECONDS}s"
echo "[source-validation] concurrency=${CONCURRENCY}"
if [[ -n "${quickjs_lib}" ]]; then
  echo "[source-validation] quickjs=$(dirname "${quickjs_lib}")"
else
  echo "[source-validation] quickjs=not-found"
fi

SOURCE_START="${START}" \
SOURCE_LIMIT="${LIMIT}" \
SOURCE_TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" \
SOURCE_CONCURRENCY="${CONCURRENCY}" \
  "${SCRIPT_DIR}/flutter_test_with_quickjs.sh" tool/source_batch_validation_test.dart
