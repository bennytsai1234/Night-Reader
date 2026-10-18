"""產生排版測試用的字型 mixed_width_test.ttf。

測試環境的預設字型每個字都一樣寬，量不出英數字補半格的效果。這個字型
的字寬刻意不同（字框 1000）：

- 漢字「一二三四五六七八九十」與全形標點「「」『』，。、？！…—」：1000（一格）
- 英文字母：500；i、l：250；數字：600；空格：250
- U+1F600（😀）：1200，用來驗證 emoji 會縮到一格

字形都是實心方塊。垂直度量與 Noto Sans CJK 相同（ascent 1160、descent
-288），與閱讀器的 strut 一致。

用法：python generate_mixed_width_font.py <輸出路徑>
"""

import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

FAMILY = "ReaderMixedWidthTest"
CELL = "一二三四五六七八九十「」『』，。、？！…—"


def _advances():
    advances = {}
    for char in CELL:
        advances[ord(char)] = 1000
    for code in range(ord("a"), ord("z") + 1):
        advances[code] = 500
    for code in range(ord("A"), ord("Z") + 1):
        advances[code] = 500
    advances[ord("i")] = 250
    advances[ord("l")] = 250
    for code in range(ord("0"), ord("9") + 1):
        advances[code] = 600
    advances[ord(" ")] = 250
    advances[0x1F600] = 1200
    return advances


def _box(advance):
    pen = TTGlyphPen(None)
    if advance > 100:
        inset = advance // 10
        pen.moveTo((inset, 0))
        pen.lineTo((inset, 700))
        pen.lineTo((advance - inset, 700))
        pen.lineTo((advance - inset, 0))
        pen.closePath()
    return pen.glyph()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    advances = _advances()
    order = [".notdef"] + [f"u{code:05X}" for code in sorted(advances)]
    builder = FontBuilder(unitsPerEm=1000, isTTF=True)
    builder.setupGlyphOrder(order)
    builder.setupCharacterMap({code: f"u{code:05X}" for code in advances})
    glyphs = {".notdef": _box(500)}
    metrics = {".notdef": (500, 50)}
    for code, advance in advances.items():
        name = f"u{code:05X}"
        glyphs[name] = _box(advance)
        metrics[name] = (advance, advance // 10 if advance > 100 else 0)
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics(metrics)
    builder.setupHorizontalHeader(ascent=1160, descent=-288, lineGap=0)
    builder.setupNameTable(
        {
            "familyName": FAMILY,
            "styleName": "Regular",
            "uniqueFontIdentifier": f"{FAMILY}-Regular;1.000",
            "fullName": f"{FAMILY} Regular",
            "version": "Version 1.000",
            "psName": f"{FAMILY}-Regular",
        }
    )
    builder.setupOS2(
        sTypoAscender=880,
        sTypoDescender=-120,
        sTypoLineGap=0,
        usWinAscent=1160,
        usWinDescent=288,
    )
    builder.setupPost()
    builder.save(sys.argv[1])


if __name__ == "__main__":
    main()
