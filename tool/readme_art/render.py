"""把 card.html 的每張卡片用 Chrome 拍成 README 用的圖，存到 docs/readme/。

用法（在 repo 根目錄）：python -I tool/readme_art/render.py [卡片名稱 ...]
沒給名稱就全部重拍；卡片清單與內容在 cards.js。截圖、短片與天空圖取自 website/，
網站重拍後跟著重跑。

有動畫的格子（cards.js 的 "a"）：先把那一格的螢幕塗成洋紅色拍一張，洋紅色的濃淡就是
遮罩，再把短片（clip:名稱，website/clips/）或幾張截圖輪流（wipe:a,b,… 由左而右掃過、
fade:a,b,… 淡入淡出）一幀一幀貼進去，存成會動的 webp。
"""
import json
import pathlib
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageOps

CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe'
ROOT = pathlib.Path(__file__).resolve().parents[2]
ART = ROOT / 'tool' / 'readme_art'
WEB = ROOT / 'website'
OUT = ROOT / 'docs' / 'readme'

FPS = 30  # 和網站的短片一樣，短片的每一幀都用上
LOOP = 6.0  # 秒；短片 3 秒播兩次，wipe／fade 每張停 LOOP / 張數
SWITCH = 0.45  # 秒，wipe／fade 換下一張的時間
KEY = np.array([255, 0, 255], dtype=np.float32)
ANIM_ENCODE = {'lossless': True, 'quality': 100, 'method': 4, 'minimize_size': True}


def cards():
    text = (ART / 'cards.js').read_text(encoding='utf-8')
    return json.loads(text[text.index('{'):text.rindex('}') + 1])


def shoot(name, tmp, slot=None):
    png = pathlib.Path(tmp) / f'{name}-{slot}.png'
    url = (ART / 'card.html').as_uri() + f'?k={name}' + (f'&slot={slot}' if slot is not None else '')
    subprocess.run([
        CHROME, '--headless=new', '--hide-scrollbars', '--force-device-scale-factor=2',
        '--default-background-color=00000000', '--allow-file-access-from-files',
        '--virtual-time-budget=4000', '--window-size=830,1400', f'--screenshot={png}', url,
    ], check=True, capture_output=True)
    return Image.open(png).convert('RGBA')


def slots_of(card):
    if card['type'] == 'row':
        return [it['a'] for it in card['items'] if it.get('a')]
    return [card['a']] if card.get('a') else []


def clip_frames(arg, size, n):
    """短片照 FPS 取 n 幀，裁成 size（照 cover 置中）。
    clip:名稱:hold 先停在最後一幀，最後才播一次，第一幀與循環接縫都是播完的畫面。"""
    name, _, mode = arg.partition(':')
    with tempfile.TemporaryDirectory() as d:
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(WEB / 'clips' / f'{name}.mp4'),
                        '-vf', f'fps={FPS}', str(pathlib.Path(d) / '%03d.png')], check=True)
        src = [ImageOps.fit(Image.open(p).convert('RGB'), size, Image.LANCZOS)
               for p in sorted(pathlib.Path(d).glob('*.png'))]
    if mode == 'hold':
        rest = max(n - len(src), 0)
        return ([src[-1]] * rest + src)[:n]
    return [src[i % len(src)] for i in range(n)]


def seq_frames(names, size, n, wipe):
    """幾張截圖輪流，每張停一段，最後 SWITCH 秒換成下一張。
    wipe：由左而右掃過去，只給版面相同、只換顏色或封面的幾張用。
    fade：版面會動的（隱藏廣告、正文整理，字的位置前後不同）掃過或交叉淡化都會讓兩頁的字
    疊在一起、像壞掉，所以前半段淡到只剩紙色、後半段再淡入下一張，兩頁的字不同時出現。"""
    imgs = [ImageOps.fit(Image.open(WEB / 'shots' / f'{s}.webp').convert('RGB'), size, Image.LANCZOS)
            for s in names]
    arrs = [np.asarray(i, dtype=np.float32) for i in imgs]
    paper = [np.median(a.reshape(-1, 3), axis=0) for a in arrs]  # 字很稀，中位數就是紙色
    w = size[0]
    xs = np.arange(w, dtype=np.float32)[None, :, None]
    soft = w * 0.18
    seg = LOOP / len(names)
    out = []
    for f in range(n):
        t = f / FPS
        i = int(t // seg) % len(names)
        p = (t - i * seg - (seg - SWITCH)) / SWITCH
        if p <= 0:
            out.append(imgs[i])
            continue
        p = min(p, 1)
        j = (i + 1) % len(names)
        a, b = arrs[i], arrs[j]
        if wipe:
            p = 1 - (1 - p) ** 3  # 先快後慢
            edge = -soft + p * (w + 2 * soft)
            m = np.clip((edge - xs) / soft + 0.5, 0, 1)
            mix = a * (1 - m) + b * m
        elif p < 0.5:
            k = p * 2
            mix = a * (1 - k) + paper[i] * k
        else:
            k = (p - 0.5) * 2
            mix = paper[j] * (1 - k) + b * k
        out.append(Image.fromarray(mix.astype(np.uint8)))
    return out


def frames_for(spec, size, n):
    kind, arg = spec.split(':', 1)
    if kind == 'clip':
        return clip_frames(arg, size, n)
    return seq_frames(arg.split(','), size, n, wipe=kind == 'wipe')


def magenta(img):
    """每個像素有多少比例是洋紅色（螢幕圓角邊緣會是洋紅和黑框混出來的）。"""
    a = np.asarray(img, dtype=np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return np.clip((np.minimum(r, b) - g) / 255.0, 0, 1) * (a[..., 3] / 255.0)


def save(im, frames, name):
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / f'{name}.webp'
    if frames is None:
        im.save(dst, 'WEBP', quality=86, method=6)
    else:
        frames[0].save(dst, 'WEBP', save_all=True, append_images=frames[1:], duration=round(1000 / FPS),
                       loop=0, **ANIM_ENCODE)
    kb = dst.stat().st_size // 1024
    print(f'{name}: {im.size[0]}x{im.size[1]}' + (f' {len(frames)} 幀' if frames else '') + f' {kb} KB')


def render(name, card, tmp):
    slots = slots_of(card)
    base = shoot(name, tmp, 'all' if slots else None)
    box = base.getchannel('A').getbbox()
    base = base.crop(box)
    if not slots:
        return save(base, None, name)
    n = int(LOOP * FPS)
    parts = []
    for i, spec in enumerate(slots):
        alpha = magenta(shoot(name, tmp, i).crop(box))
        ys, xs = np.nonzero(alpha > 0.02)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        parts.append((y0, y1, x0, x1, alpha[y0:y1, x0:x1, None], frames_for(spec, (x1 - x0, y1 - y0), n)))
    b = np.asarray(base, dtype=np.float32)
    frames = []
    for f in range(n):
        a = b.copy()
        for y0, y1, x0, x1, al, fr in parts:
            a[y0:y1, x0:x1, :3] += al * (np.asarray(fr[f], dtype=np.float32) - KEY)
        frames.append(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA'))
    save(base, frames, name)


all_cards = cards()
with tempfile.TemporaryDirectory() as tmp:
    for n in sys.argv[1:] or list(all_cards):
        render(n, all_cards[n], tmp)
