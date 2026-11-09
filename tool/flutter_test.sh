#!/usr/bin/env bash
# 跑 Flutter 測試，輸出只留看得到錯誤的部分：用一般模式（-r expanded），錯誤內容與
# 測試自己印的東西照印；濾掉每項測試的進度行（失敗的 [E] 與最後的總結保留）
# 和 pub 的套件版本清單。不用 -r failures-only：它配 --run-skipped 時會把錯誤一起吞掉。
#
# 整次執行超過 FLUTTER_TEST_WALL（預設 20m，0 是不限）就停掉：元件測試等不到回覆
# 時會一直卡著，--timeout 停不了它。沒跑完時（卡住被停、或測試程序自己掛掉）最後印出
# 當時在跑的那一項。
#
#   tool/flutter_test.sh [flutter test 的參數…]   例：tool/flutter_test.sh test/features/bookmarks
#                                                   tool/flutter_test.sh --run-skipped -t screens test/screens/x_test.dart
#                                                   FLUTTER_TEST_WALL=60m tool/flutter_test.sh test/frame_budget
# 結束碼照 flutter test；超過時間是 124。
set -o pipefail
wall="${FLUTTER_TEST_WALL:-20m}"
runner=(flutter test -r expanded "$@")
if [ "$wall" != "0" ]; then
  runner=(timeout -k 10s "$wall" "${runner[@]}")
fi
"${runner[@]}" 2>&1 | awk -v wall="$wall" '
  /available\)$/ { next }
  /^[0-9]+:[0-9]+ \+[0-9]+( ~[0-9]+)?( -[0-9]+)?: / {
    last = $0
    if ($0 ~ /(All tests passed!|All tests skipped\.|Some tests failed\.)$/) done = 1
    if ($0 ~ /\[E\]$/ || done) print
    fflush()
    next
  }
  { print; fflush() }
  END {
    if (!done && last != "") {
      print "flutter_test.sh: 測試沒有跑完（超過 " wall " 會被停掉）。最後在跑："
      print last
    }
  }
'
