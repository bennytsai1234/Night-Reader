#!/bin/sh
# 檢查 docs/adr/README.md 的索引和 docs/adr/ 裡的 ADR 對得上：每一份都有一行連到它，
# 索引連到的每一份都存在。ADR 常只改文件、直接推上 beta，CI 不跑只改文件的推送，
# 所以推送前的 hook 也跑這支。
#
#   sh tool/adr_index.sh
# 結束碼：0 對得上，1 有漏列或連到不存在的（印出檔名）。
dir=docs/adr
index=$dir/README.md
status=0
for file in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
  [ -e "$file" ] || continue
  name=${file##*/}
  if ! grep -qF "]($name)" "$index"; then
    echo "adr-index: $index 沒有列 $name"
    status=1
  fi
done
for name in $(grep -oE '\]\([0-9]{4}-[^)]*\.md\)' "$index" | sed 's/^](//; s/)$//' | sort -u); do
  if [ ! -f "$dir/$name" ]; then
    echo "adr-index: $index 連到不存在的 $name"
    status=1
  fi
done
exit $status
