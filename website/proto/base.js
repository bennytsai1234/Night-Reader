// 夜讀網站原型，A、B 兩版共用：捲動換天色、星星、導覽膠囊、版本與大小、風格切換、前後對照、短片、進場。

const root = document.documentElement;
const reduced = matchMedia('(prefers-reduced-motion: reduce)');

// ---------- 天色：最濃的黃昏開始，捲到 5%–85% 這段慢慢入夜，捲到底再暗一點 ----------
function sky() {
  const max = root.scrollHeight - innerHeight;
  const p = Math.min(1, Math.max(0, scrollY / Math.max(1, max)));
  const t = Math.min(1, Math.max(0, (p - 0.05) / 0.8));
  root.style.setProperty('--n', (t * t * (3 - 2 * t)).toFixed(4));
  root.style.setProperty('--deep', p.toFixed(4));
}
let pending = false;
addEventListener('scroll', () => {
  if (pending) return;
  pending = true;
  requestAnimationFrame(() => { pending = false; sky(); });
}, { passive: true });
addEventListener('resize', sky);
sky();

// ---------- 星星：固定的亂數種子，每次看到的星空一樣 ----------
(function stars() {
  const box = document.querySelector('.stars');
  if (!box) return;
  let s = 20261106;
  const rnd = () => { s |= 0; s = (s + 0x6d2b79f5) | 0; let t = Math.imul(s ^ (s >>> 15), 1 | s); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const frag = document.createDocumentFragment();
  for (let i = 0; i < 90; i++) {
    const e = document.createElement('i');
    const big = rnd() > 0.9;
    const size = big ? 2.4 : 1 + rnd() * 1.2;
    e.style.cssText = `left:${(rnd() * 100).toFixed(2)}%;top:${(Math.pow(rnd(), 1.4) * 100).toFixed(2)}%;width:${size}px;height:${size}px;--a:${(0.35 + rnd() * 0.65).toFixed(2)};--d:${(2.5 + rnd() * 4).toFixed(1)}s;--l:${(-rnd() * 6).toFixed(1)}s`;
    frag.appendChild(e);
  }
  box.appendChild(frag);
})();

// ---------- 導覽膠囊：捲到哪一卷，那一卷的卷名底下有一塊滑動的底色 ----------
(function navPill() {
  const links = [...document.querySelectorAll('.nav-links a')];
  const pill = document.querySelector('.nav-pill');
  if (!links.length || !pill) return;
  const targets = links.map((a) => document.querySelector(a.getAttribute('href')));
  const end = document.querySelector('#download');
  function place(a) {
    links.forEach((l) => l.classList.toggle('on', l === a));
    if (!a) { pill.style.opacity = 0; return; }
    pill.style.opacity = 1;
    pill.style.left = a.offsetLeft + 'px';
    pill.style.width = a.offsetWidth + 'px';
  }
  function update() {
    const y = innerHeight * 0.45;
    let cur = null;
    targets.forEach((el, i) => { if (el && el.getBoundingClientRect().top <= y) cur = links[i]; });
    // 捲到下載那段就不屬於任何一卷。
    if (end && end.getBoundingClientRect().top <= y) cur = null;
    place(cur);
  }
  addEventListener('scroll', () => requestAnimationFrame(update), { passive: true });
  addEventListener('resize', update);
  update();
})();

// ---------- 版本與大小：讀得到才顯示 ----------
(async function version() {
  const metas = document.querySelectorAll('.get .meta');
  if (!metas.length) return;
  try {
    const r = await fetch('https://api.github.com/repos/bennytsai1234/Night-Reader/releases/latest', { headers: { Accept: 'application/vnd.github+json' } });
    if (!r.ok) throw new Error(r.status);
    const j = await r.json();
    const apk = (j.assets || []).find((a) => /\.apk$/i.test(a.name));
    const text = `Android・${String(j.tag_name).replace(/^v/, '')}` + (apk ? `・${(apk.size / 1048576).toFixed(0)} MB` : '');
    metas.forEach((m) => { m.textContent = text; });
  } catch (_) {
    metas.forEach((m) => { m.textContent = 'Android 7.0 以上'; });
  }
})();

// ---------- 風格：白天晚上各選一個，切換白天晚上看那一個 ----------
(function styles() {
  const box = document.querySelector('.styles');
  const shots = [...document.querySelectorAll('.style-stack > [data-style]')];
  if (!box || !shots.length) return;
  // 白天牛皮紙、晚上素色：維護者自己讀書用的設定。
  const chosen = { light: 'kraft', dark: 'plain' };
  let mode = 'dark';
  box.querySelectorAll('.swatches button').forEach((b) => b.prepend(document.createElement('i')));
  function render() {
    box.dataset.show = mode;
    box.querySelectorAll('.daynight button').forEach((b) => b.classList.toggle('on', b.dataset.mode === mode));
    box.querySelectorAll('.swatches').forEach((row) => row.querySelectorAll('button').forEach((b) => {
      const on = b.dataset.style === chosen[row.dataset.mode];
      b.classList.toggle('on', on);
      b.setAttribute('aria-pressed', on);
    }));
    shots.forEach((s) => s.classList.toggle('on', s.dataset.mode === mode && s.dataset.style === chosen[mode]));
  }
  box.querySelectorAll('.daynight button').forEach((b) => b.addEventListener('click', () => { mode = b.dataset.mode; render(); }));
  box.querySelectorAll('.swatches').forEach((row) => row.querySelectorAll('button').forEach((b) => b.addEventListener('click', () => {
    chosen[row.dataset.mode] = b.dataset.style;
    render();
  })));
  render();
})();

// ---------- 前後對照：同一個 data-toggle 的按鈕與畫面一起換，先顯示第二張（之後） ----------
document.querySelectorAll('.seg[data-toggle]').forEach((seg) => {
  const stack = document.querySelector(`.stack[data-toggle="${seg.dataset.toggle}"]`);
  const buttons = [...seg.querySelectorAll('button')];
  function show(key) {
    buttons.forEach((b) => { const on = b.dataset.key === key; b.classList.toggle('on', on); b.setAttribute('aria-pressed', on); });
    stack?.querySelectorAll('[data-key]').forEach((p) => p.classList.toggle('on', p.dataset.key === key));
  }
  buttons.forEach((b) => b.addEventListener('click', () => show(b.dataset.key)));
  show(buttons[buttons.length - 1].dataset.key);
});

// ---------- 短片：捲進畫面才載入並播放，捲出去就停 ----------
(function clips() {
  const videos = [...document.querySelectorAll('video.clip')];
  if (!videos.length) return;
  const load = (v) => { if (!v.src && v.dataset.src) v.src = v.dataset.src; };
  if (reduced.matches || !('IntersectionObserver' in window)) { videos.forEach(load); return; }
  const io = new IntersectionObserver((entries) => entries.forEach((en) => {
    const v = en.target;
    if (en.isIntersecting) { load(v); v.play().catch(() => {}); } else { v.pause(); }
  }), { threshold: 0.35 });
  videos.forEach((v) => io.observe(v));
})();

// ---------- 進場：捲進畫面的段落加上 .in（版型自己決定怎麼動） ----------
(function reveal() {
  const items = [...document.querySelectorAll('.feature')];
  if (!items.length) return;
  // 整頁從頭到尾一左一右，跨卷也接著數。
  items.forEach((e, i) => e.classList.toggle('flip', i % 2 === 1));
  if (reduced.matches || !('IntersectionObserver' in window)) { items.forEach((e) => e.classList.add('in')); return; }
  const io = new IntersectionObserver((entries) => {
    entries.forEach((en) => { if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); } });
  }, { rootMargin: '0px 0px -12% 0px', threshold: 0.15 });
  items.forEach((e) => io.observe(e));
})();
