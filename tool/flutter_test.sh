#!/usr/bin/env bash
# 跑 Flutter 測試，輸出只留看得到錯誤的部分：用一般模式（-r expanded），錯誤內容與
# 測試自己印的東西照印；濾掉每項測試的進度行（失敗的 [E] 與最後的總結保留）
# 和 pub 的套件版本清單。不用 -r failures-only：它配 --run-skipped 時會把錯誤一起吞掉。
#
#   tool/flutter_test.sh [flutter test 的參數…]   例：tool/flutter_test.sh test/features/bookmarks
#                                                   tool/flutter_test.sh --run-skipped -t screens test/screens/x_test.dart
# 結束碼照 flutter test。
set -o pipefail
flutter test -r expanded "$@" 2>&1 | awk '
  /available\)$/ { next }
  /^[0-9]+:[0-9]+ \+[0-9]+( ~[0-9]+)?( -[0-9]+)?: / {
    if ($0 ~ /\[E\]$/ || $0 ~ /(All tests passed!|All tests skipped\.|Some tests failed\.)$/) print
    fflush()
    next
  }
  { print; fflush() }
'
