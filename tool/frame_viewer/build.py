"""把 `test/support/frame_recording.dart` 錄下的候選做成逐格錄影頁。

    python tool/frame_viewer/build.py <設定檔.json>

設定檔放在 repo 外（例如 %TEMP%），格式見 `tool/frame_viewer/example.json`。
輸出在錄影資料夾的 `viewer/`：`page.html`、每段候選一張拼圖（每格一小張，
一列 16 格）與 `data.png`（每格的量測編成 PNG，頁面用 canvas 讀回）。頁面
引用的圖都是絕對路徑：把 `page.html` 的內容整份先交給 html_preview 看一次、
取它回報的高度，再交給 html_render，T3 會把圖內嵌進去，在對話裡直接逐格
播放。

候選與檔名：每個候選（`designs`，含「目前」當對照）配上每個變化
（`variants`，例如兩種間隔；`fixed` 的候選不分變化），淺色、深色各錄一段，
名稱是「<候選>-<變化>-<light|dark>」。頁面上的段落名稱、各段說明（可依候選
不同，`{variant}` 換成變化的 value、`{欄位}` 換成候選的同名欄位）、要畫深淺
的位置（手機邏輯座標）與跳轉按鈕都在設定檔裡。`limitMs` 是電腦上動畫中一格的上限，
不給時是 4.2（手機 8.3ms 照 2 倍換算，ADR 0029、0036）；主執行緒那排每格扣掉測試的
資料庫時間（`db_clock.dart`，手機上不在主執行緒）與閱讀器排版切片的一半（`slice_clock.dart`，
照時間切、手機上一樣長）再和它比。錄影時開了 `FRAME_GC=1`，
頁面多一排「回收記憶體」；`gcPhoneRatio` 是手機上回收比電腦慢幾倍（ADR 0029 定 2 倍），
照它畫出換算到手機會超過一格的線。

需要 ffmpeg、numpy 與 Pillow。
"""
import json
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
COLS = 16
PAGE_WIDTH, PHONE_GAP, MAX_TILE = 728, 12, 168
# 和上一格比，任何一個顏色差超過這個值的像素才算變了。錄下的是沒有壓縮的
# 原始像素，沒有雜訊；呼吸這類慢慢變的動畫每格只差一兩階，門檻要是 0 才看得到。
CHANGE_THRESHOLD = 0


def candidate_names(config):
    variants = config.get('variants') or [None]
    for design in config['designs']:
        for variant in ([None] if design.get('fixed') else variants):
            base = design['key'] + (f"-{variant['key']}" if variant else '')
            for theme in ('light', 'dark'):
                yield base, theme


def luminance(frame, x, y):
    patch = frame[max(0, y - 1):y + 2, max(0, x - 1):x + 2, :3].reshape(-1, 3)
    return float((patch @ np.array([0.299, 0.587, 0.114])).mean())


def measure(meta, frames, spots):
    rows = []
    previous = None
    for frame in frames:
        rgb = frame[:, :, :3].astype(np.int16)
        change = 0 if previous is None else int((np.abs(rgb - previous).max(axis=2) > CHANGE_THRESHOLD).sum())
        previous = rgb
        row = [change]
        if spots:
            bg = luminance(frame, *spots['background'])
            row += [round(abs(bg - luminance(frame, p['x'], p['y']))) for p in spots['points']]
        rows.append(row)
    return {
        'n': len(frames),
        'phases': meta['phases'][:len(frames)],
        'costs': meta['costs'][:len(frames)],
        'db': meta.get('db', [])[:len(frames)],
        'slice': meta.get('slice', [])[:len(frames)],
        'frameMs': meta.get('frameMs', 16),
        'gcNew': meta.get('gcNew', [])[:len(frames)],
        'gcOld': meta.get('gcOld', [])[:len(frames)],
        'frames': rows,
    }


def sprite(path, meta, tile, out):
    rows = math.ceil(len(meta['phases']) / COLS)
    subprocess.run(
        ['ffmpeg', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgba',
         '-s', f"{meta['width']}x{meta['height']}", '-i', path,
         '-vf', f'scale={tile[0]}:{tile[1]},tile={COLS}x{rows}', '-frames:v', '1',
         '-c:v', 'libwebp', '-quality', '60', out],
        check=True)


def encode_data(data, out):
    raw = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    # 前兩個像素放長度，之後每個像素的 RGB 各放一個位元組，A 固定 255（不透明
    # 的像素讀回來不會被預乘改掉）。
    payload = len(raw).to_bytes(4, 'big') + b'\0\0' + raw
    side = math.ceil(math.sqrt(math.ceil(len(payload) / 3)))
    payload += b'\0' * (side * side * 3 - len(payload))
    Image.frombytes('RGB', (side, side), payload).convert('RGBA').save(out, optimize=True)


def main():
    with open(sys.argv[1], encoding='utf-8') as f:
        config = json.load(f)
    recordings = config.get('recordings') or os.path.join(
        os.environ.get('TEMP') or os.environ.get('TMPDIR') or '/tmp', 'night-reader-frames')
    out_dir = os.path.join(recordings, 'viewer')
    os.makedirs(out_dir, exist_ok=True)
    count = len(config['designs'])
    tile_w = min(MAX_TILE, (PAGE_WIDTH - PHONE_GAP * (count - 1)) // count)
    data, sprites, tile = {}, {}, None
    for base, theme in candidate_names(config):
        name = f'{base}-{theme}'
        src = os.path.join(recordings, name)
        if not os.path.isfile(os.path.join(src, 'meta.json')):
            if theme == 'light':
                sys.exit(f'缺少錄影：{src}')
            continue
        with open(os.path.join(src, 'meta.json'), encoding='utf-8') as f:
            meta = json.load(f)
        w, h = meta['width'], meta['height']
        tile = (tile_w, round(tile_w * h / w / 2) * 2)
        raw = os.path.join(src, 'frames.rgba')
        frames = np.memmap(raw, np.uint8, 'r').reshape(-1, h, w, 4)
        out = os.path.join(out_dir, f'{name}.webp')
        sprite(raw, meta, tile, out)
        sprites[name] = out.replace('\\', '/')
        if theme == 'light':
            data[base] = measure(meta, frames, config.get('spots'))
        print(name, len(frames), 'frames', os.path.getsize(out) // 1024, 'KB')
    data_png = os.path.join(out_dir, 'data.png')
    encode_data(data, data_png)
    page_config = {k: config[k] for k in
                   ('designs', 'variants', 'phases', 'notes', 'spots', 'jumps', 'end', 'limitMs', 'start', 'gcPhoneRatio')
                   if k in config}
    page_config['tile'] = tile
    with open(os.path.join(HERE, 'template.html'), encoding='utf-8') as f:
        html = f.read()
    for key, value in {
        '/*TITLE*/': config.get('title', '動畫儀表板'),
        '/*CONFIG*/': json.dumps(page_config, ensure_ascii=False),
        '/*SPRITES*/': json.dumps(sprites, ensure_ascii=False, indent=0),
        '/*DATA_PNG*/': json.dumps(data_png.replace('\\', '/')),
    }.items():
        html = html.replace(key, value)
    page = os.path.join(out_dir, 'page.html')
    with open(page, 'w', encoding='utf-8', newline='\n') as f:
        f.write(html)
    print(page, len(html), 'chars')


if __name__ == '__main__':
    main()
