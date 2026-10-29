#!/usr/bin/env bash
# 量改動前後每一幀的成本（ADR 0018、CODING_STANDARDS.md「動畫」）。
#
#   bash tool/frame_budget_compare.sh <改前的提交> <test/frame_budget/ 的測試檔>...
#
# 例：bash tool/frame_budget_compare.sh origin/beta test/frame_budget/reader_interactions_frame_budget_test.dart
#
# 把 <改前的提交> 開在暫時的 worktree，和目前的工作目錄（含還沒 commit 的改動）各跑一次，
# 印出一張 Markdown 表：每個情境動畫在動的時候，扣掉測試的資料庫、排版切片照實算後還超過
# 上限（電腦 4.2ms）的幀數（ADR 0036）。點下去的那一幀與預留停頓不算；最大一幀降了但還
# 超過，一樣是掉幀，表上不列。表可以直接貼進 commit message。測試檔路徑相對於 repo 根目錄；
# 改前沒有的測試檔只跑改後，改前的量測工具還不會印這個數字時那一格是「—」。測試沒有全過
# 就停下來，不印表。
#
# 只跑一次：數字有疑問時，打開完整輸出看那幾幀落在哪一段、在做什麼工作，不重跑。
#
# - 全機同時只跑一個量測：別的 session 正在用這支指令時排隊等它結束。電腦上還有其他
#   flutter_tester 在跑（別人直接跑 flutter test）時只提醒，數字可能偏高；不結束任何程序。
# - FRAME_ATTRIBUTE=1 照樣傳下去，但歸因本身會讓數字變大，只拿來找是誰，不拿來比前後。
# - 兩邊的完整輸出（base.log、head.log）留在最後印出的資料夾，看每一幀的細節用；看完刪掉。
#
#   bash tool/frame_budget_compare.sh summarize <資料夾>
#     只重印那個資料夾裡 base.log、head.log 的對照表。
#
# 測試：sh tool/frame_budget_compare_test.sh
set -euo pipefail

# 從 describeFrames 的摘要（「<情境>：N 幀，…」與下一行「  動畫中…（扣掉資料庫、排版切片
# 照實算後 K 幀）…」）收集兩邊的 K，印成對照表。
summarize() {
  local dir=$1 logs=() side
  # 改前沒有這些測試檔時只有改後的 log；一份都沒有時 awk 會改讀標準輸入，先擋下來。
  for side in base head; do
    [ -f "$dir/$side.log" ] && logs+=("$dir/$side.log")
  done
  if [ ${#logs[@]} -eq 0 ]; then
    echo "$dir 裡沒有 base.log 或 head.log" >&2
    return 1
  fi
  LC_ALL=C awk '
    function cell(side, label) { return (side, label) in over ? over[side, label] : "—" }
    FNR == 1 { side = FILENAME ~ /base\.log$/ ? "base" : "head"; split("", occ); label = "" }
    match($0, /：[0-9]+ 幀，中位數 [0-9.]+ms，最大 [0-9.]+ms，/) {
      label = substr($0, 1, RSTART - 1)
      # 同一次輸出裡同名的情境（例如來回兩次「發現→書架」）照出現順序分開。
      if (++occ[label] > 1) label = label "（第 " occ[label] " 次）"
      if (!(label in seen)) { seen[label] = 1; order[++count] = label }
      next
    }
    label != "" && match($0, /扣掉資料庫、排版切片照實算後 [0-9]+ 幀/) {
      rest = substr($0, RSTART, RLENGTH)
      gsub(/[^0-9]+/, "", rest)
      over[side, label] = rest
      label = ""
    }
    # 整段沒有動畫在動的幀時，摘要只印「0 幀」。
    label != "" && /^  動畫中（不含點下去後的第 0 幀） 0 幀；/ { over[side, label] = 0; label = "" }
    END {
      if (!count) { print "輸出裡沒有 describeFrames 的摘要行" > "/dev/stderr"; exit 1 }
      print "| 情境 | 動畫中超過 4.2ms 的幀 改前 → 改後 |"
      print "|---|---|"
      for (i = 1; i <= count; i++) {
        l = order[i]
        printf "| %s | %s → %s |\n", l, cell("base", l), cell("head", l)
      }
    }
  ' "${logs[@]}"
}

if [ "${1:-}" = summarize ]; then
  summarize "$2"
  exit
fi

if [ $# -lt 2 ]; then
  sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
ref=$1
shift
files=("$@")

root=$(git rev-parse --show-toplevel)
cd "$root"
base_commit=$(git rev-parse --verify "$ref^{commit}")
tmp=${TMPDIR:-/tmp}
lock="$tmp/night-reader-frame-budget.lock"
out=$(mktemp -d "$tmp/nr-frame-budget-XXXXXX")
base="$out/base"

# 清理在 set -e 底下也要每一步都做到：worktree 刪不掉時照樣放掉鎖。
cleanup() {
  set +e
  if [ -d "$base" ] && ! git worktree remove --force "$base" 2>/dev/null; then
    echo "暫時的 worktree 刪不掉，手動刪：$base（再跑 git worktree prune）" >&2
  fi
  [ "$(cat "$lock/owner" 2>/dev/null)" = "$owner" ] && rm -rf "$lock"
}
owner="$$ $root $(date '+%m-%d %H:%M')"
trap cleanup EXIT
# flutter test 收到 Ctrl+C 會自己正常結束，bash 就不會跟著停；明確結束，不再跑下一輪。
trap 'echo "中斷了" >&2; exit 130' INT TERM

# 鎖是一個資料夾：mkdir 不是成功就是已經存在，兩個 session 不會同時拿到。
# 拿著鎖的程序已經不在（被中斷），或建好資料夾卻沒寫進擁有者就停住超過一分鐘，就接手。
stale() {
  local holder pid
  holder=$(cat "$lock/owner" 2>/dev/null || true)
  pid=${holder%% *}
  if [ -n "$pid" ]; then
    ! kill -0 "$pid" 2>/dev/null
  else
    [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]
  fi
}
# 接手也要互斥：兩個等待的人同時看到舊鎖失效時，後刪的那個會刪掉先接手那個剛拿到的鎖。
# 拿到 reclaim 的人在裡面重新確認一次才刪；鎖只有 reclaim 的持有者會刪，確認後不會再換手。
reclaim() {
  mkdir "$lock.reclaim" 2>/dev/null || {
    # 持有 reclaim 的程序在這幾毫秒裡被中斷，留下的資料夾一分鐘後清掉。
    [ -n "$(find "$lock.reclaim" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$lock.reclaim" 2>/dev/null
    return 1
  }
  local took=1
  if stale; then
    echo "上一個量測（$(cat "$lock/owner" 2>/dev/null || echo 沒有記下是誰)）已經不在了，接手它的鎖" >&2
    rm -rf "$lock"
    took=0
  fi
  rmdir "$lock.reclaim"
  return $took
}
waited=""
until mkdir "$lock" 2>/dev/null; do
  stale && reclaim && continue
  [ -n "$waited" ] || echo "等別的量測結束：$(cat "$lock/owner" 2>/dev/null)" >&2
  waited=1
  sleep 10
done
echo "$owner" > "$lock/owner"

git worktree add --detach -q "$base" "$base_commit"
# 新 worktree 的 sqlite3 原生函式庫照 AGENTS.md「環境」的做法沿用這裡的快取，不重新下載。
if [ -d .dart_tool/hooks_runner/shared/sqlite3 ]; then
  mkdir -p "$base/.dart_tool/hooks_runner/shared"
  cp -R .dart_tool/hooks_runner/shared/sqlite3 "$base/.dart_tool/hooks_runner/shared/"
fi

others() {
  if command -v tasklist.exe >/dev/null 2>&1; then
    tasklist.exe //FI "IMAGENAME eq flutter_tester.exe" //NH 2>/dev/null | grep -c flutter_tester || true
  else
    pgrep -c flutter_tester 2>/dev/null || true
  fi
}

run() {
  local side=$1 name=$2 dir=$3 present=() f busy
  for f in "${files[@]}"; do
    [ -f "$dir/$f" ] && present+=("$f")
  done
  if [ ${#present[@]} -eq 0 ]; then
    echo "  $name：沒有這些測試檔，跳過" >&2
    return
  fi
  busy=$(others)
  [ "${busy:-0}" -gt 0 ] && echo "  提醒：電腦上還有 $busy 個 flutter_tester 在跑，這次的數字可能偏高" >&2
  echo "  $name" >&2
  # 摘要在測試的檢查之前印出，沒全過的那次數字可能是沒量完的，不算進表。
  if ! (cd "$dir" && flutter test --run-skipped -t frame_budget "${present[@]}") > "$out/$side.log" 2>&1; then
    mv "$out/$side.log" "$out/failed-$side.log"
    echo "  $name的測試沒有全過，停下來；看 $out/failed-$side.log" >&2
    exit 1
  fi
}

echo "改前 $(git log -1 --format='%h %s' "$base_commit")，改後是目前的工作目錄，各跑一次" >&2
run base 改前 "$base"
run head 改後 "$root"

summarize "$out"
echo "完整輸出：$out（看完刪掉）" >&2
