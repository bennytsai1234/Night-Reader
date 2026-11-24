"""重新產生 lib/core/utils/big5_table.dart：

    python3 tool/big5_table.py

照 Python 內建的 cp950（Windows 的 Big5，台灣網站實際送的那一種）逐一解每個
雙位元組，寫成一列一個開頭位元組（0x81–0xFE）、每列照第二個位元組 0x40–0x7E、
0xA1–0xFE 排的字；沒有字的位置是 U+FFFD。同一個字解得出兩個位置時（「十」「卅」
這類），另外照 cp950 編碼的結果寫進 big5EncodeOverrides：編碼不是解碼倒過來。
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
first = {}
seen_twice = set()
for lead in range(0x81, 0xFF):
    chars = []
    for trail in TRAILS:
        try:
            ch = bytes([lead, trail]).decode('cp950')
        except UnicodeDecodeError:
            ch = '�'
        if len(ch) != 1:
            ch = '�'
        if ch != '�':
            if ch in first:
                seen_twice.add(ch)
            else:
                first[ch] = (lead << 8) | trail
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
lines.append('')
lines.append('/// 同一個字解得出兩個位置、編碼時不取第一個的：字 → 兩個位元組。')
lines.append('const Map<int, int> big5EncodeOverrides = {')
for ch in sorted(seen_twice):
    code = int.from_bytes(ch.encode('cp950'), 'big')
    if code != first[ch]:
        lines.append(f'  0x{ord(ch):04X}: 0x{code:04X}, // {ch}')
lines.append('};')
OUTPUT.write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
print(f'寫好 {OUTPUT}（{len(rows)} 列）')
