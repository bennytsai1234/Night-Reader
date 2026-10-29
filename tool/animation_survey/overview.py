"""把 pages/overview.json 做成總覽頁 pages/overview.html。

    python overview.py

只有畫面在動（換頁、換場、骨架、捲動、其他動畫）時主執行緒超過 4.2ms 才算問題，
畫面靜止時的尖峰不算（使用者 2026-10-27 定的）。每一步一列：淺色、深色各一條
逐格的主執行緒長條（動畫中超過 4.2ms 的格子標紅、靜止時超過的標灰，長條頂到
32ms 截掉、頂端標記），旁邊是動畫中超過 4.2ms 的格數與動畫中最忙的一格。最上面
是動畫中超過 4.2ms 格數最多的 20 步。
"""
import json
import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_pages import survey_root  # noqa: E402

PAGES = os.path.join(survey_root(), 'pages')

AREA_NAMES = {
    'sample': '樣本：書架切換列表／網格', 'tabs': '換分頁', 'launch': '開 App 進場', 'shelf': '書架', 'book': '書籍詳情與目錄',
    'reader': '閱讀器', 'search': '搜尋', 'explore': '發現', 'download': '下載',
    'sources': '書源管理', 'mine': '「我的」：外觀與主題', 'mine2': '「我的」：其他各頁',
}

TEMPLATE = r'''<!doctype html>
<html lang="zh-Hant"><head><meta charset="utf-8">
<title>全 App 主執行緒總覽</title>
<style>
:root{--surface:var(--card,#fcfcfb);--ink:var(--foreground,#0b0b0b);--ink2:var(--muted-foreground,#52514e);--muted:var(--muted-foreground,#898781);
--grid:var(--border,#e1e0d9);--axis:var(--border,#c3c2b7);--ok:var(--chart-1,#86b6ef);--bar:var(--chart-1,#2a78d6);--crit:var(--destructive,#d03b3b);
--move:color-mix(in srgb,var(--chart-1,#2a78d6) 14%,transparent);--still:var(--muted-foreground,#b5b3ab);--dark:var(--chart-2,#86b6ef);}
body{margin:0;font-size:13px;line-height:1.5}
.wrap{padding:0}
h1{font-size:18px;margin:0 0 4px} h2{font-size:15px;margin:22px 0 6px}
.sub{color:var(--ink2);margin:0 0 12px}
.card{background:var(--surface);border-radius:8px;padding:12px 14px;margin-bottom:12px}
.tiles{display:flex;gap:12px;flex-wrap:wrap}
.tile{background:var(--surface);border-radius:8px;padding:10px 14px;min-width:150px}
.tile b{display:block;font-size:22px} .tile span{color:var(--ink2)}
table{border-collapse:collapse;width:100%}
th{color:var(--muted);font-weight:normal;text-align:left;padding:2px 6px;border-bottom:1px solid var(--axis)}
td{padding:3px 4px;border-bottom:1px solid var(--grid);vertical-align:middle}
td.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
td.lbl{max-width:170px} .key{color:var(--muted);font-size:11px}
svg{display:block} .hot{color:var(--crit);font-weight:600}
#tip{position:fixed;pointer-events:none;background:var(--surface);color:var(--ink);border:1px solid var(--axis);border-radius:6px;padding:4px 8px;font-size:12px;display:none;z-index:9}
.legend{display:flex;gap:16px;color:var(--ink2);margin:6px 0 0;flex-wrap:wrap}
.sw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px}
</style></head><body><div class="wrap">
<h1>全 App 主執行緒總覽</h1>
<p class="sub">電腦上 debug 模式逐格量到的主執行緒時間，看的是問題落在哪個操作、哪一段，不是手機上的毫秒數。每格已扣掉測試的資料庫時間（手機上不在主執行緒）。4.2ms 是電腦上的上限（手機 8.3ms 照 2 倍換算，ADR 0029、0036）；只算畫面在動的格子，畫面靜止時的尖峰（預留停頓）不算。</p>
<div class="tiles" id="tiles"></div>
<h2>動畫中超過 4.2ms 的格數最多的 20 步（<i class="sw" style="background:var(--bar)"></i>淺色＋<i class="sw" style="background:var(--dark)"></i>深色）</h2>
<div class="card"><div id="top"></div></div>
<h2>每一步逐格</h2>
<div class="legend"><span><i class="sw" style="background:var(--ok)"></i>4.2ms 以內</span><span><i class="sw" style="background:var(--crit)"></i>動畫中超過 4.2ms</span><span><i class="sw" style="background:var(--still)"></i>靜止時超過 4.2ms（不算）</span><span><i class="sw" style="background:var(--move)"></i>畫面在動（換頁、換場、骨架、捲動、動畫）</span><span>長條頂到 32ms 截掉，頂端加粗表示更高</span></div>
<div id="areas"></div>
</div><div id="tip"></div>
<script>
// 資料編成 PNG（頁面有大小上限），讀回來再畫。
const img = new Image();
img.onload = () => {
  const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
  const g = c.getContext('2d'); g.drawImage(img, 0, 0);
  const px = g.getImageData(0, 0, c.width, c.height).data;
  const bytes = new Uint8Array(px.length / 4 * 3);
  for (let i = 0, j = 0; i < px.length; i += 4) { bytes[j++] = px[i]; bytes[j++] = px[i + 1]; bytes[j++] = px[i + 2]; }
  const len = (bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]) >>> 0;
  init(JSON.parse(new TextDecoder().decode(bytes.subarray(6, 6 + len))));
};
img.onerror = () => console.error('讀不到量測資料');
img.src = /*DATA_PNG*/;
function init(DATA){
const AREAS = /*AREAS*/;
const STILL = new Set(['靜止','紙','骨架停住']);
const LIMIT = 4.2;
const tip = document.getElementById('tip');
function showTip(e, html){tip.innerHTML=html;tip.style.display='block';tip.style.left=(e.clientX+12)+'px';tip.style.top=(e.clientY+12)+'px';}
function hideTip(){tip.style.display='none';}
const css = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
// 只看畫面在動的格子：over 是動畫中超過 4.2ms 的格數，peak 是動畫中最忙的一格。
function stats(m){ if(!m) return null; const c=m.costs; let peak=0,at=-1,over=0;
  // 第 0 格是點下去後的第一格，可以重（ADR 0036 第 1 條），不算。
  c.forEach((v,i)=>{ if(i===0||STILL.has(m.phases[i])) return; if(v>LIMIT) over++; if(v>peak){peak=v;at=i;} });
  return {peak, at, over, n:c.length, phase:at<0?null:m.phases[at]}; }
DATA.forEach(r=>{for(const k of ['light','dark']) if(r[k]) r[k].phases=r[k].phases.flatMap(([p,n])=>Array(n).fill(p));
  r.ls=stats(r.light); r.ds=stats(r.dark); r.area=r.page.replace(/-(\d+|錄影中)$/,'');
  r.over=(r.ls?r.ls.over:0)+(r.ds?r.ds.over:0);});
const fmt = v => v>=100? v.toFixed(0) : v.toFixed(1);

// 摘要
const all = DATA.filter(r=>r.ls||r.ds);
const hot = all.filter(r=>r.over>0).length;
const worst = all.slice().sort((a,b)=>b.over-a.over)[0];
document.getElementById('tiles').innerHTML =
  `<div class="tile"><b>${all.length}</b><span>個操作</span></div>`+
  `<div class="tile"><b>${hot}</b><span>個動畫中有格子超過 4.2ms</span></div>`+
  (worst&&worst.over?`<div class="tile"><b>${worst.over} 格</b><span>最多：${worst.label}</span></div>`:'');

// 動畫中超過 4.2ms 格數最多的 20 步：橫條，淺色、深色疊在一起
(function(){
  const rows = all.filter(r=>r.over>0).sort((a,b)=>b.over-a.over).slice(0,20);
  if(!rows.length){document.getElementById('top').innerHTML='<span class="key">沒有任何一步在動畫中超過 4.2ms。</span>';return;}
  const W=690,L=260,R=90,H=22,top=18, h=top+rows.length*H+6;
  const max=Math.max(...rows.map(r=>r.over),4);
  const x=v=>L+(W-L-R)*v/max;
  let s=`<svg width="${W}" height="${h}" role="img" aria-label="動畫中超過 4.2ms 格數最多的步驟">`;
  const step=Math.max(1,Math.ceil(max/5));
  for(let t=0;t<=max;t+=step){const xx=x(t);
    s+=`<line x1="${xx}" x2="${xx}" y1="${top-4}" y2="${h-4}" stroke="${css('--grid')}" stroke-width="1"/>`+
       `<text x="${xx}" y="10" font-size="10" fill="${css('--muted')}" text-anchor="middle">${t} 格</text>`;}
  rows.forEach((r,i)=>{const y=top+i*H, lo=r.ls?r.ls.over:0, dk=r.ds?r.ds.over:0;
    s+=`<text x="${L-8}" y="${y+14}" font-size="12" fill="${css('--ink')}" text-anchor="end">${AREAS[r.area]||r.area}｜${r.label.slice(0,22)}</text>`+
       `<rect x="${L}" y="${y+4}" width="${Math.max(lo?2:0,x(lo)-L)}" height="12" rx="2" fill="${css('--bar')}"/>`+
       `<rect x="${x(lo)+(lo?1:0)}" y="${y+4}" width="${Math.max(dk?2:0,x(dk)-L)}" height="12" rx="2" fill="${css('--dark')}"/>`+
       `<text x="${x(r.over)+8}" y="${y+14}" font-size="12" fill="${css('--ink2')}">淺 ${lo}・深 ${dk}</text>`;});
  document.getElementById('top').innerHTML=s+'</svg>';
})();

// 每一步逐格
function strip(m, row, mode){
  if(!m) return '<span class="key">沒有錄到</span>';
  const c=m.costs, bw=Math.max(0.5,Math.min(2.5,140/c.length)), W=Math.ceil(c.length*bw), H=34, cap=32;
  const y=v=>H-2-(H-6)*Math.min(v,cap)/cap;
  let s=`<svg width="${W}" height="${H}" data-row="${row}" data-mode="${mode}" style="cursor:crosshair">`;
  c.forEach((v,i)=>{ if(!STILL.has(m.phases[i])) s+=`<rect x="${i*bw}" y="0" width="${bw}" height="${H}" fill="${css('--move')}"/>`; });
  s+=`<line x1="0" x2="${W}" y1="${y(LIMIT)}" y2="${y(LIMIT)}" stroke="${css('--crit')}" stroke-width="0.6" stroke-dasharray="2 2"/>`;
  c.forEach((v,i)=>{ const yy=y(v), still=STILL.has(m.phases[i]), col=v<=LIMIT?css('--ok'):still?css('--still'):css('--crit');
    s+=`<rect x="${i*bw+0.25}" y="${yy}" width="${Math.max(0.5,bw-0.5)}" height="${H-2-yy}" fill="${col}"/>`;
    if(v>cap) s+=`<rect x="${i*bw}" y="0" width="${bw}" height="3" fill="${col}"/>`; });
  s+=`<line x1="0" x2="${W}" y1="${H-1.5}" y2="${H-1.5}" stroke="${css('--axis')}"/></svg>`;
  return s;
}
const byArea = {};
DATA.forEach((r,i)=>{(byArea[r.area]=byArea[r.area]||[]).push(i);});
let html='';
for(const [area, idx] of Object.entries(byArea)){
  const rows=idx.map(i=>DATA[i]);
  const n=rows.filter(r=>r.over>0).length;
  html+=`<h2>${AREAS[area]||area}　<span class="key">${rows.length} 個操作，${n} 個動畫中有格子超過 4.2ms</span></h2><div class="card"><table>`+
    `<tr><th>操作</th><th>淺色逐格</th><th class="num">動畫中超過 4.2ms</th><th class="num">動畫中最忙</th><th>深色逐格</th><th class="num">動畫中超過 4.2ms</th><th class="num">動畫中最忙</th></tr>`;
  for(const i of idx){const r=DATA[i];
    const cell=(s)=> s?`<td class="num ${s.over?'hot':''}">${s.over} 格</td><td class="num">${s.at<0?'—':fmt(s.peak)+' ms'}</td>`:'<td></td><td></td>';
    html+=`<tr><td class="lbl">${r.label}<br><span class="key">${r.key}（${r.page} 頁）</span></td><td>${strip(r.light,i,'light')}</td>${cell(r.ls)}<td>${strip(r.dark,i,'dark')}</td>${cell(r.ds)}</tr>`;}
  html+='</table></div>';
}
document.getElementById('areas').innerHTML=html;
document.querySelectorAll('svg[data-row]').forEach(svg=>{
  svg.addEventListener('mousemove',e=>{const r=DATA[+svg.dataset.row], m=r[svg.dataset.mode];
    const bw=svg.width.baseVal.value/m.costs.length, i=Math.min(m.costs.length-1,Math.max(0,Math.floor((e.offsetX)/bw)));
    showTip(e,`${r.label}（${svg.dataset.mode==='light'?'淺色':'深色'}）<br>第 ${i} 格・${m.phases[i]}<br><b>${fmt(m.costs[i])} ms</b>`);});
  svg.addEventListener('mouseleave',hideTip);
});
}
</script></body></html>
'''


def main():
    with open(os.path.join(PAGES, 'overview.json'), encoding='utf-8') as f:
        data = json.load(f)
    # 頁面有大小上限：段落名稱改成「名稱、連續幾格」，頁面上再展開。
    for row in data:
        for mode in ('light', 'dark'):
            m = row.get(mode)
            if not m:
                continue
            # 每格扣掉測試的資料庫時間（手機上不在主執行緒，`db_clock.dart`）與閱讀器
            # 排版切片的一半（照時間切、手機上一樣長，`slice_clock.dart`，ADR 0036）。
            db = m.pop('db', None) or []
            sl = m.pop('slice', None) or []
            at = lambda xs, i: xs[i] if i < len(xs) else 0  # noqa: E731
            m['costs'] = [round(c - at(db, i) - at(sl, i) / 2, 1) for i, c in enumerate(m['costs'])]
            runs = []
            for p in m['phases']:
                if runs and runs[-1][0] == p:
                    runs[-1][1] += 1
                else:
                    runs.append([p, 1])
            m['phases'] = runs
    raw = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    payload = len(raw).to_bytes(4, 'big') + b'\0\0' + raw
    side = math.ceil(math.sqrt(math.ceil(len(payload) / 3)))
    payload += b'\0' * (side * side * 3 - len(payload))
    data_png = os.path.join(PAGES, 'overview-data.png')
    Image.frombytes('RGB', (side, side), payload).convert('RGBA').save(data_png, optimize=True)
    html = TEMPLATE.replace('/*DATA_PNG*/', json.dumps(data_png.replace('\\', '/')))
    html = html.replace('/*AREAS*/', json.dumps(AREA_NAMES, ensure_ascii=False))
    out = os.path.join(PAGES, 'overview.html')
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(html)
    print(out, len(html), 'chars', len(data), 'steps')


if __name__ == '__main__':
    main()
