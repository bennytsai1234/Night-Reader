#!/bin/sh
# tool/frame_budget_compare.sh 對照表的測試：用假的測試輸出檢查彙整，ci.yml 會執行。
# 執行：sh tool/frame_budget_compare_test.sh
set -eu

tool="$(cd "$(dirname "$0")" && pwd)/frame_budget_compare.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 兩次改前、兩次改後。「發現→書架」在同一次輸出裡出現兩次，要分開算；
# 「新情境」只有改後才有；尖峰幀的明細行不是摘要行，要略過。
cat > "$work/base-1.log" <<'EOF'
00:01 +0: loading
第一輪 書架→發現：95 幀，中位數 0.3ms，最大 113.6ms，超過 8ms 的 7 幀
  第 0 幀（換頁） 11.2ms：幀前 0.1、幀 10.8、幀後 0.2、非同步 0.2
第一輪 發現→書架：95 幀，中位數 0.3ms，最大 24.5ms，超過 8ms 的 7 幀
第一輪 發現→書架：95 幀，中位數 0.2ms，最大 12.3ms，超過 8ms 的 3 幀
EOF
cat > "$work/base-2.log" <<'EOF'
第一輪 書架→發現：95 幀，中位數 0.5ms，最大 100.0ms，超過 8ms 的 7 幀
第一輪 發現→書架：95 幀，中位數 0.3ms，最大 20.5ms，超過 8ms 的 7 幀
第一輪 發現→書架：95 幀，中位數 0.4ms，最大 10.3ms，超過 8ms 的 3 幀
EOF
cat > "$work/head-1.log" <<'EOF'
第一輪 書架→發現：95 幀，中位數 0.2ms，最大 50.0ms，超過 8ms 的 2 幀
第一輪 發現→書架：95 幀，中位數 0.3ms，最大 9.0ms，超過 8ms 的 1 幀
第一輪 發現→書架：95 幀，中位數 0.2ms，最大 8.0ms，超過 8ms 的 0 幀
新情境：10 幀，中位數 1.0ms，最大 2.0ms，超過 8ms 的 0 幀
EOF
cat > "$work/head-2.log" <<'EOF'
第一輪 書架→發現：95 幀，中位數 0.4ms，最大 40.0ms，超過 8ms 的 2 幀
第一輪 發現→書架：95 幀，中位數 0.3ms，最大 7.0ms，超過 8ms 的 0 幀
第一輪 發現→書架：95 幀，中位數 0.2ms，最大 6.0ms，超過 8ms 的 0 幀
新情境：10 幀，中位數 1.0ms，最大 4.0ms，超過 8ms 的 0 幀
EOF

expected='| 情境 | 最大一幀 改前 → 改後（ms） | 中位數 改前 → 改後（ms） |
|---|---|---|
| 第一輪 書架→發現 | 106.8 (100.0–113.6) → 45.0 (40.0–50.0) | 0.4 → 0.3 |
| 第一輪 發現→書架 | 22.5 (20.5–24.5) → 8.0 (7.0–9.0) | 0.3 → 0.3 |
| 第一輪 發現→書架（第 2 次） | 11.3 (10.3–12.3) → 7.0 (6.0–8.0) | 0.3 → 0.2 |
| 新情境 | — → 3.0 (2.0–4.0) | — → 1.0 |'

if actual=$(bash "$tool" summarize "$work" 2>&1) && [ "$actual" = "$expected" ]; then
  echo 'ok   對照表'
else
  printf 'FAIL 對照表\n  expected:\n%s\n  actual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

mkdir "$work/empty"
: > "$work/empty/base-1.log"
: > "$work/empty/head-1.log"
if bash "$tool" summarize "$work/empty" > /dev/null 2>&1; then
  echo 'FAIL 沒有摘要行時要失敗' >&2
  exit 1
fi
echo 'ok   沒有摘要行時失敗'

# 改前沒有這些測試檔：只有改後的 log 也要印得出表。
mkdir "$work/head-only"
cp "$work/head-1.log" "$work/head-only/"
expected='| 情境 | 最大一幀 改前 → 改後（ms） | 中位數 改前 → 改後（ms） |
|---|---|---|
| 第一輪 書架→發現 | — → 50.0 | — → 0.2 |
| 第一輪 發現→書架 | — → 9.0 | — → 0.3 |
| 第一輪 發現→書架（第 2 次） | — → 8.0 | — → 0.2 |
| 新情境 | — → 2.0 | — → 1.0 |'
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
echo "情境：10 幀，中位數 1.0ms，最大 2.0ms，超過 8ms 的 0 幀"
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
  (cd "$repo" && PATH="$work/bin:$PATH" TMPDIR="$work/tmp" FAKE_FLUTTER=$1 bash "$tool" -n 2 HEAD~1 test/frame_budget/a_test.dart 2>&1)
}
lock="$work/tmp/night-reader-frame-budget.lock"
clean() {
  [ ! -e "$lock" ] && [ "$(git -C "$repo" worktree list | wc -l)" -eq 1 ]
}

if out=$(compare ok) && printf '%s\n' "$out" | grep -q '^| 情境 | 2.0 (2.0–2.0) → 2.0 (2.0–2.0) |' && clean; then
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
if [ "$status" -ne 130 ] || [ "$(printf '%s\n' "$out" | grep -c '第 . 次$')" -ne 1 ] || ! clean; then
  printf 'FAIL Ctrl+C 要停在第一輪（結束碼 %s）\n%s\n' "$status" "$out" >&2
  exit 1
fi
echo 'ok   Ctrl+C 停在第一輪'

# 拿著鎖的程序已經不在：接手。
mkdir "$lock"
sh -c 'echo "$$ 已經結束的量測" > "$1/owner"' _ "$lock"
if out=$(compare ok) && printf '%s\n' "$out" | grep -q '接手它的鎖' && clean; then
  echo 'ok   接手已經不在的程序留下的鎖'
else
  printf 'FAIL 接手失效的鎖\n%s\n' "$out" >&2
  exit 1
fi
