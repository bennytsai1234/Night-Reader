"""重新產生 lib/core/utils/gb18030_ranges.dart：

    python3 tool/gb18030_ranges.py [index-gb18030-ranges.txt]

照 WHATWG Encoding Standard 的 index-gb18030-ranges.txt（沒給檔案時從
https://encoding.spec.whatwg.org/index-gb18030-ranges.txt 下載）寫出 GB18030
四位元組的對照表：每一列是（四位元組的序號，對到的第一個碼位），兩列之間的
序號與碼位一一往上加。
"""

import pathlib
import sys
import urllib.request

OUTPUT = pathlib.Path(__file__).resolve().parent.parent / 'lib/core/utils/gb18030_ranges.dart'
SOURCE = 'https://encoding.spec.whatwg.org/index-gb18030-ranges.txt'

if len(sys.argv) > 1:
    text = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
else:
    with urllib.request.urlopen(SOURCE) as response:
        text = response.read().decode('utf-8')

identifier = ''
rows = []
for line in text.splitlines():
    if line.startswith('# Identifier:'):
        identifier = line.split(':', 1)[1].strip()
    line = line.split('#', 1)[0].strip()
    if not line:
        continue
    pointer, code = line.split()
    rows.append((int(pointer), int(code, 16)))

pointers = ', '.join(str(p) for p, _ in rows)
codes = ', '.join(f'0x{c:04X}' for _, c in rows)
OUTPUT.write_text(
    '// 由 tool/gb18030_ranges.py 產生，不要手改。\n'
    f'// 來源：WHATWG index-gb18030-ranges.txt（Identifier: {identifier}）。\n\n'
    '/// GB18030 四位元組的序號：每一段的起點。\n'
    f'const List<int> gb18030RangePointers = [{pointers}];\n\n'
    '/// 每一段起點對到的碼位，和 [gb18030RangePointers] 一一對應。\n'
    f'const List<int> gb18030RangeCodePoints = [{codes}];\n',
    encoding='utf-8',
    newline='\n',
)
print(f'{OUTPUT}: {len(rows)} 段')
