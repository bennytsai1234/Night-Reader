#!/bin/sh
# 更新說明（CHANGELOG.md）的共用工具，見 ADR 0010。
#
#   sh tool/changelog.sh section <標題> [檔案]
#     印出「## <標題>」段落的內容，去掉前後空行。檔案預設 CHANGELOG.md，「-」代表標準輸入。
#     找不到這個標題時結束碼為 1；段落存在但沒有內容時印出空字串、結束碼為 0。
#     android-release.yml 用它取正式版的 GitHub Release 說明（「X.Y.Z」段落）。
#
#   sh tool/changelog.sh added <base> [檔案]
#     印出「## 未發布」裡 <base> 那個提交還沒有的條列，改寫過的也算，不含開頭的介紹段落。
#     一條是「- 」開頭的頂層條列加上底下縮排的子條列，整條比對、整條印出。<base> 沒有這個
#     段落時印出全部條列。android-release.yml 以上一個發布的 tag 為 base，取測試版的 Release 說明。
#
#   sh tool/changelog.sh app-files <base> <head>
#     印出 base..head 改到的 App 內容檔案，一行一個；沒有時不印。
#     commit message 裡單獨一行寫了 `Release-Notes: none` 的提交（App 行為沒變，例如只改註解）不算。
#     android-release.yml 以上一個發布的 tag 為 base 呼叫，有輸出才發測試版。
#
#   sh tool/changelog.sh check <base> <head>
#     base..head 改到 App 內容（照 app-files）時，確認 CHANGELOG.md 有跟著寫：「## 未發布」
#     不是空的，而且照 added 的條列有新增或改寫（只刪條列也算），或新增了正式版的「## X.Y.Z」
#     段落。只改介紹不算：測試版說明只取條列。沒寫時結束碼為 1。
#     android-release.yml 發測試版時以上一個發布的 tag 為 base 呼叫（ADR 0027）。
#
#   sh tool/changelog.sh validate beta|stable [檔案]
#     檢查即將公開的更新說明：長度、條列數、具名書源與網址；預設從標準輸入讀取。
#     只驗證這一次要發布的文字，不讀舊版歷史。
#
# 測試：sh tool/changelog_test.sh
set -eu

UNRELEASED='未發布'

# 不進 APK 的路徑：文件、網站、測試、Git hook、工具腳本，以及只跑測試的 ci.yml 與部署網站的
# website-deploy.yml。android-release.yml 算 App 內容：APK 用它固定的 Flutter 版本與參數建置。
is_app_path() {
  case $1 in
    *.md | docs/* | website/* | test/* | .githooks/* | tool/* | \
      .github/workflows/ci.yml | .github/workflows/website-deploy.yml) return 1 ;;
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

# 印出 <commit> 上 CHANGELOG.md 的「## <標題>」段落；沒有這個檔案或標題時結束碼為 1。
section_at() {
  git show "$1:CHANGELOG.md" 2>/dev/null | section "$2" -
}

# new_items <舊段落> <新段落>：印出新段落裡舊段落沒有的條列。一條是一行「- 」開頭的頂層條列，
# 加上緊接在它下面、縮排開頭的行（子條列與續行）；整條比對，只改子條列也算改寫，整條印出。
# 介紹段落與其他不在條列裡的行不算。
new_items() {
  OLD=$1 NEW=$2 awk '
    function parse(text, items,   n, lines, i, line, item, k) {
      n = split(text, lines, "\n")
      k = 0
      item = ""
      for (i = 1; i <= n; i++) {
        line = lines[i]
        if (line ~ /^- /) {
          if (item != "") items[++k] = item
          item = line
        } else if (item != "" && line ~ /^[ \t]+[^ \t]/) {
          item = item "\n" line
        } else {
          if (item != "") items[++k] = item
          item = ""
        }
      }
      if (item != "") items[++k] = item
      return k
    }
    BEGIN {
      m = parse(ENVIRON["OLD"], olds)
      for (i = 1; i <= m; i++) seen[olds[i]] = 1
      n = parse(ENVIRON["NEW"], news)
      for (i = 1; i <= n; i++) if (!(news[i] in seen)) print news[i]
    }
  '
}

added() {
  old=$(section_at "$1" "$UNRELEASED") || old=''
  new=$(section "$UNRELEASED" "${2:-CHANGELOG.md}") || return 1
  new_items "$old" "$new"
}

check() {
  base=$1
  head=$2
  case $base in
    *[!0]*) ;;
    *)
      echo "changelog: 沒有可比對的起點（新分支），不檢查更新說明。"
      return 0
      ;;
  esac
  require_commits "$base" "$head" || return 1

  app_files=$(app_files "$base" "$head") || return 1
  if [ -z "$app_files" ]; then
    echo "changelog: 這次沒有改到 App 內容，或改到的提交都標了 Release-Notes: none，不需要更新說明。"
    return 0
  fi

  if ! new=$(section_at "$head" "$UNRELEASED"); then
    echo "changelog: CHANGELOG.md 找不到「## $UNRELEASED」段落。請在最上面保留這個標題，正式版的段落放在它下面。" >&2
    return 1
  fi
  # 「未發布」最後會成為正式版說明，合併時先把長篇或具名書源擋下來。
  if [ -n "$new" ] && ! printf '%s\n' "$new" | validate stable -; then
    return 1
  fi
  old=$(section_at "$base" "$UNRELEASED") || old=''
  # 巢狀條列會因任一子項改寫而把整組內容重發；公開說明一律平鋪。
  # 只刪除條列也不能發空白更新說明，應改寫一項描述最新行為。
  added=$(new_items "$old" "$new")
  if [ -n "$added" ]; then
    if ! printf '%s\n' "$added" | validate beta -; then return 1; fi
    echo "changelog: 「## $UNRELEASED」已更新，公開說明通過檢查。"
    return 0
  fi

  # 正式版的版號 commit 把「未發布」改名成「X.Y.Z」，留下的「未發布」是空的。
  version=$(git show "$head:pubspec.yaml" | awk '$1 == "version:" { print $2; exit }')
  if [ -n "$version" ] &&
    notes=$(section_at "$head" "$version") && [ -n "$notes" ] &&
    ! section_at "$base" "$version" >/dev/null; then
    echo "changelog: 新增了正式版 $version 的更新說明。"
    return 0
  fi

  {
    if [ -z "$new" ] && [ -n "$old" ]; then
      echo "changelog: 這段範圍的改動動到了 App 內容，但 CHANGELOG.md 的「## $UNRELEASED」被清空了，也沒有新增正式版的段落。"
    elif [ "$new" != "$old" ]; then
      echo "changelog: 這段範圍的改動動到了 App 內容，但沒有新增或改寫條列；測試版不能發布空白更新說明。"
    else
      echo "changelog: 這段範圍的改動動到了 App 內容，但 CHANGELOG.md 的「## $UNRELEASED」沒有更新。"
    fi
    echo
    echo "  測試版與正式版的 GitHub Release 說明都取自 CHANGELOG.md，App 的更新視窗與「更新紀錄」會顯示它。"
    echo "  請在「## $UNRELEASED」下面用一般讀者看得懂的中文寫這次的變化："
    echo "    - 有新重點時，在段落開頭用一兩句話介紹；"
    echo "    - 每項改動寫成一行，不列個別書源或網址，不用巢狀條列，也不寫內部實作。"
    echo "  發正式版時，版號 commit 要把「## $UNRELEASED」改成「## X.Y.Z」，並在上面留一個空的「## $UNRELEASED」。"
    echo
    echo "  改到 App 內容的檔案（最多列 10 個）："
    printf '%s\n' "$app_files" | head -n 10 | sed 's/^/    /'
  } >&2
  return 1
}

# 檢查實際公開的段落；既有已發布版本不在這裡重新檢查。
# 具名書源檢查包含已知清單與網址，新的名稱仍需 PR 審查時人工確認。
validate() {
  mode=${1:-}
  case "$mode" in
    beta) max_items=4; max_chars=480 ;;
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
  if [ "$count" -lt 1 ] || [ "$count" -gt "$max_items" ] || [ "$chars" -gt "$max_chars" ]; then
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
  echo "用法：sh tool/changelog.sh section <標題> [檔案] | added <base> [檔案] | app-files <base> <head> | check <base> <head> | validate beta|stable [檔案]" >&2
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
  added)
    [ $# -ge 1 ] && [ $# -le 2 ] || usage
    added "$@"
    ;;
  app-files)
    [ $# -eq 2 ] || usage
    require_commits "$@"
    app_files "$@"
    ;;
  check)
    [ $# -eq 2 ] || usage
    check "$@"
    ;;
  validate)
    [ $# -ge 1 ] && [ $# -le 2 ] || usage
    validate "$@"
    ;;
  *) usage ;;
esac
