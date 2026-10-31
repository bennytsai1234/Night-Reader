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
  old=$(section_at "$base" "$UNRELEASED") || old=''
  # 測試版的說明只取新增或改寫的條列（added），所以照同一個判斷放行：只改介紹，測試版
  # 說明會是空的。只刪了條列（例如推翻剛加的功能）時沒有新條列，ADR 0010 允許。清空不算。
  added=$(new_items "$old" "$new")
  removed=$(new_items "$new" "$old")
  if [ -n "$new" ] && { [ -n "$added" ] || [ -n "$removed" ]; }; then
    echo "changelog: 「## $UNRELEASED」已更新。"
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
      echo "changelog: 這段範圍的改動動到了 App 內容，但 CHANGELOG.md 的「## $UNRELEASED」只改了介紹，沒有新增或改寫條列；測試版的說明只取新增或改寫的條列，會是空的。"
    else
      echo "changelog: 這段範圍的改動動到了 App 內容，但 CHANGELOG.md 的「## $UNRELEASED」沒有更新。"
    fi
    echo
    echo "  測試版與正式版的 GitHub Release 說明都取自 CHANGELOG.md，App 的更新視窗與「更新紀錄」會顯示它。"
    echo "  請在「## $UNRELEASED」下面用一般讀者看得懂的中文寫這次的變化："
    echo "    - 有新重點時，在段落開頭用一兩句話介紹；"
    echo "    - 每項使用者看得到的改動寫成一行條列，不寫內部實作，也不寫 feat:、fix: 這類前綴。"
    echo "  發正式版時，版號 commit 要把「## $UNRELEASED」改成「## X.Y.Z」，並在上面留一個空的「## $UNRELEASED」。"
    echo
    echo "  改到 App 內容的檔案（最多列 10 個）："
    printf '%s\n' "$app_files" | head -n 10 | sed 's/^/    /'
  } >&2
  return 1
}

usage() {
  echo "用法：sh tool/changelog.sh section <標題> [檔案] | added <base> [檔案] | app-files <base> <head> | check <base> <head>" >&2
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
  *) usage ;;
esac
