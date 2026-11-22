#!/bin/sh
# 檢查說明文件裡寫的「`名稱` 技能」都找得到：專案的 .claude/skills/，或這台電腦
# 裝的 ~/.claude/skills/。全域技能改名或拿掉時，文件常留著舊名字。技能只裝在本機，
# CI 上沒有，所以只在推送前的 hook 跑；這台沒有 ~/.claude/skills/ 就略過。
#
#   sh tool/skill_refs.sh
# 結束碼：0 全都找得到或略過，1 有找不到的（印出檔案與行號）。
global="$HOME/.claude/skills"
if [ ! -d "$global" ]; then
  echo "skill-refs: 這台沒有 $global，略過。"
  exit 0
fi
missing=$(git grep -n -o -E '`[a-z0-9-]+` ?技能' -- '*.md' | while IFS=: read -r file line match; do
  name=$(printf '%s' "$match" | sed -E 's/^`([a-z0-9-]+)`.*/\1/')
  if [ ! -f ".claude/skills/$name/SKILL.md" ] && [ ! -f "$global/$name/SKILL.md" ]; then
    printf 'skill-refs: %s:%s 找不到「%s」技能\n' "$file" "$line" "$name"
  fi
done)
if [ -n "$missing" ]; then
  printf '%s\n' "$missing"
  exit 1
fi
