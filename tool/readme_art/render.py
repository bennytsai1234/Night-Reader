"""把 card.html 的每張卡片用 Chrome 拍成 README 用的圖，存到 docs/readme/。

用法（在 repo 根目錄）：python -I tool/readme_art/render.py [卡片名稱 ...]
沒給名稱就全部重拍；卡片清單與內容在 cards.js。截圖、短片與天空圖取自 website/，
網站重拍後跟著重跑。

有動畫的格子（cards.js 的 "a"）：先把那一格的螢幕塗成洋紅色拍一張，洋紅色的濃淡就是
遮罩，再把短片（clip:名稱，website/clips/）或幾張截圖輪流（wipe:a,b,… 由左而右掃過、
fade:a,b,… 淡入淡出）一幀一幀貼進去，存成會動的 webp。devices:手機圖,平板圖 是舞台：
那格不畫手機框，外框與螢幕都由這裡逐幀畫，手機與平板來回變形。
"""
import json
import pathlib
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

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


DEVICE_PAD = 110  # 舞台四周多畫的範圍（px，2 倍），裝置變寬與陰影用
TEXT_GAP = 30  # 舞台下緣往下多少 px 之後是功能名，陰影在這之前淡掉，不壓到字
TABLET_W = 1.12  # 平板寬是手機的幾倍；再寬會碰到隔壁的手機
HOLD = (0.4, 0.6)  # 手機、平板各停多久（佔一圈扣掉兩次切換後的比例）
MORPH = 0.75  # 秒，一次切換


def ease(p):
    return p * p * (3 - 2 * p)


def device_layer(size, rect, pad, radius, inner_radius, screen, shadow=True):
    """在 size 大的透明圖上畫一台裝置：黑框、圓角螢幕、網站同款陰影，screen 是螢幕圖（RGB，已縮好）。"""
    x, y, w, h = rect
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    if shadow:
        sh = Image.new('L', size, 0)
        ImageDraw.Draw(sh).rounded_rectangle((x, y + 36, x + w, y + h + 36), radius, fill=round(255 * 0.55))
        layer.putalpha(sh.filter(ImageFilter.GaussianBlur(44)))
    body = Image.new('L', size, 0)
    ImageDraw.Draw(body).rounded_rectangle((x, y, x + w, y + h), radius, fill=255)
    layer.paste((0, 0, 0, 255), (0, 0), body)
    ImageDraw.Draw(layer).rounded_rectangle((x, y, x + w - 1, y + h - 1), radius, outline=(255, 255, 255, 41), width=2)
    sx, sy = round(x + pad), round(y + pad)
    m = Image.new('L', screen.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, screen.width - 1, screen.height - 1), inner_radius, fill=255)
    layer.paste(screen, (sx, sy), m)
    return layer


def devices_frames(names, stage, n):
    """舞台：手機那格先放手機，再換成平板，停一下換回手機，循環接得起來。
    外框照網站的手機框與平板框畫，螢幕圖用 website/shots/ 的兩張；兩張字的位置不同，
    所以外框變形的同時照 fade 的做法先淡到紙色再淡入，兩頁的字不同時出現
    （使用者 2026-11-08 選定；滑出滑入會讓兩台與兩頁的字疊在一起）。"""
    w0, h0 = stage
    size = (w0 + 2 * DEVICE_PAD, h0 + 2 * DEVICE_PAD)
    k = w0 / 134  # 卡片裡手機寬 134 css px
    wt = round(w0 * TABLET_W)
    ht = round(wt * 1280 / 800)
    phone = dict(rect=(DEVICE_PAD, DEVICE_PAD, w0, h0), pad=4 * k, radius=15 * k, inner=11.5 * k)
    tablet = dict(rect=(DEVICE_PAD - (wt - w0) / 2, DEVICE_PAD + (h0 - ht) / 2, wt, ht),
                  pad=5 * k, radius=9 * k, inner=6 * k)
    src = [Image.open(WEB / 'shots' / f'{s}.webp').convert('RGB') for s in names]
    paper = [np.median(np.asarray(i).reshape(-1, 3), axis=0) for i in src]

    def screen(spec, img_i, dim):
        x, y, w, h = spec['rect']
        sw, sh = round(w - 2 * spec['pad']), round(h - 2 * spec['pad'])
        img = ImageOps.fit(src[img_i], (sw, sh), Image.LANCZOS)
        if dim > 0:
            a = np.asarray(img, dtype=np.float32)
            img = Image.fromarray((a * (1 - dim) + paper[img_i] * dim).astype(np.uint8))
        return img

    def lerp(a, b, p):
        r = tuple(a['rect'][i] + (b['rect'][i] - a['rect'][i]) * p for i in range(4))
        return dict(rect=tuple(round(v) for v in r),
                    **{key: a[key] + (b[key] - a[key]) * p for key in ('pad', 'radius', 'inner')})

    def draw(spec, img_i, dim):
        return device_layer(size, spec['rect'], spec['pad'], spec['radius'], spec['inner'], screen(spec, img_i, dim))

    loop = n / FPS
    hold = [(loop - 2 * MORPH) * h for h in HOLD]
    marks = [0, hold[0], hold[0] + MORPH, hold[0] + MORPH + hold[1], loop]
    devs = [phone, tablet]
    out = []
    for f in range(n):
        t = f / FPS
        if t < marks[1]:
            lay = draw(phone, 0, 0)
        elif marks[2] <= t < marks[3]:
            lay = draw(tablet, 1, 0)
        else:
            fwd = t < marks[2]
            p = (t - (marks[1] if fwd else marks[3])) / MORPH
            a, b = (0, 1) if fwd else (1, 0)
            spec = lerp(devs[a], devs[b], ease(p))
            lay = draw(spec, a, p * 2) if p < 0.5 else draw(spec, b, 2 - p * 2)
        out.append(lay)
    return out


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
    parts, stages = [], []
    for i, spec in enumerate(slots):
        alpha = magenta(shoot(name, tmp, i).crop(box))
        ys, xs = np.nonzero(alpha > 0.02)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        if spec.startswith('devices:'):
            fr = devices_frames(spec.split(':', 1)[1].split(','), (x1 - x0, y1 - y0), n)
            stages.append((x0 - DEVICE_PAD, y0 - DEVICE_PAD, y1, fr))
            continue
        parts.append((y0, y1, x0, x1, alpha[y0:y1, x0:x1, None], frames_for(spec, (x1 - x0, y1 - y0), n)))
    b = np.asarray(base, dtype=np.float32)
    frames = []
    for f in range(n):
        a = b.copy()
        for y0, y1, x0, x1, al, fr in parts:
            a[y0:y1, x0:x1, :3] += al * (np.asarray(fr[f], dtype=np.float32) - KEY)
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA')
        for x, y, bottom, fr in stages:
            lay = fr[f].copy()
            # 陰影在舞台下緣到功能名之間淡掉，不蓋到字
            cut = np.asarray(lay.getchannel('A'), dtype=np.float32)
            rows = np.arange(lay.height, dtype=np.float32)[:, None] + y - bottom
            cut = cut * np.clip(1 - rows / TEXT_GAP, 0, 1)
            lay.putalpha(Image.fromarray(cut.astype(np.uint8)))
            im.alpha_composite(lay, (x, y))
        frames.append(im)
    save(base, frames, name)


all_cards = cards()
with tempfile.TemporaryDirectory() as tmp:
    for n in sys.argv[1:] or list(all_cards):
        render(n, all_cards[n], tmp)
