#!/bin/sh
# 更新說明的共用工具，見 ADR 0049。
#
#   sh tool/changelog.sh section <標題> [檔案]
#     印出「## <標題>」段落的內容，去掉前後空行。檔案預設 CHANGELOG.md，「-」代表標準輸入。
#     找不到這個標題時結束碼為 1；段落存在但沒有內容時印出空字串、結束碼為 0。
#     android-release.yml 用它取正式版的 GitHub Release 說明（「X.Y.Z」段落）。
#
#   sh tool/changelog.sh titles <base> <head>
#     印出測試版說明：base..head 主線上每個改到 App 內容的提交（照 app-files），標題去掉
#     Conventional Commits 前綴與結尾的「(#123)」，一個一行「- 」條列，舊的在前。
#     squash 合併的提交標題就是 PR 標題。android-release.yml 以上一個發布的 tag 為 base 呼叫。
#
#   sh tool/changelog.sh check-title <PR 標題>
#     檢查 PR 標題去掉前綴後能不能直接當測試版說明的一行（同 validate beta）。
#     pr-title.yml 在改到 App 內容的 PR 上呼叫。
#
#   sh tool/changelog.sh app-files <base> <head>
#     印出 base..head 改到的 App 內容檔案，一行一個；沒有時不印。
#     commit message 裡單獨一行寫了 `Release-Notes: none` 的提交（App 行為沒變，例如只改註解）不算。
#     android-release.yml 以上一個發布的 tag 為 base 呼叫，有輸出才發測試版。
#
#   sh tool/changelog.sh validate beta|stable [檔案]
#     檢查即將公開的更新說明：條列格式、長度、具名書源與網址；預設從標準輸入讀取。
#
# 測試：sh tool/changelog_test.sh
set -eu

# 不進 APK 的路徑：文件、網站、測試與測試的設定（dart_test.yaml）、靜態檢查的設定
# （analysis_options.yaml）、Git hook、工具腳本，以及只跑檢查的 ci.yml、pr-title.yml 與部署網站的
# website-deploy.yml。android-release.yml 算 App 內容：APK 用它固定的 Flutter 版本與參數建置。
is_app_path() {
  case $1 in
    *.md | docs/* | website/* | test/* | dart_test.yaml | analysis_options.yaml | \
      .githooks/* | tool/* | \
      .github/workflows/ci.yml | .github/workflows/pr-title.yml | \
      .github/workflows/website-deploy.yml) return 1 ;;
  esac
  return 0
}

app_paths() {
  while IFS= read -r path; do
    if [ -n "$path" ] && is_app_path "$path"; then printf '%s\n' "$path"; fi
  done
}

# git 的輸出先存進變數再篩：sh 的管線只看最後一個指令的結束碼，git 失敗會被當成沒有改動，
# 發版就默默略過。
app_files() {
  diff=$(git -c core.quotePath=false diff --name-only "$1" "$2") || return 1
  changed=$(printf '%s\n' "$diff" | app_paths)
  [ -n "$changed" ] || return 0
  commits=$(git rev-list "$1..$2") || return 1
  touched=''
  for commit in $commits; do
    message=$(git log -1 --format=%B "$commit") || return 1
    # 不用 git 的 trailer 解析：squash 合併的說明最後一段是「Generated with」那行，
    # `Release-Notes: none` 寫在它前面一段就讀不到。
    if printf '%s\n' "$message" | tr -d '\r' | grep -qxE 'Release-Notes:[[:space:]]*none[[:space:]]*'; then
      continue
    fi
    # -c：合併提交只列和每個父提交都不同的檔案，也就是合併時另外改的；兩邊分支原本的改動
    # 由分支上的提交各自算。
    files=$(git -c core.quotePath=false diff-tree --no-commit-id --name-only -r -c "$commit") || return 1
    touched="$touched
$files"
  done
  # 只留整段比起來還有差異的檔案：改了又改回來的不算。
  printf '%s\n' "$touched" | app_paths | sort -u | CHANGED=$changed awk '
    BEGIN { n = split(ENVIRON["CHANGED"], lines, "\n"); for (i = 1; i <= n; i++) keep[lines[i]] = 1 }
    $0 in keep
  '
}

require_commits() {
  for commit in "$@"; do
    if ! git rev-parse --verify --quiet "$commit^{commit}" >/dev/null; then
      echo "changelog: 本機沒有提交 $commit，先 git fetch 再試。" >&2
      return 1
    fi
  done
}

section() {
  awk -v want="## $1" '
    { sub(/\r$/, ""); sub(/[ \t]+$/, "") }
    /^## / {
      if (found) exit
      if ($0 == want) { found = 1; next }
    }
    found { lines[++n] = $0 }
    END {
      if (!found) exit 1
      first = 1
      while (first <= n && lines[first] == "") first++
      last = n
      while (last >= first && lines[last] == "") last--
      for (i = first; i <= last; i++) print lines[i]
    }
  ' "${2:-CHANGELOG.md}"
}

# 標題變成說明的一行：去掉「fix(reader): 」「feat!: 」這類前綴與結尾的「 (#123)」。
title_line() {
  printf '%s\n' "$1" | sed -E 's/^[[:alnum:]]+(\([^)]*\))?!?:[[:space:]]*//; s/[[:space:]]*\(#[0-9]+\)$//; s/^/- /'
}

titles() {
  require_commits "$1" "$2" || return 1
  commits=$(git rev-list --reverse --first-parent "$1..$2") || return 1
  for commit in $commits; do
    files=$(app_files "$commit^" "$commit") || return 1
    [ -n "$files" ] || continue
    subject=$(git log -1 --format=%s "$commit") || return 1
    title_line "$subject"
  done
}

check_title() {
  line=$(title_line "$1")
  if ! printf '%s\n' "$line" | validate beta -; then
    echo "changelog: PR 標題會直接成為測試版說明的一行（「$line」），請改成讀者看得懂的一句。" >&2
    return 1
  fi
}

# 檢查實際公開的段落；既有已發布版本不在這裡重新檢查。
# 具名書源檢查包含已知清單與網址，新的名稱仍需 PR 審查時人工確認。
# 測試版一行是一個 PR，條數跟著合併的 PR 走，不限條數；App 更新視窗只顯示前幾項重點。
validate() {
  mode=${1:-}
  case "$mode" in
    beta) max_items=''; max_chars='' ;;
    stable) max_items=8; max_chars=900 ;;
    *) echo "changelog: validate 需要 beta 或 stable 模式。" >&2; return 2 ;;
  esac
  body=$(cat "${2:--}") || return 1
  if [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then
    echo "changelog: 公開更新說明不可為空。" >&2
    return 1
  fi
  count=$(printf '%s\n' "$body" | grep -c '^- ' || true)
  chars=$(printf '%s' "$body" | LC_ALL=C.UTF-8 wc -m | tr -d ' ')
  if [ "$count" -lt 1 ]; then
    echo "changelog: 更新說明至少要有一項「- 」條列。" >&2
    return 1
  fi
  if [ -n "$max_items" ] && { [ "$count" -gt "$max_items" ] || [ "$chars" -gt "$max_chars" ]; }; then
    echo "changelog: $mode 更新說明要有 1～$max_items 項、至多 $max_chars 字元（目前 $count 項、$chars 字元），請合併成讀者看得懂的重點。" >&2
    return 1
  fi
  if printf '%s\n' "$body" | grep -qE '^[[:space:]]+[-*+] |^[*+] '; then
    echo "changelog: 公開更新說明不能用巢狀條列或其他條列格式，請平鋪成一句重點。" >&2
    return 1
  fi
  if [ "$mode" = beta ] && printf '%s\n' "$body" | grep -qEv '^[[:space:]]*$|^- '; then
    echo "changelog: 測試版只能使用平鋪的「- 」條列，不要介紹段落或續行。" >&2
    return 1
  fi
  # 用 C 語系比對：UTF-8 語系的 [:alnum:] 把中文字也算進去，網域後面直接接
  # 中文（「example.com的」）就漏掉了。
  if printf '%s\n' "$body" | LC_ALL=C grep -Eiq 'https?://|www\.|[[:alnum:]-]+\.(com|net|org|io|cn|tw|cc|vip|top|dev)([^[:alnum:].-]|$)'; then
    echo "changelog: 公開更新說明不能列出網址或網域，請改寫成通用功能描述。" >&2
    return 1
  fi
  names="$(dirname "$0")/release_note_source_names.txt"
  if [ ! -s "$names" ]; then
    echo "changelog: 找不到具名書源檢查清單，不能略過檢查。" >&2
    return 1
  fi
  if printf '%s\n' "$body" | grep -iqFf "$names"; then
    echo "changelog: 公開更新說明包含已知書源名稱；只描述通用行為，細節留在 PR 與測試。" >&2
    return 1
  fi
  too_long=$(printf '%s\n' "$body" | while IFS= read -r line; do
    case "$line" in
      '- '*)
        line_chars=$(printf '%s' "$line" | LC_ALL=C.UTF-8 wc -m | tr -d ' ')
        if [ "$line_chars" -gt 145 ]; then printf '1\n'; break; fi
        ;;
    esac
  done)
  if [ -n "$too_long" ]; then
    echo "changelog: 每一項公開更新說明不得超過 145 字元，請縮成一句重點。" >&2
    return 1
  fi
}

usage() {
  echo "用法：sh tool/changelog.sh section <標題> [檔案] | titles <base> <head> | check-title <PR 標題> | app-files <base> <head> | validate beta|stable [檔案]" >&2
  exit 2
}

[ $# -ge 1 ] || usage
command=$1
shift
case $command in
  section)
    [ $# -ge 1 ] && [ $# -le 2 ] || usage
    section "$@"
    ;;
  titles)
    [ $# -eq 2 ] || usage
    titles "$@"
    ;;
  check-title)
    [ $# -eq 1 ] || usage
    check_title "$1"
    ;;
  app-files)
    [ $# -eq 2 ] || usage
    require_commits "$@"
    app_files "$@"
    ;;
  validate)
    [ $# -ge 1 ] && [ $# -le 2 ] || usage
    validate "$@"
    ;;
  *) usage ;;
esac
