#!/bin/sh
# tool/changelog.sh 的測試：在暫存的 Git repo 裡模擬各種提交，ci.yml 會執行。
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

## 0.3.5

這次的重點。

- 第一項
### 小標題留在段落裡
- 第二項


## 0.3.4

- 舊版的改動

## 0.3.3
EOF

expect_output 'section: 取段落並去掉前後空行' "$(printf '這次的重點。\n\n- 第一項\n### 小標題留在段落裡\n- 第二項')" \
  sh "$tool" section 0.3.5 "$work/CHANGELOG.md"
expect_output 'section: 取中間的段落' '- 舊版的改動' \
  sh "$tool" section 0.3.4 "$work/CHANGELOG.md"
expect_output 'section: 空段落印出空字串' '' \
  sh "$tool" section 0.3.3 "$work/CHANGELOG.md"
expect_failure 'section: 找不到標題時失敗' \
  sh "$tool" section 0.3.6 "$work/CHANGELOG.md"
expect_failure 'section: 標題要完全相同' \
  sh "$tool" section 0.3 "$work/CHANGELOG.md"
printf '## 0.2.0\r\n\r\n- CRLF 換行\r\n## 0.1.0\r\n' >"$work/crlf.md"
expect_output 'section: 接受 CRLF 換行' '- CRLF 換行' \
  sh "$tool" section 0.2.0 "$work/crlf.md"
expect_output 'section: 「-」讀標準輸入' '- 舊版的改動' \
  sh -c 'sh "$1" section 0.3.4 - <"$2"' _ "$tool" "$work/CHANGELOG.md"

# ---- app-files ----

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

app_files() { (cd "$repo" && sh "$tool" app-files "$@"); }
titles() { (cd "$repo" && sh "$tool" titles "$@"); }

base=$(commit init "pubspec.yaml=version: 0.3.3
" "lib/main.dart=v1")

docs=$(commit 'docs: 說明' "README.md=說明" "docs/adr/0001.md=x" "test/a_test.dart=x" "website/index.html=x" "dart_test.yaml=x" "analysis_options.yaml=x")
expect_output 'app-files: 只改文件、網站、測試時不印' '' app_files "$base" "$docs"

ci=$(commit 'ci: 檢查' ".github/workflows/ci.yml=x" ".github/workflows/pr-title.yml=x" ".github/workflows/website-deploy.yml=x" ".githooks/pre-push=x" "tool/x.sh=x")
expect_output 'app-files: 只改 CI、hook、工具腳本時不印' '' app_files "$base" "$ci"

g checkout -q -b build "$ci"
build=$(commit build ".github/workflows/android-release.yml=x")
expect_output 'app-files: 建置 APK 的 workflow 算 App 內容' '.github/workflows/android-release.yml' app_files "$base" "$build"
g checkout -q -

app=$(commit 'fix(reader): 翻頁更順 (#12)' "lib/main.dart=v2")
expect_output 'app-files: 印出改到的 App 內容檔案' 'lib/main.dart' app_files "$base" "$app"
expect_failure 'app-files: 本機沒有起點提交時失敗' app_files 1234567890123456789012345678901234567890 "$app"

# App 行為沒變的提交單獨一行標 Release-Notes: none。
g checkout -q -b exempt "$app"
comment=$(commit "$(printf 'docs: fix a comment\n\nRelease-Notes: none\nCo-Authored-By: x <x@example.com>')" "lib/main.dart=v2 // 註解")
expect_output 'app-files: 標了 Release-Notes: none 的提交不算' '' app_files "$app" "$comment"
squashed=$(commit "$(printf 'fix(ci): squash 合併\n\nApp 內容沒變。\n\nRelease-Notes: none\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')" "lib/main.dart=v2 // 註解 2")
expect_output 'app-files: Release-Notes: none 後面還有一段時照樣算' '' app_files "$comment" "$squashed"
in_body=$(commit "$(printf 'fix: change\n\nRelease-Notes: none 寫在內文不算\n\nCo-Authored-By: x <x@example.com>')" "lib/main.dart=v5")
expect_output 'app-files: 不是單獨一行的 Release-Notes 不算' 'lib/main.dart' app_files "$squashed" "$in_body"
g checkout -q -

# 改了又改回來，另有一個標了 none 的 App 提交讓整段比起來還有 App 差異。
g checkout -q -b reverted "$app"
commit change "lib/main.dart=v9" >/dev/null
commit revert "lib/main.dart=v2" >/dev/null
reverted=$(commit "$(printf 'docs: comment\n\nRelease-Notes: none')" "lib/comment.dart=// 註解")
expect_output 'app-files: 改了又改回來的檔案不算' '' app_files "$app" "$reverted"
g checkout -q -

# 合併提交：兩邊分支只改文件與一個 App 檔案，合併時另外改了 lib/main.dart。
g checkout -q -b side "$app"
commit side "README.md=side" "lib/side.dart=x" >/dev/null
g checkout -q -b trunk "$app"
commit trunk "docs/trunk.md=x" >/dev/null
g merge -q --no-ff --no-commit side >/dev/null
printf 'merged' >"$repo/lib/main.dart"
g add -A
g commit -q -m merge
merged=$(g rev-parse HEAD)
expect_output 'app-files: 合併時另外改的 App 檔案也算' "$(printf 'lib/main.dart\nlib/side.dart')" app_files "$app" "$merged"
g checkout -q -

# ---- titles ----

# 主線上照順序：一個 App 的 PR、一個只改文件、一個標了 none、一個不帶前綴的、一個 breaking。
g checkout -q -b line "$app"
commit 'docs(adr): 記下決定 (#13)' "docs/x.md=y" >/dev/null
commit "$(printf 'refactor(reader): 拆檔 (#14)\n\nRelease-Notes: none')" "lib/a.dart=x" >/dev/null
commit '書架列表多一種排序 (#15)' "lib/b.dart=x" >/dev/null
last=$(commit 'feat(sync)!: 同步只帶閱讀進度 (#16)' "lib/c.dart=x")
expect_output 'titles: 只列改到 App 的提交，去掉前綴與 PR 編號，舊的在前' \
  "$(printf -- '- 翻頁更順\n- 書架列表多一種排序\n- 同步只帶閱讀進度')" titles "$base" "$last"
expect_output 'titles: 範圍裡沒有 App 改動時不印' '' titles "$base" "$docs"
g checkout -q -

# 主線上的合併提交只算一次，不把分支上的每個提交各列一行。
expect_output 'titles: 只看主線，合併提交算一行' '- merge' titles "$app" "$merged"

check_title() { sh "$tool" check-title "$@"; }
expect_success 'check-title: 讀者看得懂的一句通過' check_title 'fix(reader): 翻頁更順'
expect_failure 'check-title: 去掉前綴後有書源名稱時擋下' check_title 'fix(source): 番茄小說的簽章解析'
expect_failure 'check-title: 有網域時擋下' check_title 'fix(source): example.com 的搜尋'
expect_failure 'check-title: 太長時擋下' check_title "fix: $(awk 'BEGIN { for (i = 0; i < 150; i++) printf "字" }')"

# ---- 公開更新說明 ----

validate() { (cd "$repo" && sh "$tool" validate "$@"); }
printf '%s\n' '- 改善搜尋與目錄的相容性。' >"$work/public.md"
expect_success 'validate: 精簡通用的測試版說明通過' validate beta "$work/public.md"
printf '%s\n' '這次更容易在多台裝置接著閱讀。' '' '- 改善閱讀進度同步。' >"$work/public.md"
expect_success 'validate: 正式版允許一段簡短介紹' validate stable "$work/public.md"
expect_failure 'validate: 測試版不能放介紹段落' validate beta "$work/public.md"
printf '%s\n' '- 改善番茄小說的簽章解析。' >"$work/public.md"
expect_failure 'validate: 已知書源名稱不得出現在公開說明' validate beta "$work/public.md"
printf '%s\n' '- 改善 https://books.example.com 的書源。' >"$work/public.md"
expect_failure 'validate: 書源網址不得出現在公開說明' validate beta "$work/public.md"
printf '%s\n' '- 改善 www.example.org 上的搜尋。' >"$work/public.md"
expect_failure 'validate: 網域不得出現在公開說明' validate beta "$work/public.md"
printf '%s\n' '- 改善 example.com的搜尋。' >"$work/public.md"
expect_failure 'validate: 網域後面直接接中文也擋下' validate beta "$work/public.md"
printf '%s\n' '- 改善 example.cn，搜尋更快。' >"$work/public.md"
expect_failure 'validate: 網域後面接全形標點也擋下' validate beta "$work/public.md"
printf '%s\n' '- 0.3.8 起的版本設定照舊保留。' >"$work/public.md"
expect_success 'validate: 版號不是網域' validate beta "$work/public.md"
printf '%s\n' '- 改善書源相容性：' '  - 修正某項解析' >"$work/public.md"
expect_failure 'validate: 巢狀條列不能公開' validate beta "$work/public.md"
printf '%s\n' '- 1' '- 2' '- 3' '- 4' '- 5' '- 6' '- 7' '- 8' '- 9' >"$work/public.md"
expect_success 'validate: 測試版一個 PR 一行，不限條數' validate beta "$work/public.md"
expect_failure 'validate: 正式版超過八項失敗' validate stable "$work/public.md"
awk 'BEGIN { printf "- "; for (i = 0; i < 146; i++) printf "字"; print "" }' >"$work/public.md"
expect_failure 'validate: 單項超過 145 字元會失敗' validate beta "$work/public.md"
awk 'BEGIN { for (j = 0; j < 7; j++) { printf "- "; for (i = 0; i < 130; i++) printf "字"; print "" } }' >"$work/public.md"
expect_failure 'validate: 正式版總長度過長會失敗' validate stable "$work/public.md"
: >"$work/public.md"
expect_failure 'validate: 空白更新說明會失敗' validate beta "$work/public.md"

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
expect_failure 'titles: git 讀不到內容時失敗' sh -c 'cd "$1" && sh "$2" titles "$3" HEAD' _ "$bad" "$tool" "$bad_base"

if [ "$failures" -ne 0 ]; then
  echo "changelog_test: $failures 項失敗" >&2
  exit 1
fi
echo "changelog_test: 全部通過"
