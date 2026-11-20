"""量截圖上的間距：由上往下把底色以外的東西切成一段段，印出每段的上下緣與
段與段之間的空白；卡片（左緣內側整段同一個非底色）裡面照卡片的底色再切一次，
印出卡片裡每一塊到上一塊（或卡片頂）的距離、最後一塊到卡片底的距離。

    python -I tool/spacing_bands.py <截圖.png>... [--scale 3]

截圖用 test/screens/app_screens_test.dart 拍（手機 3 倍，數字換算回邏輯像素）。
量到的是畫出來的筆畫，字型的上下留白算在空白裡：差 1～4 的多半是字型造成的，
先看版面（元件的內距）是不是對稱，再下結論。分隔線（高 1 以下）標成 sep。
頁首漸隱、玻璃這類漸層蓋在內容上時，量到的邊不準，捲到頂或底再拍。
"""
import argparse

import numpy as np
from PIL import Image

MARGIN = 16  # 卡片離螢幕左右
RADIUS = 14  # 卡片圓角：判斷卡片與切卡片內部時避開
PAGE_THRESHOLD = 18  # 和頁面底色差多少算有東西
CARD_THRESHOLD = 6  # 卡片裡的分隔線、分段控制的軌道很淡，門檻低一點


def _bands(mask):
    out, start = [], None
    for y, value in enumerate(mask):
        if value and start is None:
            start = y
        if not value and start is not None:
            out.append((start, y))
            start = None
    if start is not None:
        out.append((start, len(mask)))
    return out


def _differs(pixels, color, threshold):
    return np.abs(pixels.astype(int) - np.array(color)).max(axis=-1) > threshold


def analyze(path, scale):
    image = np.asarray(Image.open(path).convert('RGB'))
    height, width, _ = image.shape
    page = tuple(int(v) for v in image[height // 2, 2])
    left, right = int(2 * scale), width - int(2 * scale)
    rows = _differs(image[:, left:right], page, PAGE_THRESHOLD).any(axis=1)
    bands = []
    for top, bottom in _bands(rows):
        band = {'top': top / scale, 'bottom': bottom / scale}
        inner_top, inner_bottom = top + int(RADIUS * scale), bottom - int(RADIUS * scale)
        column = image[inner_top:max(inner_top + 1, inner_bottom), int((MARGIN + 4) * scale)]
        if bottom - top > 2 * RADIUS * scale and len(column):
            card = tuple(int(v) for v in np.median(column, axis=0))
            uniform = (~_differs(column, card, PAGE_THRESHOLD)).mean() > 0.9
            if uniform and _differs(np.array([card]), page, PAGE_THRESHOLD).any():
                x0, x1 = int((MARGIN + RADIUS) * scale), width - int((MARGIN + RADIUS) * scale)
                inside = _differs(image[top:bottom, x0:x1], card, CARD_THRESHOLD).any(axis=1)
                band['inner'] = [
                    {
                        'top': (top + a) / scale,
                        'bottom': (top + b) / scale,
                        'kind': 'sep' if (b - a) / scale <= 1.0 else 'ink',
                    }
                    for a, b in _bands(inside)
                ]
        bands.append(band)
    return bands


def report(path, scale):
    print(f'== {path}')
    previous = None
    for band in analyze(path, scale):
        gap = '' if previous is None else f"  空白 {band['top'] - previous:5.1f}"
        kind = '卡片' if 'inner' in band else '    '
        print(f"  {kind} {band['top']:6.1f}–{band['bottom']:6.1f}{gap}")
        if 'inner' in band:
            above = band['top']
            for part in band['inner']:
                print(f"      {part['kind']} {part['top']:6.1f}–{part['bottom']:6.1f}  上方 {part['top'] - above:5.1f}")
                above = part['bottom']
            print(f"      到卡片底 {band['bottom'] - above:5.1f}")
        previous = band['bottom']


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('images', nargs='+')
    parser.add_argument('--scale', type=float, default=3.0, help='截圖的裝置像素比')
    args = parser.parse_args()
    for image in args.images:
        report(image, args.scale)
