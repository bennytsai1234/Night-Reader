#!/bin/sh
# tool/frame_budget_compare.sh 對照表的測試：用假的測試輸出檢查彙整，ci.yml 會執行。
# 執行：sh tool/frame_budget_compare_test.sh
set -eu

tool="$(cd "$(dirname "$0")" && pwd)/frame_budget_compare.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 「發現→書架」在同一次輸出裡出現兩次，要分開算；「新情境」只有改後才有；
# 「舊格式」是改前的量測工具還不會印扣掉後的幀數；尖峰幀的明細行要略過。
cat > "$work/base.log" <<'EOF'
00:01 +0: loading
第一輪 書架→發現：95 幀，中位數 0.3ms，最大 113.6ms，超過 4.2ms 的 7 幀
  動畫中（不含點下去後的第 0 幀） 31 幀，最大 11.2ms（第 3 幀）、超過 4.2ms 的 6 幀（扣掉資料庫、排版切片照實算後 5 幀）；靜止時 63 幀，最大 113.6ms（第 -1 幀）、超過 4.2ms 的 1 幀
  第 3 幀［動］（換頁） 11.2ms：幀前 0.1、幀 10.8、幀後 0.2、非同步 0.2
第一輪 發現→書架：95 幀，中位數 0.3ms，最大 24.5ms，超過 4.2ms 的 7 幀
  動畫中（不含點下去後的第 0 幀） 31 幀，最大 24.5ms（第 2 幀）、超過 4.2ms 的 7 幀（扣掉資料庫、排版切片照實算後 7 幀）；靜止時 63 幀，最大 1.0ms（第 -1 幀）、超過 4.2ms 的 0 幀
第一輪 發現→書架：95 幀，中位數 0.2ms，最大 12.3ms，超過 4.2ms 的 3 幀
  動畫中（不含點下去後的第 0 幀） 31 幀，最大 12.3ms（第 2 幀）、超過 4.2ms 的 3 幀（扣掉資料庫、排版切片照實算後 3 幀）；靜止時 63 幀，最大 1.0ms（第 -1 幀）、超過 4.2ms 的 0 幀
舊格式：95 幀，中位數 0.3ms，最大 20.0ms，超過 8ms 的 2 幀
  動畫中 31 幀，最大 20.0ms（第 2 幀）、超過 8ms 的 2 幀；靜止時 63 幀，最大 1.0ms（第 -1 幀）、超過 8ms 的 0 幀
EOF
cat > "$work/head.log" <<'EOF'
第一輪 書架→發現：95 幀，中位數 0.2ms，最大 50.0ms，超過 4.2ms 的 2 幀
  動畫中（不含點下去後的第 0 幀） 31 幀，最大 4.0ms（第 3 幀）、超過 4.2ms 的 0 幀（扣掉資料庫、排版切片照實算後 0 幀）；靜止時 63 幀，最大 50.0ms（第 -1 幀）、超過 4.2ms 的 2 幀
第一輪 發現→書架：95 幀，中位數 0.3ms，最大 9.0ms，超過 4.2ms 的 1 幀
  動畫中（不含點下去後的第 0 幀） 31 幀，最大 9.0ms（第 2 幀）、超過 4.2ms 的 1 幀（扣掉資料庫、排版切片照實算後 1 幀）；靜止時 63 幀，最大 1.0ms（第 -1 幀）、超過 4.2ms 的 0 幀
第一輪 發現→書架：95 幀，中位數 0.2ms，最大 8.0ms，超過 4.2ms 的 2 幀
  動畫中（不含點下去後的第 0 幀） 31 幀，最大 8.0ms（第 2 幀）、超過 4.2ms 的 2 幀（扣掉資料庫、排版切片照實算後 12 幀）；靜止時 63 幀，最大 1.0ms（第 -1 幀）、超過 4.2ms 的 0 幀
舊格式：95 幀，中位數 0.3ms，最大 3.0ms，超過 4.2ms 的 0 幀
  動畫中（不含點下去後的第 0 幀） 31 幀，最大 3.0ms（第 2 幀）、超過 4.2ms 的 0 幀（扣掉資料庫、排版切片照實算後 0 幀）；靜止時 63 幀，最大 1.0ms（第 -1 幀）、超過 4.2ms 的 0 幀
新情境：10 幀，中位數 1.0ms，最大 2.0ms，超過 4.2ms 的 0 幀
  動畫中（不含點下去後的第 0 幀） 9 幀，最大 2.0ms（第 1 幀）、超過 4.2ms 的 0 幀（扣掉資料庫、排版切片照實算後 0 幀）；靜止時 1 幀，最大 1.0ms（第 -1 幀）、超過 4.2ms 的 0 幀
沒有動畫：10 幀，中位數 1.0ms，最大 9.0ms，超過 4.2ms 的 1 幀
  動畫中（不含點下去後的第 0 幀） 0 幀；靜止時 10 幀，最大 9.0ms（第 0 幀）、超過 4.2ms 的 1 幀
EOF

expected='| 情境 | 動畫中超過 4.2ms 的幀 改前 → 改後 |
|---|---|
| 第一輪 書架→發現 | 5 → 0 |
| 第一輪 發現→書架 | 7 → 1 |
| 第一輪 發現→書架（第 2 次） | 3 → 12 |
| 舊格式 | — → 0 |
| 新情境 | — → 0 |
| 沒有動畫 | — → 0 |'

if actual=$(bash "$tool" summarize "$work" 2>&1) && [ "$actual" = "$expected" ]; then
  echo 'ok   對照表'
else
  printf 'FAIL 對照表\n  expected:\n%s\n  actual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

mkdir "$work/empty"
: > "$work/empty/base.log"
: > "$work/empty/head.log"
if bash "$tool" summarize "$work/empty" > /dev/null 2>&1; then
  echo 'FAIL 沒有摘要行時要失敗' >&2
  exit 1
fi
echo 'ok   沒有摘要行時失敗'

# 改前沒有這些測試檔：只有改後的 log 也要印得出表。
mkdir "$work/head-only"
cp "$work/head.log" "$work/head-only/"
expected='| 情境 | 動畫中超過 4.2ms 的幀 改前 → 改後 |
|---|---|
| 第一輪 書架→發現 | — → 0 |
| 第一輪 發現→書架 | — → 1 |
| 第一輪 發現→書架（第 2 次） | — → 12 |
| 舊格式 | — → 0 |
| 新情境 | — → 0 |
| 沒有動畫 | — → 0 |'
if actual=$(bash "$tool" summarize "$work/head-only" 2>&1) && [ "$actual" = "$expected" ]; then
  echo 'ok   只有改後'
else
  printf 'FAIL 只有改後\n  expected:\n%s\n  actual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

# 整支跑一遍：暫時的 repo 有兩個提交，flutter 換成假的，鎖放在自己的暫存資料夾。
# FAKE_FLUTTER 決定假 flutter 怎麼結束：ok 印一行摘要、fail 印完摘要後失敗、
# interrupt 對整支指令送 Ctrl+C 後自己正常結束（flutter test 收到 Ctrl+C 就是這樣）。
repo="$work/repo"
mkdir -p "$repo/test/frame_budget" "$work/bin" "$work/tmp"
cat > "$work/bin/flutter" <<'EOF'
#!/bin/sh
echo "情境：10 幀，中位數 1.0ms，最大 2.0ms，超過 4.2ms 的 0 幀"
echo "  動畫中（不含點下去後的第 0 幀） 9 幀，最大 2.0ms（第 1 幀）、超過 4.2ms 的 0 幀（扣掉資料庫、排版切片照實算後 0 幀）；靜止時 1 幀，最大 1.0ms（第 -1 幀）、超過 4.2ms 的 0 幀"
case $FAKE_FLUTTER in
  fail) exit 1 ;;
  interrupt) kill -INT "$(cut -d' ' -f1 "$TMPDIR/night-reader-frame-budget.lock/owner")" ;;
esac
EOF
chmod +x "$work/bin/flutter"
(
  cd "$repo"
  git init -q
  echo a > test/frame_budget/a_test.dart
  git add . && git -c user.name=t -c user.email=t@t commit -q -m base
  echo b > test/frame_budget/a_test.dart
  git -c user.name=t -c user.email=t@t commit -q -am head
)
compare() {
  (cd "$repo" && PATH="$work/bin:$PATH" TMPDIR="$work/tmp" FAKE_FLUTTER=$1 bash "$tool" HEAD~1 test/frame_budget/a_test.dart 2>&1)
}
lock="$work/tmp/night-reader-frame-budget.lock"
clean() {
  [ ! -e "$lock" ] && [ "$(git -C "$repo" worktree list | wc -l)" -eq 1 ]
}

if out=$(compare ok) && printf '%s\n' "$out" | grep -q '^| 情境 | 0 → 0 |' && clean; then
  echo 'ok   整支跑完，鎖與暫時的 worktree 都清掉'
else
  printf 'FAIL 整支跑完\n%s\n' "$out" >&2
  exit 1
fi

if out=$(compare fail); then
  printf 'FAIL 測試沒全過要停下來\n%s\n' "$out" >&2
  exit 1
fi
if printf '%s\n' "$out" | grep -q '^|' || ! clean; then
  printf 'FAIL 測試沒全過時不印表、要清乾淨\n%s\n' "$out" >&2
  exit 1
fi
echo 'ok   測試沒全過就停下來，不印表'

out=$(compare interrupt) && status=0 || status=$?
if [ "$status" -ne 130 ] || [ "$(printf '%s\n' "$out" | grep -cE '^  (改前|改後)$')" -ne 1 ] || ! clean; then
  printf 'FAIL Ctrl+C 要停在改前那次（結束碼 %s）\n%s\n' "$status" "$out" >&2
  exit 1
fi
echo 'ok   Ctrl+C 停在改前那次'

# 拿著鎖的程序已經不在：接手。
mkdir "$lock"
sh -c 'echo "$$ 已經結束的量測" > "$1/owner"' _ "$lock"
if out=$(compare ok) && printf '%s\n' "$out" | grep -q '接手它的鎖' && clean; then
  echo 'ok   接手已經不在的程序留下的鎖'
else
  printf 'FAIL 接手失效的鎖\n%s\n' "$out" >&2
  exit 1
fi
