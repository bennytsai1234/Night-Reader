"""全 App 動畫儀表板探索：把錄好的步驟做成每區的儀表板頁與一頁總覽。

    python make_pages.py <區> [<區> ...]     做這幾區的儀表板（每頁 4 步）
    python make_pages.py --overview          做總覽頁（讀已整理好的 meta.json）

錄影在 D:\\nr-survey\\tmp\\night-reader-frames（survey-manifest.jsonl 列出每一步），
整理後搬到 D:\\nr-survey\\pages\\<區>-<頁>\\，做完頁面就刪掉原始畫面
frames.rgba，只留 meta.json 與頁面用的圖。
"""
import json
import os
import shutil
import subprocess
import sys

ROOT = os.environ.get('NR_SURVEY_ROOT', r'D:\nr-survey')
REC = os.path.join(ROOT, 'tmp', 'night-reader-frames')
PAGES = os.path.join(ROOT, 'pages')
BUILD = r'D:\Migrated\Desktop\Folder\product\Night-Reader\tool\frame_viewer\build.py'
PER_PAGE = 4

PHASES = {
    '換頁': {'label': '換頁', 'kind': 'moving'},
    '換分頁': {'label': '換分頁', 'kind': 'moving'},
    '紙': {'label': '紙蓋著'},
    '掀紙': {'label': '掀紙', 'kind': 'moving'},
    '換場': {'label': '骨架換場', 'kind': 'moving'},
    '骨架': {'label': '骨架', 'kind': 'moving'},
    '捲動': {'label': '捲動', 'kind': 'moving'},
    '動畫': {'label': '其他動畫', 'kind': 'moving'},
    '靜止': {'label': '靜止'},
}
NOTES = {
    '換頁': '<b>換頁</b>：頁面推入、返回，或面板、選單進出場。',
    '換分頁': '<b>換分頁</b>：書架、發現、我的之間的轉場。',
    '紙蓋著': '<b>紙蓋著</b>：閱讀器排正文時蓋著的閱讀底色。',
    '掀紙': '<b>掀紙</b>：正文排好，紙照骨架換場掀開。',
    '骨架換場': '<b>骨架換場</b>：骨架由左而右換成內容。',
    '骨架': '<b>骨架</b>：資料還沒到，骨架在呼吸。',
    '捲動': '<b>捲動</b>：清單或頁面還在滑。',
    '其他動畫': '<b>其他動畫</b>：開關、按鈕、淡入淡出這類小動畫還在走。',
    '靜止': '<b>靜止</b>：畫面停下來了。',
}


def manifest():
    steps, seen = [], set()
    path = os.path.join(REC, 'survey-manifest.jsonl')
    with open(path, encoding='utf-8') as f:
        for line in f:
            s = json.loads(line)
            if s['key'] in seen:
                continue
            seen.add(s['key'])
            steps.append(s)
    return steps


def build_area(area, steps):
    chunks = [steps[i:i + PER_PAGE] for i in range(0, len(steps), PER_PAGE)]
    for n, chunk in enumerate(chunks, 1):
        page = os.path.join(PAGES, f'{area}-{n}')
        os.makedirs(page, exist_ok=True)
        for s in chunk:
            for mode in ('light', 'dark'):
                src = os.path.join(REC, f"{s['key']}-{mode}")
                if os.path.isdir(src):
                    dst = os.path.join(page, f"{s['key']}-{mode}")
                    if os.path.isdir(dst):
                        shutil.rmtree(dst)
                    shutil.move(src, dst)
        config = {
            'title': f'{area} 第 {n}/{len(chunks)} 頁',
            'recordings': page,
            'designs': [{'key': s['key'], 'name': s['label']} for s in chunk],
            'phases': PHASES,
            'notes': NOTES,
            'limitMs': 8,
        }
        cfg = os.path.join(page, 'config.json')
        with open(cfg, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(config, f, ensure_ascii=False, indent=1)
        subprocess.run([sys.executable, BUILD, cfg], check=True)
        for s in chunk:
            for mode in ('light', 'dark'):
                raw = os.path.join(page, f"{s['key']}-{mode}", 'frames.rgba')
                if os.path.isfile(raw):
                    os.remove(raw)
        print(f'PAGE {area}-{n}', os.path.join(page, 'viewer', 'page.html'), flush=True)


def overview():
    rows = []
    order = ['sample', 'tabs', 'launch', 'shelf', 'book', 'reader', 'search', 'explore',
             'download', 'sources', 'mine', 'mine2']
    pages = [p for p in os.listdir(PAGES)
             if os.path.isdir(os.path.join(PAGES, p)) and p.rsplit('-', 1)[-1].isdigit()]
    for page in sorted(pages, key=lambda p: (order.index(p.rsplit('-', 1)[0]), int(p.rsplit('-', 1)[1]))):
        cfg_path = os.path.join(PAGES, page, 'config.json')
        if not os.path.isfile(cfg_path):
            continue
        with open(cfg_path, encoding='utf-8') as f:
            cfg = json.load(f)
        for d in cfg['designs']:
            row = {'page': page, 'key': d['key'], 'label': d['name']}
            for mode in ('light', 'dark'):
                meta_path = os.path.join(PAGES, page, f"{d['key']}-{mode}", 'meta.json')
                if os.path.isfile(meta_path):
                    with open(meta_path, encoding='utf-8') as f:
                        meta = json.load(f)
                    row[mode] = {'costs': meta['costs'], 'phases': meta['phases']}
            rows.append(row)
    # 還在錄、還沒做成頁面的步驟（錄影資料夾裡的 meta.json）也列進來。
    done = {r['key'] for r in rows}
    if os.path.isfile(os.path.join(REC, 'survey-manifest.jsonl')):
        for s in manifest():
            if s['key'] in done:
                continue
            row = {'page': f"{s['area']}-錄影中", 'key': s['key'], 'label': s['label']}
            for mode in ('light', 'dark'):
                meta_path = os.path.join(REC, f"{s['key']}-{mode}", 'meta.json')
                if os.path.isfile(meta_path):
                    with open(meta_path, encoding='utf-8') as f:
                        meta = json.load(f)
                    row[mode] = {'costs': meta['costs'], 'phases': meta['phases']}
            rows.append(row)
    out = os.path.join(PAGES, 'overview.json')
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(rows, f, ensure_ascii=False)
    print('OVERVIEW', out, len(rows), 'steps')


if __name__ == '__main__':
    if sys.argv[1:] == ['--overview']:
        overview()
    else:
        steps = manifest()
        for area in sys.argv[1:]:
            build_area(area, [s for s in steps if s['area'] == area])
