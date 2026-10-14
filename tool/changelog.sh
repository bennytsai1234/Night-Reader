#!/bin/sh
# 更新說明（CHANGELOG.md）的共用工具，見 ADR 0010。
#
#   sh tool/changelog.sh section <標題> [檔案]
#     印出「## <標題>」段落的內容，去掉前後空行。檔案預設 CHANGELOG.md，「-」代表標準輸入。
#     找不到這個標題時結束碼為 1；段落存在但沒有內容時印出空字串、結束碼為 0。
#     android-release.yml 用它取 GitHub Release 說明：測試版取「未發布」，正式版取「X.Y.Z」。
#
#   sh tool/changelog.sh check <base> <head>
#     base..head 改到 App 內容時，確認 CHANGELOG.md 有跟著寫：「## 未發布」改過且不是空的，
#     或新增了正式版的「## X.Y.Z」段落。沒寫時結束碼為 1。
#     commit message 的 trailer 寫了 `Release-Notes: none` 的提交（App 行為沒變，例如只改註解）不算。
#     android-release.yml 手動發測試版時以上一個發布的 tag 為 base 呼叫（ADR 0014）。
#
# 測試：sh tool/changelog_test.sh
set -eu

UNRELEASED='未發布'

# 不算 App 內容的路徑：android-release.yml 的 release_ignored（文件、網站、測試、ci.yml），
# 加上不進 APK 的 CI 設定、Git hook 與這類工具腳本。改 release_ignored 時這裡一起改。
is_app_path() {
  case $1 in
    *.md | docs/* | website/* | test/* | .github/* | .githooks/* | tool/*) return 1 ;;
  esac
  return 0
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
  for commit in "$base" "$head"; do
    if ! git rev-parse --verify --quiet "$commit^{commit}" >/dev/null; then
      echo "changelog: 本機沒有提交 $commit，先 git fetch 再試。" >&2
      return 1
    fi
  done

  app_files=$(git -c core.quotePath=false diff --name-only "$base" "$head" |
    while IFS= read -r path; do
      if is_app_path "$path"; then printf '%s\n' "$path"; fi
    done)
  if [ -z "$app_files" ]; then
    echo "changelog: 這次沒有改到 App 內容，不需要更新說明。"
    return 0
  fi

  # 不影響 App 行為的提交（例如只改註解）在 commit message 結尾的 trailer 寫
  # `Release-Notes: none`，不需要更新說明；只看其他提交改到的 App 檔案。
  app_files=$(git rev-list --no-merges "$base..$head" |
    while IFS= read -r commit; do
      notes=$(git log -1 --format='%(trailers:key=Release-Notes,valueonly)' "$commit" | tr -d '[:space:]')
      [ "$notes" = none ] && continue
      git -c core.quotePath=false diff-tree --no-commit-id --name-only -r "$commit"
    done | sort -u |
    while IFS= read -r path; do
      if is_app_path "$path"; then printf '%s\n' "$path"; fi
    done)
  if [ -z "$app_files" ]; then
    echo "changelog: 改到 App 內容的提交都標了 Release-Notes: none，不需要更新說明。"
    return 0
  fi

  if ! new=$(section_at "$head" "$UNRELEASED"); then
    echo "changelog: CHANGELOG.md 找不到「## $UNRELEASED」段落。請在最上面保留這個標題，正式版的段落放在它下面。" >&2
    return 1
  fi
  old=$(section_at "$base" "$UNRELEASED") || old=''
  # 清空也算變化，但清空後測試版就沒有這次改動的說明，所以只有寫了內容才放行。
  if [ "$new" != "$old" ] && [ -n "$new" ]; then
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
      echo "changelog: 這次推上 main 的改動動到了 App 內容，但 CHANGELOG.md 的「## $UNRELEASED」被清空了，也沒有新增正式版的段落。"
    else
      echo "changelog: 這次推上 main 的改動動到了 App 內容，但 CHANGELOG.md 的「## $UNRELEASED」沒有更新。"
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
  echo "用法：sh tool/changelog.sh section <標題> [檔案] | check <base> <head>" >&2
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
  check)
    [ $# -eq 2 ] || usage
    check "$@"
    ;;
  *) usage ;;
esac
