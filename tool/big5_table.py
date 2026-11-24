"""重新產生 lib/core/utils/big5_table.dart：

    python3 tool/big5_table.py

照 Python 內建的 cp950（Windows 的 Big5，台灣網站實際送的那一種）逐一解每個
雙位元組，寫成一列一個開頭位元組（0x81–0xFE）、每列照第二個位元組 0x40–0x7E、
0xA1–0xFE 排的字；沒有字的位置是 U+FFFD。
"""

import pathlib

OUTPUT = pathlib.Path(__file__).resolve().parent.parent / 'lib/core/utils/big5_table.dart'
TRAILS = list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF))


def escape(ch: str) -> str:
    if ch in '\\\'$':
        return '\\' + ch
    if ch == '�':
        return '\\uFFFD'
    return ch


rows = []
for lead in range(0x81, 0xFF):
    chars = []
    for trail in TRAILS:
        try:
            ch = bytes([lead, trail]).decode('cp950')
        except UnicodeDecodeError:
            ch = '�'
        if len(ch) != 1:
            ch = '�'
        chars.append(escape(ch))
    rows.append(''.join(chars))

lines = [
    '// 由 tool/big5_table.py 產生，不要手改。',
    '',
    '/// Big5（cp950）的雙位元組對照：一列一個開頭位元組（0x81 起），每列照第二',
    '/// 個位元組 0x40–0x7E、0xA1–0xFE 排；沒有字的位置是 U+FFFD。',
    'const List<String> big5Rows = [',
]
for row in rows:
    lines.append(f"  '{row}',")
lines.append('];')
OUTPUT.write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
print(f'寫好 {OUTPUT}（{len(rows)} 列）')
