#!/usr/bin/env python3
"""產生 NightReaderPunct.ttf——歧義寬度標點的全形保證字型。

背景：Android 字型回退鏈對 U+2014/U+2026 等「東亞歧義寬度」碼位會命中
Roboto 的西文窄字形，導致閱讀器格線錯位。此字型只含這些標點的全形字形，
放在排版 TextStyle fontFamily 首位，讓回退鏈永遠先命中全形版本；其餘
字元（漢字、拉丁）因本字型無字形而繼續走系統鏈，行為不變。

來源：Noto Sans TC（SIL Open Font License 1.1，見同目錄 OFL.txt）。
Google Fonts variable 版的 U+2014 advance 為 881（非全形）、U+2015 字形
只覆蓋 70..930（――中間有缺口），因此 dash 不取原字形，改為自製 0..1000
滿版橫線（厚度與垂直位置取自 uni2015：y 362..398，中心 380 = CJK em box
中心），使「——」成為連續 2em 直線。

用法：
    pip install fonttools
    python3 generate.py <NotoSansTC[wght].ttf 路徑>
輸出：../../assets/fonts/NightReaderPunct.ttf

涵蓋碼位（全部 advance = 1000/1000 em）：
    U+2014 EM DASH            → 自製滿版橫線
    U+2015 HORIZONTAL BAR     → 自製滿版橫線
    U+2025 TWO DOT LEADER     → Noto 原字形
    U+2026 HORIZONTAL ELLIPSIS→ Noto 原字形（TC 置中六點式樣的一半）
    U+22EF MIDLINE ELLIPSIS   → Noto 原字形（與 U+2026 同字形）

刻意排除：彎引號 U+2018/2019/201C/201D——英文撇號（don't）與純英文
引號對會被放寬成全形，誤傷比落單引號殘窄更常見。
"""

import sys
from pathlib import Path

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

KEEP_UNICODES = [0x2015, 0x2025, 0x2026, 0x22EF]
DASH_UNICODES = [0x2014, 0x2015]
FAMILY = "NightReaderPunct"
OUT = Path(__file__).resolve().parents[2] / "assets" / "fonts" / f"{FAMILY}.ttf"

# 自製 dash 的幾何（單位：per-em 1000）
BAR_Y_MIN, BAR_Y_MAX = 362, 398  # 取自 Noto TC uni2015，中心 380
BAR_X_MIN, BAR_X_MAX = 0, 1000  # 滿版，「——」連續無缺口


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"用法：{sys.argv[0]} <NotoSansTC[wght].ttf>")
    font = TTFont(sys.argv[1])

    if "fvar" in font:
        instantiateVariableFont(font, {"wght": 400}, inplace=True)

    options = Options()
    options.drop_tables += ["GSUB", "GPOS"]
    options.hinting = False
    options.name_IDs = []  # name 表稍後整個重寫
    subsetter = Subsetter(options=options)
    subsetter.populate(unicodes=KEEP_UNICODES)
    subsetter.subset(font)

    glyf = font["glyf"]
    hmtx = font["hmtx"]
    bar_glyph_name = "uni2015"
    pen = TTGlyphPen(None)
    pen.moveTo((BAR_X_MIN, BAR_Y_MIN))
    pen.lineTo((BAR_X_MAX, BAR_Y_MIN))
    pen.lineTo((BAR_X_MAX, BAR_Y_MAX))
    pen.lineTo((BAR_X_MIN, BAR_Y_MAX))
    pen.closePath()
    glyf[bar_glyph_name] = pen.glyph()
    hmtx[bar_glyph_name] = (1000, BAR_X_MIN)

    for table in font["cmap"].tables:
        if not table.isUnicode():
            continue
        for cp in DASH_UNICODES:
            table.cmap[cp] = bar_glyph_name

    name = font["name"]
    name.names = []
    for name_id, value in {
        1: FAMILY,
        2: "Regular",
        3: f"{FAMILY}-Regular; derived from Noto Sans TC (OFL 1.1)",
        4: f"{FAMILY} Regular",
        6: f"{FAMILY}-Regular",
        13: "This Font Software is licensed under the SIL Open Font "
        "License, Version 1.1.",
    }.items():
        name.setName(value, name_id, 3, 1, 0x409)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)

    check = TTFont(OUT)
    cmap = check.getBestCmap()
    widths = check["hmtx"]
    for cp in sorted(set(KEEP_UNICODES + DASH_UNICODES)):
        glyph = cmap.get(cp)
        assert glyph is not None, f"U+{cp:04X} 缺字形"
        advance = widths[glyph][0]
        assert advance == 1000, f"U+{cp:04X} advance={advance}"
        print(f"U+{cp:04X} -> {glyph} advance={advance}")
    print(f"OK: {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
