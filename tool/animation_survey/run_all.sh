#!/usr/bin/env bash
# 依序錄每一區（淺色、深色），每區錄完就做成儀表板頁、刪掉原始畫面。
# 用法：bash tool/animation_survey/run_all.sh [區 ...]（預設全部）
# 錄影與頁面放在 NR_SURVEY_ROOT（沒設時有 D 槽用 D:/nr-survey，沒有就用系統暫存區的
# nr-survey）；一段錄影約 80MB，錄完一區就只留頁面。
set -u
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/../.." || exit 1
if [ -z "${NR_SURVEY_ROOT:-}" ]; then
  if [ -d /d ]; then NR_SURVEY_ROOT='D:/nr-survey'; else NR_SURVEY_ROOT="$(cygpath -m "$TEMP")/nr-survey"; fi
fi
export NR_SURVEY_ROOT
root=$(cygpath -u "$NR_SURVEY_ROOT")
export TEMP="$(cygpath -w "$root/tmp")" TMP="$(cygpath -w "$root/tmp")"
unset SURVEY_DRY
mkdir -p "$root/tmp" "$root/logs"
areas=("$@")
[ ${#areas[@]} -eq 0 ] && areas=(tabs launch shelf book reader search explore download sources mine mine2)
total=${#areas[@]}
i=0
for area in "${areas[@]}"; do
  i=$((i + 1))
  for mode in light dark; do
    echo "AREA $i/$total $area $mode 開始 $(date +%H:%M:%S)"
    SURVEY_MODE=$mode flutter test "test/_screens/survey/${area}_survey_test.dart" \
      -r failures-only --timeout 30m > "$root/logs/$area-$mode.log" 2>&1
    status=$?
    grep -E "^SURVEY|Some tests failed|EXCEPTION|Expected:|Test failed" "$root/logs/$area-$mode.log"
    echo "AREA $i/$total $area $mode 結束 exit=$status $(date +%H:%M:%S)"
  done
  python "$here/make_pages.py" "$area" 2>&1 | grep -E "^PAGE|Error|缺少"
done
python "$here/make_pages.py" --overview
python "$here/overview.py"
echo "ALL DONE"
