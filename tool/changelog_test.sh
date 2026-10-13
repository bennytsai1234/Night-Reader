#!/bin/sh
# tool/changelog.sh 的測試：在暫存的 Git repo 裡模擬各種推送，ci.yml 會執行。
# 執行：sh tool/changelog_test.sh
set -eu

tool="$(cd "$(dirname "$0")" && pwd)/changelog.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

# expect_output <名稱> <預期輸出> <指令…>：指令要成功，輸出要完全相同。
expect_output() {
  name=$1 expected=$2
  shift 2
  if actual=$("$@" 2>&1) && [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    fail "$name"
    printf '  expected:\n%s\n  actual:\n%s\n' "$expected" "$actual" >&2
  fi
}

expect_success() {
  name=$1
  shift
  if out=$("$@" 2>&1); then pass "$name"; else
    fail "$name"
    printf '%s\n' "$out" >&2
  fi
}

expect_failure() {
  name=$1
  shift
  if out=$("$@" 2>&1); then
    fail "$name"
    printf '%s\n' "$out" >&2
  else pass "$name"; fi
}

# ---- section ----

cat >"$work/CHANGELOG.md" <<'EOF'
# 更新說明

開頭的說明不屬於任何段落。

## 未發布

這次的重點。

- 第一項
### 小標題留在段落裡
- 第二項


## 0.3.4

- 舊版的改動

## 0.3.3
EOF

expect_output 'section: 取「未發布」並去掉前後空行' "$(printf '這次的重點。\n\n- 第一項\n### 小標題留在段落裡\n- 第二項')" \
  sh "$tool" section 未發布 "$work/CHANGELOG.md"
expect_output 'section: 取正式版段落' '- 舊版的改動' \
  sh "$tool" section 0.3.4 "$work/CHANGELOG.md"
expect_output 'section: 空段落印出空字串' '' \
  sh "$tool" section 0.3.3 "$work/CHANGELOG.md"
expect_failure 'section: 找不到標題時失敗' \
  sh "$tool" section 0.3.5 "$work/CHANGELOG.md"
expect_failure 'section: 標題要完全相同' \
  sh "$tool" section 0.3 "$work/CHANGELOG.md"
printf '## 未發布\r\n\r\n- CRLF 換行\r\n## 0.1.0\r\n' >"$work/crlf.md"
expect_output 'section: 接受 CRLF 換行' '- CRLF 換行' \
  sh "$tool" section 未發布 "$work/crlf.md"
expect_output 'section: 「-」讀標準輸入' '- 舊版的改動' \
  sh -c 'sh "$1" section 0.3.4 - <"$2"' _ "$tool" "$work/CHANGELOG.md"

# ---- check ----

repo="$work/repo"
git init -q "$repo"
g() { git -C "$repo" -c user.name=test -c user.email=test@example.com "$@"; }

# commit <訊息> <路徑=內容>…：寫入檔案後提交，印出新提交的 SHA。
commit() {
  message=$1
  shift
  for pair in "$@"; do
    path=${pair%%=*}
    mkdir -p "$repo/$(dirname "$path")"
    printf '%s' "${pair#*=}" >"$repo/$path"
  done
  g add -A
  g commit -q -m "$message"
  g rev-parse HEAD
}

changelog() { printf '# 更新說明\n\n## 未發布\n\n%s\n## 0.3.3\n\n- 上一版\n' "$1"; }
check() { (cd "$repo" && sh "$tool" check "$@"); }

base=$(commit init "pubspec.yaml=version: 0.3.3
" "lib/main.dart=v1" "CHANGELOG.md=$(changelog '')")

docs=$(commit docs "README.md=說明" "docs/adr/0001.md=x" "test/a_test.dart=x" "website/index.html=x")
expect_success 'check: 只改文件、網站、測試不需要寫' check "$base" "$docs"

ci=$(commit ci ".github/workflows/ci.yml=x" ".githooks/pre-push=x" "tool/x.sh=x")
expect_success 'check: 只改 CI、hook、工具腳本不需要寫' check "$base" "$ci"

app=$(commit app "lib/main.dart=v2")
expect_failure 'check: 改到 App 內容但沒寫更新說明時擋下' check "$base" "$app"
expect_success 'check: 新分支（起點全為 0）不檢查' check 0000000000000000000000000000000000000000 "$app"
expect_failure 'check: 本機沒有起點提交時失敗' check 1234567890123456789012345678901234567890 "$app"

noted=$(commit notes "CHANGELOG.md=$(changelog '- 新功能
')")
expect_success 'check: 寫進「未發布」後放行' check "$base" "$noted"

# 從 noted 分出去：改 App 又把非空的「未發布」刪光，版號沒升。
g checkout -q -b emptied "$noted"
emptied=$(commit emptied "lib/main.dart=v2b" "CHANGELOG.md=$(changelog '')")
expect_failure 'check: 改到 App 內容卻把「未發布」清空時擋下' check "$noted" "$emptied"
g checkout -q -

# 正式版：版號 commit 把「未發布」改名成「0.3.4」，上面留空的「未發布」。
bump=$(commit 'release: bump version to 0.3.4' "pubspec.yaml=version: 0.3.4
" "CHANGELOG.md=$(printf '# 更新說明\n\n## 未發布\n\n## 0.3.4\n\n- 新功能\n\n## 0.3.3\n\n- 上一版\n')")
expect_success 'check: 版號 commit 單獨推送時放行' check "$noted" "$bump"
expect_success 'check: 功能與版號 commit 一起推送時放行' check "$base" "$bump"

bare_bump=$(commit 'release: bump version to 0.3.5' "pubspec.yaml=version: 0.3.5
" "lib/main.dart=v3")
expect_failure 'check: 版號 commit 沒有把「未發布」改成新版號時擋下' check "$bump" "$bare_bump"

broken=$(commit broken "lib/main.dart=v4" "CHANGELOG.md=# 更新說明
")
expect_failure 'check: CHANGELOG.md 沒有「未發布」標題時擋下' check "$bare_bump" "$broken"

# App 行為沒變的提交在 trailer 標 Release-Notes: none。
g checkout -q -b exempt "$noted"
comment=$(commit "$(printf 'docs: fix a comment\n\nRelease-Notes: none\nCo-Authored-By: x <x@example.com>')" "lib/main.dart=v2 // 註解")
expect_success 'check: 標了 Release-Notes: none 的提交不需要寫' check "$noted" "$comment"
in_body=$(commit "$(printf 'fix: change\n\nRelease-Notes: none 寫在內文不算\n\nCo-Authored-By: x <x@example.com>')" "lib/main.dart=v5")
expect_failure 'check: 不在 trailer 的 Release-Notes 不算' check "$comment" "$in_body"
g checkout -q -b mixed "$comment"
mixed=$(commit fix "lib/other.dart=x")
expect_failure 'check: 同一次推送裡還有沒標的 App 提交時擋下' check "$noted" "$mixed"
g checkout -q -

if [ "$failures" -ne 0 ]; then
  echo "changelog_test: $failures 項失敗" >&2
  exit 1
fi
echo "changelog_test: 全部通過"
