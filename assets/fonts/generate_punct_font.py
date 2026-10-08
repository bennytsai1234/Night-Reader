"""產生 NightReaderPunct：閱讀器內文的臺灣標準標點字型。

來源是 Noto Sans CJK TC 2.004 的 Regular／Bold OTF
（https://github.com/notofonts/noto-cjk/tree/main/Sans/OTF/TraditionalChinese）。

- ，。、；：！？：直接沿用繁中版置中的字形。
- 「」『』：Noto 的字形又長又貼字格邊緣（日文／簡中畫法），且各語系版本相同。
  這裡保留 Noto 的筆畫，改成教育部標準位置：直筆外緣貼字格中線，
  「『 佔右上四分之一格、」』 佔左下四分之一格，直筆截短到半格。

其餘字元不收錄，排版時回退到系統字型。授權為 SIL OFL 1.1（見 OFL.txt）。

用法：python generate_punct_font.py <Regular.otf> <Bold.otf> <輸出資料夾>
"""

import sys
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

FAMILY = "NightReaderPunct"
CENTERED = "，。、；：！？"
OPENING = "「『"
CLOSING = "」』"

# Noto Sans CJK 的表意字框：上緣 880、下緣 -120，中心 (500, 380)。
EM_CENTER_X = 500
EM_CENTER_Y = 380
# 教育部標準（以微軟正黑體量測）：上引號頂端距字框上緣約 0.066 em。
BRACKET_TOP = 814


def _bounds(glyph_set, name):
    pen = BoundsPen(glyph_set)
    glyph_set[name].draw(pen)
    return pen.bounds


def _map_points(recording, mapper):
    mapped = RecordingPen()
    for op, args in recording.value:
        getattr(mapped, op)(*[mapper(*point) for point in args])
    return mapped


def _bracket(glyph_set, name, opening_bottom_offset, opening):
    """截短直筆並移到教育部位置；收引號以字框中心點對稱處理。"""
    recording = RecordingPen()
    glyph_set[name].draw(recording)
    x_min, y_min, x_max, y_max = _bounds(glyph_set, name)
    mid = (y_min + y_max) / 2
    if opening:
        dx = EM_CENTER_X - x_min
        dy = BRACKET_TOP - y_max
        shorten = (EM_CENTER_Y - opening_bottom_offset) - dy - y_min
        return _map_points(
            recording,
            lambda x, y: (x + dx, (y + shorten if y < mid else y) + dy),
        )
    bottom = 2 * EM_CENTER_Y - BRACKET_TOP
    top = EM_CENTER_Y + opening_bottom_offset
    dx = EM_CENTER_X - x_max
    dy = bottom - y_min
    shorten = (y_max + dy) - top
    return _map_points(
        recording,
        lambda x, y: (x + dx, (y - shorten if y > mid else y) + dy),
    )


def _to_tt_glyph(recording):
    pen = TTGlyphPen(None)
    recording.replay(Cu2QuPen(pen, max_err=1.0, reverse_direction=True))
    return pen.glyph()


def build(source_path, bold, out_path):
    source = TTFont(source_path)
    cmap = source.getBestCmap()
    glyph_set = source.getGlyphSet()

    # 『 的直筆比 「 長一點；維持 Noto 原本的長度差。
    opening_bottom = {
        "「": 0,
        "『": _bounds(glyph_set, cmap[ord("「")])[1]
        - _bounds(glyph_set, cmap[ord("『")])[1],
    }
    opening_bottom["」"] = opening_bottom["「"]
    opening_bottom["』"] = opening_bottom["『"]

    order = [".notdef"]
    char_map = {}
    glyphs = {".notdef": TTGlyphPen(None).glyph()}
    for char in CENTERED + OPENING + CLOSING:
        name = f"uni{ord(char):04X}"
        source_name = cmap[ord(char)]
        if char in CENTERED:
            recording = RecordingPen()
            glyph_set[source_name].draw(recording)
        else:
            recording = _bracket(
                glyph_set,
                source_name,
                opening_bottom[char],
                opening=char in OPENING,
            )
        order.append(name)
        char_map[ord(char)] = name
        glyphs[name] = _to_tt_glyph(recording)

    style = "Bold" if bold else "Regular"
    builder = FontBuilder(unitsPerEm=1000, isTTF=True)
    builder.setupGlyphOrder(order)
    builder.setupCharacterMap(char_map)
    builder.setupGlyf(glyphs)
    glyf = builder.font["glyf"]
    metrics = {}
    for name in order:
        glyph = glyf[name]
        glyph.recalcBounds(glyf)
        metrics[name] = (1000, getattr(glyph, "xMin", 0))
    builder.setupHorizontalMetrics(metrics)
    # 垂直度量與 Noto Sans CJK 相同，混排時行高與基線不變。
    builder.setupHorizontalHeader(ascent=1160, descent=-288, lineGap=0)
    builder.setupNameTable(
        {
            "copyright": "© 2014-2021 Adobe (http://www.adobe.com/). "
            "Modified for Night Reader: subset to CJK punctuation; "
            "corner brackets moved to Taiwan MOE positions.",
            "familyName": FAMILY,
            "styleName": style,
            "uniqueFontIdentifier": f"{FAMILY}-{style};1.000",
            "fullName": f"{FAMILY} {style}",
            "version": "Version 1.000",
            "psName": f"{FAMILY}-{style}",
            "licenseDescription": "This Font Software is licensed under the "
            "SIL Open Font License, Version 1.1.",
            "licenseInfoURL": "https://openfontlicense.org",
        }
    )
    builder.setupOS2(
        version=4,
        usWeightClass=700 if bold else 400,
        fsSelection=0x20 if bold else 0x40,
        achVendID="NRDR",
        sTypoAscender=880,
        sTypoDescender=-120,
        sTypoLineGap=0,
        usWinAscent=1160,
        usWinDescent=288,
        sxHeight=543,
        sCapHeight=733,
        ulCodePageRange1=1 << 20,  # Chinese: Big5
    )
    builder.font["head"].macStyle = 1 if bold else 0
    builder.setupPost()
    builder.save(out_path)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    regular, bold, out_dir = sys.argv[1:]
    out = Path(out_dir)
    build(regular, False, out / f"{FAMILY}-Regular.ttf")
    build(bold, True, out / f"{FAMILY}-Bold.ttf")


if __name__ == "__main__":
    main()
