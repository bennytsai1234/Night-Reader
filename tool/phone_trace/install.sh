#!/usr/bin/env bash
# 用 adb 把 APK 裝到使用者手機，vivo 跳出的安裝確認頁（「安全守護提示您」）自己按：
# 每秒讀一次畫面（uiautomator dump），勾上「已瞭解應用程式的風險偵測結果」，
# 再點「繼續安裝」那個字的位置（字本身不可點，點下去由包著它的按鈕接）。
#
# 用法：tool/phone_trace/install.sh app.apk
set -e
export MSYS_NO_PATHCONV=1
apk="$1"
command -v cygpath >/dev/null && apk="$(cygpath -m "$apk")"
log="${TEMP:-/tmp}/night-reader-install.log"
adb install -r "$apk" > "$log" 2>&1 &
pid=$!

# 畫面上 text 符合 $2 的第一個節點，印出它的中心座標；$1 是 dump 出來的 XML。
center() {
  printf '%s' "$1" | tr '>' '\n' | grep -E "text=\"($2)\"" | head -1 \
    | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' \
    | awk '{ print int(($1 + $3) / 2), int(($2 + $4) / 2) }'
}

while kill -0 "$pid" 2>/dev/null; do
  sleep 1
  xml="$(adb exec-out uiautomator dump /dev/tty 2>/dev/null || true)"
  if printf '%s' "$xml" | grep -q 'text="已瞭解應用程式的風險偵測結果"[^>]*checked="false"\|checked="false"[^>]*text="已瞭解應用程式的風險偵測結果"'; then
    adb shell input tap $(center "$xml" '已瞭解應用程式的風險偵測結果')
    echo '勾了已瞭解風險'
    continue
  fi
  at="$(center "$xml" '繼續安裝|继续安装|仍然安裝|仍然安装')"
  if [ -n "$at" ]; then
    adb shell input tap $at
    echo "點了繼續安裝（$at）"
  fi
done
wait "$pid"
status=$?
cat "${TEMP:-/tmp}/night-reader-install.log" | tail -2
exit $status
