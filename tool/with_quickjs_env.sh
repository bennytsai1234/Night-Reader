#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 64
fi

find_quickjs_lib() {
  find "${HOME}/.pub-cache" \
    -path '*flutter_js*/linux/shared/libquickjs_c_bridge_plugin.so' \
    -print 2>/dev/null \
    | sort \
    | tail -n 1
}

quickjs_lib="${LIBQUICKJSC_TEST_PATH:-}"
if [[ -z "${quickjs_lib}" ]]; then
  quickjs_lib="$(find_quickjs_lib || true)"
fi

if [[ -n "${quickjs_lib}" && -f "${quickjs_lib}" ]]; then
  export LIBQUICKJSC_TEST_PATH="${quickjs_lib}"
  export LD_LIBRARY_PATH="$(dirname "${quickjs_lib}")${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
  echo "[quickjs] using ${LIBQUICKJSC_TEST_PATH}" >&2
else
  echo "[quickjs] not found; continuing without QuickJS test runtime" >&2
fi

exec "$@"
