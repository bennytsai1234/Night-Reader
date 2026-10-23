#!/usr/bin/env bash
# 量改動前後每一幀的成本（ADR 0018、CODING_STANDARDS.md「動畫」）。
#
#   bash tool/frame_budget_compare.sh [-n 次數] <改前的提交> <test/frame_budget/ 的測試檔>...
#
# 例：bash tool/frame_budget_compare.sh origin/beta test/frame_budget/reader_interactions_frame_budget_test.dart
#
# 把 <改前的提交> 開在暫時的 worktree，和目前的工作目錄（含還沒 commit 的改動）交錯各跑
# n 次（預設 3），印出一張 Markdown 表：每個情境「最大一幀」與「中位數」在 n 次裡的中位數，
# 括號裡是 n 次最大一幀的範圍。表可以直接貼進 commit message。測試檔路徑相對於 repo 根目錄；
# 改前沒有的測試檔只跑改後。任何一次測試沒有全過就停下來，不印表。
#
# - 全機同時只跑一個量測：別的 session 正在用這支指令時排隊等它結束。電腦上還有其他
#   flutter_tester 在跑（別人直接跑 flutter test）時只提醒，數字可能偏高；不結束任何程序。
# - FRAME_ATTRIBUTE=1 照樣傳下去，但歸因本身會讓數字變大，只拿來找是誰，不拿來比前後。
# - 每次的完整輸出留在最後印出的資料夾，看尖峰幀細節用；看完刪掉。
#
#   bash tool/frame_budget_compare.sh summarize <資料夾>
#     只重印那個資料夾裡 base-*.log、head-*.log 的對照表。
#
# 測試：sh tool/frame_budget_compare_test.sh
set -euo pipefail

# 從 describeFrames 的摘要行（「<情境>：N 幀，中位數 Xms，最大 Yms，超過 Zms 的 K 幀」）
# 收集兩邊每次的數字，印成對照表。
summarize() {
  local dir=$1 logs=()
  # 改前沒有這些測試檔時只有改後的 log；一份都沒有時 awk 會改讀標準輸入，先擋下來。
  shopt -s nullglob
  logs=("$dir"/base-*.log "$dir"/head-*.log)
  shopt -u nullglob
  if [ ${#logs[@]} -eq 0 ]; then
    echo "$dir 裡沒有 base-*.log 或 head-*.log" >&2
    return 1
  fi
  LC_ALL=C awk '
    function median(list,    v, n, i, j, t) {
      n = split(list, v, " ")
      for (i = 2; i <= n; i++) for (j = i; j > 1 && v[j - 1] + 0 > v[j] + 0; j--) { t = v[j]; v[j] = v[j - 1]; v[j - 1] = t }
      return n % 2 ? v[(n + 1) / 2] : (v[n / 2] + v[n / 2 + 1]) / 2
    }
    function range(list,    v, n, i, lo, hi) {
      n = split(list, v, " ")
      if (n < 2) return ""
      lo = hi = v[1]
      for (i = 2; i <= n; i++) { if (v[i] + 0 < lo + 0) lo = v[i]; if (v[i] + 0 > hi + 0) hi = v[i] }
      return sprintf(" (%s–%s)", lo, hi)
    }
    function cell(side, label, what) {
      if (!((side, label) in max)) return "—"
      return what == "max" ? sprintf("%.1f%s", median(max[side, label]), range(max[side, label])) : sprintf("%.1f", median(med[side, label]))
    }
    FNR == 1 { side = FILENAME ~ /base-[0-9]+\.log$/ ? "base" : "head"; split("", occ) }
    match($0, /：[0-9]+ 幀，中位數 [0-9.]+ms，最大 [0-9.]+ms，/) {
      label = substr($0, 1, RSTART - 1)
      # 同一次輸出裡同名的情境（例如來回兩次「發現→書架」）照出現順序分開。
      if (++occ[label] > 1) label = label "（第 " occ[label] " 次）"
      rest = substr($0, RSTART)
      gsub(/[^0-9.]+/, " ", rest)
      split(rest, num, " ")
      if (!(label in seen)) { seen[label] = 1; order[++count] = label }
      med[side, label] = med[side, label] " " num[2]
      max[side, label] = max[side, label] " " num[3]
    }
    END {
      if (!count) { print "輸出裡沒有 describeFrames 的摘要行" > "/dev/stderr"; exit 1 }
      print "| 情境 | 最大一幀 改前 → 改後（ms） | 中位數 改前 → 改後（ms） |"
      print "|---|---|---|"
      for (i = 1; i <= count; i++) {
        l = order[i]
        printf "| %s | %s → %s | %s → %s |\n", l, cell("base", l, "max"), cell("head", l, "max"), cell("base", l, "med"), cell("head", l, "med")
      }
    }
  ' "${logs[@]}"
}

if [ "${1:-}" = summarize ]; then
  summarize "$2"
  exit
fi

runs=3
if [ "${1:-}" = -n ]; then
  runs=$2
  shift 2
fi
if [ $# -lt 2 ]; then
  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
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
  local side=$1 i=$2 dir=$3 present=() f busy
  for f in "${files[@]}"; do
    [ -f "$dir/$f" ] && present+=("$f")
  done
  if [ ${#present[@]} -eq 0 ]; then
    echo "  $side 第 $i 次：沒有這些測試檔，跳過" >&2
    return
  fi
  busy=$(others)
  [ "${busy:-0}" -gt 0 ] && echo "  提醒：電腦上還有 $busy 個 flutter_tester 在跑，這次的數字可能偏高" >&2
  echo "  $side 第 $i 次" >&2
  # 摘要在測試的檢查之前印出，沒全過的那次數字可能是沒量完的，不算進表。
  if ! (cd "$dir" && flutter test --run-skipped -t frame_budget "${present[@]}") > "$out/$side-$i.log" 2>&1; then
    mv "$out/$side-$i.log" "$out/failed-$side-$i.log"
    echo "  $side 第 $i 次測試沒有全過，停下來；看 $out/failed-$side-$i.log" >&2
    exit 1
  fi
}

echo "改前 $(git log -1 --format='%h %s' "$base_commit")，改後是目前的工作目錄，各跑 $runs 次" >&2
for i in $(seq 1 "$runs"); do
  # 交錯順序，讓電腦變熱、背景工作這類隨時間變化的干擾平均落在兩邊。
  if [ $((i % 2)) -eq 1 ]; then
    run base "$i" "$base"
    run head "$i" "$root"
  else
    run head "$i" "$root"
    run base "$i" "$base"
  fi
done

summarize "$out"
echo "完整輸出：$out（看完刪掉）" >&2
