#!/usr/bin/env bash
# 依序錄每一區（淺色、深色），每區錄完就做成儀表板頁、刪掉原始畫面。
# 用法：bash run_all.sh [區 ...]（預設全部）
set -u
cd "D:/Migrated/Desktop/Folder/product/Night-Reader" || exit 1
export TEMP='D:\nr-survey\tmp' TMP='D:\nr-survey\tmp'
unset SURVEY_DRY
mkdir -p /d/nr-survey/tmp /d/nr-survey/logs
areas=("$@")
[ ${#areas[@]} -eq 0 ] && areas=(tabs launch shelf book reader search explore download sources mine mine2)
total=${#areas[@]}
i=0
for area in "${areas[@]}"; do
  i=$((i + 1))
  for mode in light dark; do
    echo "AREA $i/$total $area $mode 開始 $(date +%H:%M:%S)"
    SURVEY_MODE=$mode flutter test "test/_screens/survey/${area}_survey_test.dart" \
      -r failures-only --timeout 30m > "/d/nr-survey/logs/$area-$mode.log" 2>&1
    status=$?
    grep -E "^SURVEY|Some tests failed|EXCEPTION|Expected:|Test failed" "/d/nr-survey/logs/$area-$mode.log"
    echo "AREA $i/$total $area $mode 結束 exit=$status $(date +%H:%M:%S)"
  done
  python /d/nr-survey/tools/make_pages.py "$area" 2>&1 | grep -E "^PAGE|Error|缺少"
done
python /d/nr-survey/tools/make_pages.py --overview
echo "ALL DONE"
