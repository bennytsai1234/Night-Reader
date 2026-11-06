// 夜讀網站原型，A、B 兩版共用：捲動換天色、星星、導覽膠囊、版本與大小、風格切換、「還有」小標籤。

const root = document.documentElement;
const darkScheme = matchMedia('(prefers-color-scheme: dark)');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const isDark = () => (root.dataset.theme ? root.dataset.theme === 'dark' : darkScheme.matches);

// ---------- 天色 ----------
// 淺色：最濃的黃昏開始，捲到 5%–85% 這段慢慢入夜；深色：一開始就是夜，捲到底再暗一點。
const nav = document.querySelector('.nav');
const hero = document.querySelector('.hero');
function frame() {
  const max = root.scrollHeight - innerHeight;
  const p = Math.min(1, Math.max(0, scrollY / Math.max(1, max)));
  const dark = isDark();
  const t = Math.min(1, Math.max(0, (p - 0.05) / 0.8));
  root.style.setProperty('--n', (dark ? 1 : t * t * (3 - 2 * t)).toFixed(4));
  root.style.setProperty('--deep', dark ? p.toFixed(4) : (p * 0.4).toFixed(4));
  nav?.classList.toggle('min', scrollY > hero.offsetHeight * 0.6);
}
let pending = false;
addEventListener('scroll', () => {
  if (pending) return;
  pending = true;
  requestAnimationFrame(() => { pending = false; frame(); });
}, { passive: true });
addEventListener('resize', frame);
darkScheme.addEventListener('change', frame);
frame();

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

// ---------- 導覽膠囊：目前所在的段落有一塊滑動的底色 ----------
(function navPill() {
  const links = [...document.querySelectorAll('.nav-links a')];
  const pill = document.querySelector('.nav-pill');
  if (!links.length || !pill) return;
  const targets = links.map((a) => document.querySelector(a.getAttribute('href')));
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
    const text = `Android · 版本 ${String(j.tag_name).replace(/^v/, '')}` + (apk ? ` · ${(apk.size / 1048576).toFixed(0)} MB` : '');
    metas.forEach((m) => { m.textContent = text; });
  } catch (_) {
    metas.forEach((m) => { m.textContent = 'Android 7.0 以上 · arm64'; });
  }
})();

// ---------- 風格：點了才換，同一頁正文換成那種風格 ----------
function showStyle(name) {
  document.querySelectorAll('.style-stack > picture').forEach((p) => p.classList.toggle('on', p.dataset.style === name));
  document.querySelectorAll('.styles button').forEach((b) => {
    const on = b.dataset.style === name;
    b.classList.toggle('on', on);
    b.setAttribute('aria-pressed', on);
  });
}
document.querySelectorAll('.styles button').forEach((b) => b.addEventListener('click', () => showStyle(b.dataset.style)));
showStyle('kraft');

// ---------- 進場：捲進畫面的段落加上 .in（版型自己決定怎麼動） ----------
(function reveal() {
  const items = [...document.querySelectorAll('.feature')];
  if (!items.length) return;
  if (reduced.matches || !('IntersectionObserver' in window)) { items.forEach((e) => e.classList.add('in')); return; }
  const io = new IntersectionObserver((entries) => {
    entries.forEach((en) => { if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); } });
  }, { rootMargin: '0px 0px -12% 0px', threshold: 0.15 });
  items.forEach((e) => io.observe(e));
})();

// ---------- 「還有」：點小標籤才看說明 ----------
(function more() {
  const chips = [...document.querySelectorAll('.more .chips button')];
  const say = document.querySelector('.more .say');
  if (!chips.length || !say) return;
  chips.forEach((b) => b.addEventListener('click', () => {
    chips.forEach((c) => { c.classList.toggle('on', c === b); c.setAttribute('aria-pressed', c === b); });
    say.style.opacity = 0;
    setTimeout(() => { say.textContent = b.dataset.say; say.style.opacity = 1; }, reduced.matches ? 0 : 160);
  }));
})();
