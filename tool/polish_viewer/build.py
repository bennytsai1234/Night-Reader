"""把 `test/polish/` 的細節檢查結果做成總覽頁。

    python tool/polish_viewer/build.py [結果資料夾]

結果資料夾預設是系統暫存區的 `night-reader-polish`（`report.json` 與截圖），
輸出在它底下的 `viewer/`：`page.html` 與每處換場裁下來的小圖。頁面引用的圖
都是絕對路徑：把 `page.html` 的內容整份先交給 html_preview 看一次、取它回報
的高度，再交給 html_render，T3 會把圖內嵌進去。

頁面：上面是總覽（每個情境一列、淺色深色各一格，點格子跳到那個情境）；下面
每個情境列出對不上的換場，每種骨架樣子一張圖，淺色、深色並排（兩邊結果
不同時分開列）：藍色虛線是骨架的條，實線是換上來的內容該在的位置，顏色照
問題種類；最後一張是換場後的畫面。上方的時間軸標出每種樣子停在哪幾格。

需要 Pillow。
"""
import html
import json
import os
import sys
import tempfile

from PIL import Image

PHONE_WIDTH = 393  # 手機邏輯寬度，同 test/support/screenshot.dart
MARGIN = 10  # 換場那一區上下多裁的邏輯像素
CROP_SCALE = 2  # 小圖每個邏輯像素存幾個實體像素
FRAME_MS = 16

# 問題種類：顏色寫在 template.html 的 .k-<種類>。
KINDS = {
    'short': '骨架太短',
    'long': '骨架太長',
    'shifted': '位置不同',
    'missing': '沒有骨架',
    'extra': '骨架多出',
}
MODES = {'light': '淺色', 'dark': '深色'}
PHONE_HEIGHT = 852
# 頁面元件的名稱（`skeleton_handoff.dart` 寫在 place 開頭）換成畫面的名字。
PAGES = {
    'ReaderV2Page': '閱讀器',
    'BookshelfPage': '書架',
    'BookDetailPage': '書籍詳情',
    'ExplorePage': '發現',
    'ExploreShowPage': '發現的書單',
    'SourceManagerPage': '書源管理',
    'DownloadManagerPage': '下載佇列',
    'SearchPage': '搜尋',
}


def esc(text):
    return html.escape(str(text))


def place_of(slot):
    """「閱讀器・畫面下方」：哪個畫面、在畫面上半還是下半。"""
    page = slot['place'].split(' ', 1)[0]
    x, y, w, h = slot['area']
    side = '畫面上方' if y + h / 2 < PHONE_HEIGHT / 2 else '畫面下方'
    return f'{PAGES.get(page, page)}・{side}'


def crop(image_path, top, height, out_path):
    """裁下 y 從 top 起 height 高的整條（邏輯像素），存成 webp。"""
    with Image.open(image_path) as image:
        scale = image.width / PHONE_WIDTH
        box = (0, round(top * scale), image.width,
               round((top + height) * scale))
        part = image.crop(box).resize(
            (PHONE_WIDTH * CROP_SCALE, round(height * CROP_SCALE)),
            Image.LANCZOS)
        part.save(out_path, 'WEBP', quality=90)
    return out_path.replace('\\', '/')


def rect_svg(rect, origin, cls):
    x, y, w, h = rect
    return (f'<rect class="{cls}" x="{x + origin[0]:.1f}" '
            f'y="{y + origin[1]:.1f}" width="{w:.1f}" height="{h:.1f}"/>')


def frame(src, top, height, shapes, label):
    view = f'0 {top:.1f} {PHONE_WIDTH} {height:.1f}'
    return (f'<div class="pane"><div class="mode">{label}</div>'
            f'<div class="frame"><img src="{esc(src)}">'
            f'<svg viewBox="{view}" preserveAspectRatio="none">'
            f'{"".join(shapes)}</svg></div></div>')


def signature(slot):
    """比淺色、深色是不是同一個結果：每種骨架樣子的條與問題。"""
    return [([tuple(b) for b in s['bars']],
             [p['message'] for p in s['problems']])
            for s in slot['snapshots']] + [
        [tuple(m['rect']) for m in slot['content']]]


def problems_of(slot):
    seen = []
    for snapshot in slot['snapshots']:
        for problem in snapshot['problems']:
            key = (problem['kind'], problem['message'].split('：')[0])
            if key not in seen:
                seen.append(key)
    if slot.get('stuck'):
        seen.append(('stuck', '骨架一直沒換成內容'))
    return seen


def timeline(slot, anchor):
    end = max([slot.get('contentFrame') or 0] +
              [s['lastFrame'] for s in slot['snapshots']]) + 1
    width = 680
    parts = []
    for i, snapshot in enumerate(slot['snapshots']):
        x0 = snapshot['firstFrame'] / end * width
        x1 = (snapshot['lastFrame'] + 1) / end * width
        bad = bool(snapshot['problems'])
        ms0 = snapshot['firstFrame'] * FRAME_MS
        ms1 = (snapshot['lastFrame'] + 1) * FRAME_MS
        parts.append(
            f'<a href="#{anchor}-s{i}"><rect class="{"bad" if bad else "good"}"'
            f' x="{x0:.1f}" y="4" width="{max(x1 - x0, 3):.1f}" height="18">'
            f'<title>第 {i + 1} 種樣子：{ms0}–{ms1} ms'
            f'{"，有問題" if bad else "，對得上"}</title></rect>'
            f'<text x="{(x0 + x1) / 2:.1f}" y="17" class="tl">{i + 1}</text>'
            '</a>')
    if slot.get('contentFrame') is not None:
        x = slot['contentFrame'] / end * width
        parts.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="0" y2="26"/>')
        parts.append(f'<text x="{min(x + 4, width - 80):.1f}" y="38" '
                     f'class="tlc">換成內容 {slot["contentFrame"] * FRAME_MS} ms'
                     '</text>')
    parts.append('<text x="0" y="38" class="tlc">點下去 0 ms</text>')
    return (f'<svg class="timeline" viewBox="0 0 {width} 42" '
            f'width="{width}" height="42">{"".join(parts)}</svg>')


def at_rest_image(slot):
    """停著的時候拍的圖（骨架層在畫面上的左緣是 0）。頁面滑進來的整段時間
    都是同一種骨架樣子時，那一種沒有停著的圖，改用之後停著的圖當底；框線
    本來就是相對位置，照停下來的位置畫。"""
    for s in slot['snapshots']:
        if s.get('image') and abs(s['origin'][0]) < 0.5:
            return s['image'], s['origin']
    if slot.get('contentImage') and abs(slot['contentOrigin'][0]) < 0.5:
        return slot['contentImage'], slot['contentOrigin']
    return None


def snapshot_frame(slot, snapshot, i, mode, out_dir, anchor):
    image, origin = snapshot.get('image'), snapshot['origin']
    moving = abs(origin[0]) >= 0.5
    if moving and at_rest_image(slot):
        image, origin = at_rest_image(slot)
    if not image:
        return None, moving
    height = slot['area'][3] + MARGIN * 2
    top = origin[1] - MARGIN
    src = crop(image, top, height,
               os.path.join(out_dir, f'{anchor}-{mode}-s{i}.webp'))
    shapes = [rect_svg(bar, origin, 'b') for bar in snapshot['bars']]
    for problem in snapshot['problems']:
        rect = problem['real'] or problem['bar']
        if rect:
            shapes.append(rect_svg(rect, origin, f'k-{problem["kind"]}'))
    return frame(src, top, height, shapes, MODES[mode]), moving


def content_frame(slot, mode, out_dir, anchor):
    if not slot.get('contentImage'):
        return None
    origin = slot['contentOrigin']
    height = slot['area'][3] + MARGIN * 2
    top = origin[1] - MARGIN
    src = crop(slot['contentImage'], top, height,
               os.path.join(out_dir, f'{anchor}-{mode}-content.webp'))
    shapes = [rect_svg(m['rect'], origin, 'c') for m in slot['content']]
    return frame(src, top, height, shapes, MODES[mode])


def slot_section(anchor, by_mode, out_dir):
    """一處換場；[by_mode] 是同一個結果的各模式（淺色、深色）。"""
    first_mode, first = next(iter(by_mode.items()))
    rows = []
    for i, snapshot in enumerate(first['snapshots']):
        panes, moving = [], False
        for mode, slot in by_mode.items():
            pane, m = snapshot_frame(slot, slot['snapshots'][i], i, mode,
                                     out_dir, anchor)
            moving = moving or m
            if pane:
                panes.append(pane)
        ms0 = snapshot['firstFrame'] * FRAME_MS
        ms1 = (snapshot['lastFrame'] + 1) * FRAME_MS
        notes = ''.join(
            f'<li><span class="dot k-{p["kind"]}"></span>{esc(p["message"])}'
            '</li>' for p in snapshot['problems']
        ) or '<li class="ok">每一條都對得上</li>'
        if moving:
            notes = ('<li class="note">這段時間頁面還在滑進來；底圖是停下來後'
                     '那一格，框線是這段時間骨架的樣子</li>') + notes
        rows.append(
            f'<figure class="shot" id="{anchor}-s{i}">'
            f'<div class="panes">{"".join(panes)}</div>'
            f'<figcaption><b>骨架第 {i + 1} 種樣子</b>　{ms0}–{ms1} ms'
            f'<ul>{notes}</ul></figcaption></figure>')
    panes = [p for p in (content_frame(slot, mode, out_dir, anchor)
                         for mode, slot in by_mode.items()) if p]
    if panes:
        labels = '、'.join(f'「{m["text"]}」' if m['text'] else '圖示'
                          for m in first['content'])
        rows.append(
            f'<figure class="shot"><div class="panes">{"".join(panes)}</div>'
            f'<figcaption><b>換場後</b>　{first["contentFrame"] * FRAME_MS} ms'
            f'<ul><li class="ok">換上來的內容：{esc(labels)}</li></ul>'
            '</figcaption></figure>')
    modes = '、'.join(MODES[m] for m in by_mode)
    return (f'<section class="slot"><h4>{esc(place_of(first))}'
            f'<span class="modes">{modes}</span></h4>'
            f'{timeline(first, anchor)}{"".join(rows)}</section>')


def main():
    src_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        tempfile.gettempdir(), 'night-reader-polish')
    with open(os.path.join(src_dir, 'report.json'), encoding='utf-8') as f:
        runs = json.load(f)
    out_dir = os.path.join(src_dir, 'viewer')
    os.makedirs(out_dir, exist_ok=True)

    scenarios = {}
    for run in runs:
        scenarios.setdefault(run['scenario'], {'title': run['title'],
                                               'runs': {}})
        scenarios[run['scenario']]['runs'][run['mode']] = run
    modes = [m for m in MODES if any(r['mode'] == m for r in runs)]

    cells = {}
    details = []
    for name, scenario in scenarios.items():
        sections = []
        for mode, run in scenario['runs'].items():
            if run.get('error'):
                cells[(name, mode)] = ('bad', '操作失敗')
                sections.append(f'<p class="note">{MODES[mode]}：操作失敗：'
                                f'{esc(run["error"])}</p>')
                continue
            count = sum(len(problems_of(s)) for s in run['slots'])
            if not run['sawSkeleton']:
                cells[(name, mode)] = ('none', '沒看到骨架')
                # 留下的最後畫面：看得到那時畫面上是什麼。
                if run.get('endImage'):
                    src = crop(run['endImage'], 0, PHONE_HEIGHT, os.path.join(
                        out_dir, f'{name}-{mode}-end.webp'))
                    sections.append(
                        f'<figure class="end"><img src="{esc(src)}">'
                        f'<figcaption>{MODES[mode]}：沒看到骨架，這是最後的'
                        f'畫面</figcaption></figure>')
            elif count == 0:
                cells[(name, mode)] = ('ok', '全部對得上')
            else:
                cells[(name, mode)] = ('bad', f'{count} 個問題')
        # 每處換場：淺色、深色結果一樣時並排畫一次，不一樣時各畫各的。
        slot_count = max(len(r.get('slots', []))
                         for r in scenario['runs'].values())
        for index in range(slot_count):
            by_mode = {mode: run['slots'][index]
                       for mode, run in scenario['runs'].items()
                       if index < len(run.get('slots', []))
                       and problems_of(run['slots'][index])}
            if not by_mode:
                continue
            groups = {}
            for mode, slot in by_mode.items():
                key = json.dumps(signature(slot))
                groups.setdefault(key, {})[mode] = slot
            for group in groups.values():
                anchor = f'{name}-slot{index}-{"-".join(group)}'
                sections.append(slot_section(anchor, group, out_dir))
        if sections:
            details.append(f'<article id="{name}"><h3>'
                           f'{esc(scenario["title"])}</h3>'
                           f'{"".join(sections)}</article>')

    header = ''.join(f'<th>{MODES[m]}</th>' for m in modes)
    rows = []
    for name, scenario in scenarios.items():
        tds = []
        for mode in modes:
            state, text = cells.get((name, mode), ('none', '沒跑'))
            link = f' href="#{name}"' if state != 'ok' else ''
            tds.append(f'<td><a class="cell {state}"{link}>{text}</a></td>')
        rows.append(f'<tr><th class="name">{esc(scenario["title"])}</th>'
                    f'{"".join(tds)}</tr>')
    legend = ('<span><i class="b"></i>骨架的條</span>'
              '<span><i class="c"></i>換上來的內容</span>' +
              ''.join(f'<span><i class="k-{k}"></i>{t}</span>'
                      for k, t in KINDS.items()))

    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           'template.html'), encoding='utf-8') as f:
        page = f.read()
    page = (page.replace('<!--HEADER-->', header)
                .replace('<!--ROWS-->', ''.join(rows))
                .replace('<!--LEGEND-->', legend)
                .replace('<!--DETAILS-->', ''.join(details)
                         or '<p class="ok">每個情境都對得上。</p>'))
    out = os.path.join(out_dir, 'page.html')
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(page)
    print(out, len(page), 'chars')


if __name__ == '__main__':
    main()
