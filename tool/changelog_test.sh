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
app_files() { (cd "$repo" && sh "$tool" app-files "$@"); }

base=$(commit init "pubspec.yaml=version: 0.3.3
" "lib/main.dart=v1" "CHANGELOG.md=$(changelog '')")

docs=$(commit docs "README.md=說明" "docs/adr/0001.md=x" "test/a_test.dart=x" "website/index.html=x")
expect_success 'check: 只改文件、網站、測試不需要寫' check "$base" "$docs"

ci=$(commit ci ".github/workflows/ci.yml=x" ".github/workflows/website-deploy.yml=x" ".githooks/pre-push=x" "tool/x.sh=x")
expect_success 'check: 只改 CI、hook、工具腳本不需要寫' check "$base" "$ci"
expect_output 'app-files: 只改文件、測試、CI、hook、工具腳本時不印' '' app_files "$base" "$ci"

g checkout -q -b build "$ci"
build=$(commit build ".github/workflows/android-release.yml=x")
expect_failure 'check: 改建置 APK 的 workflow 算 App 內容' check "$base" "$build"
expect_output 'app-files: 印出改到的 App 內容檔案' '.github/workflows/android-release.yml' app_files "$base" "$build"
g checkout -q -

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

# 測試版說明只取新增或改寫的條列：只改介紹時說明會是空的，要擋下。
g checkout -q -b intro_only "$noted"
intro_only=$(commit intro "lib/main.dart=v2c" "CHANGELOG.md=$(changelog '新的介紹。

- 新功能
')")
expect_failure 'check: 只改介紹、條列沒變時擋下' check "$noted" "$intro_only"
g checkout -q -

# 只刪了條列（推翻剛加的功能）時沒有新條列，照樣放行（ADR 0010）。
g checkout -q -b removed_only "$noted"
commit two "CHANGELOG.md=$(changelog '- 新功能
- 要推翻的功能
')" >/dev/null
two=$(g rev-parse HEAD)
removed_only=$(commit drop "lib/main.dart=v2d" "CHANGELOG.md=$(changelog '- 新功能
')")
expect_success 'check: 只刪條列時放行' check "$two" "$removed_only"
g checkout -q -

# 子條列算在上面那一條裡：只在既有條列底下加子條列也算改寫。
g checkout -q -b nested "$noted"
nested_base=$(commit parent "CHANGELOG.md=$(changelog '- 一批設定：
  - 第一個
- 另一項
')")
nested=$(commit child "lib/main.dart=v2e" "CHANGELOG.md=$(changelog '- 一批設定：
  - 第一個
  - 第二個
- 另一項
')")
expect_success 'check: 只加子條列時放行' check "$nested_base" "$nested"
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

# App 行為沒變的提交單獨一行標 Release-Notes: none。
g checkout -q -b exempt "$noted"
comment=$(commit "$(printf 'docs: fix a comment\n\nRelease-Notes: none\nCo-Authored-By: x <x@example.com>')" "lib/main.dart=v2 // 註解")
expect_success 'check: 標了 Release-Notes: none 的提交不需要寫' check "$noted" "$comment"
expect_output 'app-files: 標了 Release-Notes: none 的提交不算' '' app_files "$noted" "$comment"
squashed=$(commit "$(printf 'fix(ci): squash 合併\n\nApp 內容沒變。\n\nRelease-Notes: none\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')" "lib/main.dart=v2 // 註解 2")
expect_success 'check: Release-Notes: none 後面還有一段時照樣算' check "$comment" "$squashed"
in_body=$(commit "$(printf 'fix: change\n\nRelease-Notes: none 寫在內文不算\n\nCo-Authored-By: x <x@example.com>')" "lib/main.dart=v5")
expect_failure 'check: 不是單獨一行的 Release-Notes 不算' check "$squashed" "$in_body"
g checkout -q -b mixed "$comment"
mixed=$(commit fix "lib/other.dart=x")
expect_failure 'check: 同一次推送裡還有沒標的 App 提交時擋下' check "$noted" "$mixed"
g checkout -q -

# 改了又改回來，另有一個標了 none 的 App 提交讓整段比起來還有 App 差異。
g checkout -q -b reverted "$noted"
commit change "lib/main.dart=v9" >/dev/null
commit revert "lib/main.dart=v2" >/dev/null
reverted=$(commit "$(printf 'docs: comment\n\nRelease-Notes: none')" "lib/comment.dart=// 註解")
expect_output 'app-files: 改了又改回來的檔案不算' '' app_files "$noted" "$reverted"
expect_success 'check: 改了又改回來不需要寫' check "$noted" "$reverted"
g checkout -q -

# 合併提交：兩邊分支只改文件與一個 App 檔案，合併時另外改了 lib/main.dart。
g checkout -q -b side "$noted"
commit side "README.md=side" "lib/side.dart=x" >/dev/null
g checkout -q -b trunk "$noted"
commit trunk "docs/trunk.md=x" >/dev/null
g merge -q --no-ff --no-commit side >/dev/null
printf 'merged' >"$repo/lib/main.dart"
g add -A
g commit -q -m merge
merged=$(g rev-parse HEAD)
expect_output 'app-files: 合併時另外改的 App 檔案也算' "$(printf 'lib/main.dart\nlib/side.dart')" app_files "$noted" "$merged"
g checkout -q -

# ---- added ----

added() { (cd "$repo" && sh "$tool" added "$@"); }

g checkout -q -b added "$noted"
more=$(commit more "CHANGELOG.md=$(changelog '介紹改寫過了。

- 新功能
- 第二項
- 第三項
')")
expect_output 'added: 只印出起點沒有的條列，不含介紹' "$(printf -- '- 第二項\n- 第三項')" \
  added "$noted"
expect_output 'added: 起點的「未發布」是空的時印出全部條列' "$(printf -- '- 新功能\n- 第二項\n- 第三項')" \
  added "$base"
commit reworded "CHANGELOG.md=$(changelog '- 新功能（改寫）
- 第二項
- 第三項
')" >/dev/null
expect_output 'added: 改寫過的條列也算新的' '- 新功能（改寫）' added "$more"
g checkout -q -

# 子條列跟著上面那一條：新的一條整條印出，只改了子條列也整條印出。
g checkout -q nested
expect_output 'added: 只改了子條列時整條印出' "$(printf -- '- 一批設定：\n  - 第一個\n  - 第二個')" \
  added "$nested_base"
expect_output 'added: 新的一條連子條列一起印出' "$(printf -- '- 一批設定：\n  - 第一個\n  - 第二個\n- 另一項')" \
  added "$noted"
g checkout -q -

# ---- git 失敗 ----

# 提交還在、內容讀不到時（刪掉 lib/ 的 tree），要失敗，不能當成沒有改動而略過發版。
bad="$work/bad"
git init -q "$bad"
gb() { git -C "$bad" -c user.name=test -c user.email=test@example.com "$@"; }
mkdir -p "$bad/lib"
printf 'v1' >"$bad/lib/a.dart"
gb add -A
gb commit -q -m one
bad_base=$(gb rev-parse HEAD)
printf 'v2' >"$bad/lib/a.dart"
gb add -A
gb commit -q -m two
tree=$(gb rev-parse HEAD:lib)
rm -f "$bad/.git/objects/$(printf '%s' "$tree" | cut -c1-2)/$(printf '%s' "$tree" | cut -c3-)"
expect_failure 'app-files: git 讀不到內容時失敗' sh -c 'cd "$1" && sh "$2" app-files "$3" HEAD' _ "$bad" "$tool" "$bad_base"
expect_failure 'check: git 讀不到內容時失敗' sh -c 'cd "$1" && sh "$2" check "$3" HEAD' _ "$bad" "$tool" "$bad_base"

if [ "$failures" -ne 0 ]; then
  echo "changelog_test: $failures 項失敗" >&2
  exit 1
fi
echo "changelog_test: 全部通過"
