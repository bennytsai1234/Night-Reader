"""把 pages/overview.json 做成總覽頁 pages/overview.html。

    python overview.py

每一步一列：淺色、深色各一條逐格的主執行緒長條（超過 8ms 的格子標紅，
長條頂到 32ms 截掉、頂端標記），旁邊是最忙的一格與超過 8ms 的格數。最上面
是全部步驟裡最忙的 20 步。
"""
import json
import math
import os

from PIL import Image

PAGES = r'D:\nr-survey\pages'

AREA_NAMES = {
    'tabs': '換分頁', 'launch': '開 App 進場', 'shelf': '書架', 'book': '書籍詳情與目錄',
    'reader': '閱讀器', 'search': '搜尋', 'explore': '發現', 'download': '下載',
    'sources': '書源管理', 'mine': '「我的」：外觀與主題', 'mine2': '「我的」：其他各頁',
}

TEMPLATE = r'''<!doctype html>
<html lang="zh-Hant"><head><meta charset="utf-8">
<title>全 App 主執行緒總覽</title>
<style>
:root{--surface:var(--card,#fcfcfb);--ink:var(--foreground,#0b0b0b);--ink2:var(--muted-foreground,#52514e);--muted:var(--muted-foreground,#898781);
--grid:var(--border,#e1e0d9);--axis:var(--border,#c3c2b7);--ok:var(--chart-1,#86b6ef);--bar:var(--chart-1,#2a78d6);--crit:var(--destructive,#d03b3b);
--move:color-mix(in srgb,var(--chart-1,#2a78d6) 14%,transparent);}
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
<p class="sub">電腦上 debug 模式逐格量到的主執行緒時間，看的是尖峰落在哪個操作、哪一段，不是手機上的毫秒數。每格 16ms，8ms 是預算線。</p>
<div class="tiles" id="tiles"></div>
<h2>最忙的 20 步（淺色）</h2>
<div class="card"><div id="top"></div></div>
<h2>每一步逐格</h2>
<div class="legend"><span><i class="sw" style="background:var(--ok)"></i>8ms 以內</span><span><i class="sw" style="background:var(--crit)"></i>超過 8ms</span><span><i class="sw" style="background:var(--move)"></i>畫面在動（換頁、換場、捲動、動畫）</span><span>長條頂到 32ms 截掉，頂端加粗表示更高</span></div>
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
const STILL = new Set(['靜止','紙']);
const tip = document.getElementById('tip');
function showTip(e, html){tip.innerHTML=html;tip.style.display='block';tip.style.left=(e.clientX+12)+'px';tip.style.top=(e.clientY+12)+'px';}
function hideTip(){tip.style.display='none';}
const css = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
function stats(m){ if(!m) return null; const c=m.costs; let peak=0,at=0; c.forEach((v,i)=>{if(v>peak){peak=v;at=i;}});
  return {peak, at, over:c.filter(v=>v>8).length, n:c.length, phase:m.phases[at]}; }
DATA.forEach(r=>{for(const k of ['light','dark']) if(r[k]) r[k].phases=r[k].phases.flatMap(([p,n])=>Array(n).fill(p));
  r.ls=stats(r.light); r.ds=stats(r.dark); r.area=r.page.replace(/-(\d+|錄影中)$/,'');});
const fmt = v => v>=100? v.toFixed(0) : v.toFixed(1);

// 摘要
const all = DATA.filter(r=>r.ls);
const hot = all.filter(r=>r.ls.over>0).length;
const worst = all.slice().sort((a,b)=>b.ls.peak-a.ls.peak)[0];
document.getElementById('tiles').innerHTML =
  `<div class="tile"><b>${all.length}</b><span>個操作</span></div>`+
  `<div class="tile"><b>${hot}</b><span>個有格子超過 8ms</span></div>`+
  (worst?`<div class="tile"><b>${fmt(worst.ls.peak)} ms</b><span>最忙：${worst.label}</span></div>`:'');

// 最忙的 20 步：橫條，對數刻度（尖峰從幾 ms 到幾秒）
(function(){
  const rows = all.slice().sort((a,b)=>b.ls.peak-a.ls.peak).slice(0,20);
  const W=690,L=260,R=64,H=22,top=18, h=top+rows.length*H+6;
  const max=Math.max(...rows.map(r=>r.ls.peak),16);
  const x=v=>L+(W-L-R)*Math.log10(Math.max(v,1))/Math.log10(max);
  let s=`<svg width="${W}" height="${h}" role="img" aria-label="最忙的 20 步">`;
  for(const t of [1,8,16,100,1000,10000]) if(t<=max){const xx=x(t);
    s+=`<line x1="${xx}" x2="${xx}" y1="${top-4}" y2="${h-4}" stroke="${t===8?css('--crit'):css('--grid')}" stroke-width="1" ${t===8?'stroke-dasharray="3 3"':''}/>`+
       `<text x="${xx}" y="10" font-size="10" fill="${css('--muted')}" text-anchor="middle">${t>=1000?t/1000+'s':t+'ms'}</text>`;}
  rows.forEach((r,i)=>{const y=top+i*H;
    s+=`<text x="${L-8}" y="${y+14}" font-size="12" fill="${css('--ink')}" text-anchor="end">${AREAS[r.area]||r.area}｜${r.label.slice(0,22)}</text>`+
       `<rect x="${L}" y="${y+4}" width="${Math.max(2,x(r.ls.peak)-L)}" height="12" rx="3" fill="${css('--bar')}"/>`+
       `<text x="${x(r.ls.peak)+6}" y="${y+14}" font-size="12" fill="${css('--ink2')}">${fmt(r.ls.peak)} ms</text>`;});
  document.getElementById('top').innerHTML=s+'</svg>';
})();

// 每一步逐格
function strip(m, row, mode){
  if(!m) return '<span class="key">沒有錄到</span>';
  const c=m.costs, bw=Math.max(0.5,Math.min(2.5,140/c.length)), W=Math.ceil(c.length*bw), H=34, cap=32;
  const y=v=>H-2-(H-6)*Math.min(v,cap)/cap;
  let s=`<svg width="${W}" height="${H}" data-row="${row}" data-mode="${mode}" style="cursor:crosshair">`;
  c.forEach((v,i)=>{ if(!STILL.has(m.phases[i])) s+=`<rect x="${i*bw}" y="0" width="${bw}" height="${H}" fill="${css('--move')}"/>`; });
  s+=`<line x1="0" x2="${W}" y1="${y(8)}" y2="${y(8)}" stroke="${css('--crit')}" stroke-width="0.6" stroke-dasharray="2 2"/>`;
  c.forEach((v,i)=>{ const yy=y(v); s+=`<rect x="${i*bw+0.25}" y="${yy}" width="${Math.max(0.5,bw-0.5)}" height="${H-2-yy}" fill="${v>8?css('--crit'):css('--ok')}"/>`;
    if(v>cap) s+=`<rect x="${i*bw}" y="0" width="${bw}" height="3" fill="${css('--crit')}"/>`; });
  s+=`<line x1="0" x2="${W}" y1="${H-1.5}" y2="${H-1.5}" stroke="${css('--axis')}"/></svg>`;
  return s;
}
const byArea = {};
DATA.forEach((r,i)=>{(byArea[r.area]=byArea[r.area]||[]).push(i);});
let html='';
for(const [area, idx] of Object.entries(byArea)){
  const rows=idx.map(i=>DATA[i]);
  const n=rows.filter(r=>r.ls&&r.ls.over>0).length;
  html+=`<h2>${AREAS[area]||area}　<span class="key">${rows.length} 個操作，${n} 個有格子超過 8ms</span></h2><div class="card"><table>`+
    `<tr><th>操作</th><th>淺色逐格</th><th class="num">最忙</th><th class="num">超過 8ms</th><th>深色逐格</th><th class="num">最忙</th><th class="num">超過 8ms</th></tr>`;
  for(const i of idx){const r=DATA[i];
    const cell=(s)=> s?`<td class="num ${s.peak>8?'hot':''}">${fmt(s.peak)} ms</td><td class="num">${s.over} 格</td>`:'<td></td><td></td>';
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
