#!/usr/bin/env bash
# 在使用者手機上錄一個場景：開始 Perfetto 系統追蹤（DUR 毫秒），照步驟檔的每一行
# 操作手機（adb shell 指令，或 `sleep 秒數`），拉回追蹤與截圖，列出動畫中的掉幀。
#
# 用法：tool/phone_trace/scene.sh 名稱 步驟檔 [DUR毫秒]
# 輸出：$OUT/scene-名稱.pftrace 與 .png（OUT 預設 $TEMP/night-reader-phone，在 repo 外）。
# 先照 docs/agents/phone.md 連上手機；步驟檔的座標是使用者那支手機（1260×2800）的。
set -e
export MSYS_NO_PATHCONV=1
here="$(cd "$(dirname "$0")" && pwd)"
out="${OUT:-${TEMP:-/tmp}/night-reader-phone}"
mkdir -p "$out"
# MSYS_NO_PATHCONV 關掉了 Git Bash 的路徑轉換，交給 adb 與 python 的路徑要自己轉成 Windows 的。
if command -v cygpath >/dev/null; then here="$(cygpath -m "$here")"; out="$(cygpath -m "$out")"; fi
name="$1"; steps="$2"; dur="${3:-8000}"
dev="/data/misc/perfetto-traces/scene-$name.pftrace"
adb shell rm -f "$dev"
sed "s/duration_ms: 14000/duration_ms: $dur/" "$here/trace.cfg" | adb shell perfetto --background --txt -c - -o "$dev" >/dev/null
sleep 1
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    sleep*) eval "$line" ;;
    *) adb shell "$line" < /dev/null ;;
  esac
done < "$steps"
# 等追蹤寫完。
for _ in $(seq 1 40); do
  if ! adb shell pidof perfetto >/dev/null 2>&1; then break; fi
  sleep 1
done
adb pull "$dev" "$out/scene-$name.pftrace" >/dev/null
adb exec-out screencap -p > "$out/scene-$name.png"
echo "== $name → $out/scene-$name.pftrace"
python "$here/hitches.py" "$out/scene-$name.pftrace" 2>&1 | grep -v Downloading
