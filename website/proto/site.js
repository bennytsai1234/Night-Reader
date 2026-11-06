// 夜讀網站原型共用：捲動時讓夜空動、風格切換、手機的下載鈕。
// 背景是 Codex 生成的幾層圖（sky/）：夜空、黃昏、月亮、遠山、近山。

const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
const mode = document.body.dataset.sky;
const bar = document.querySelector('.bar');
const dock = document.querySelector('.dock');
const hero = document.querySelector('.hero');

function onScroll(frame) {
  let pending = false;
  addEventListener('scroll', () => {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => { pending = false; frame(); });
  }, { passive: true });
  addEventListener('resize', frame);
  frame();
}

// 甲：開頭一整片夜空，捲動時越遠的動得越慢，捲過開頭收進頁面底色。
if (mode === 'hero') {
  const copy = document.querySelector('.hero-copy');
  const rates = [['.sky-base', 0.5], ['.sky-moon', 0.42], ['.sky-far', 0.22], ['.sky-near', 0]]
    .map(([sel, k]) => [hero.querySelector(sel), k]);
  onScroll(() => {
    const h = hero.offsetHeight;
    const y = Math.min(scrollY, h);
    if (!reduce) {
      for (const [layer, k] of rates) layer.style.transform = `translate3d(0, ${(y * k).toFixed(1)}px, 0)`;
      copy.style.opacity = Math.max(0, 1 - y / (h * 0.55)).toFixed(3);
    }
    bar.classList.toggle('on-sky', scrollY < h - 60);
    dock?.classList.toggle('show', scrollY > h * 0.8);
  });
}

// 乙：整頁從黃昏捲到深夜。背景固定，--p 是捲動進度，CSS 照它換天色、升月亮。
if (mode === 'dusk') {
  const root = document.documentElement;
  onScroll(() => {
    const max = root.scrollHeight - innerHeight;
    const p = reduce ? 0.5 : Math.min(1, Math.max(0, scrollY / Math.max(1, max)));
    root.style.setProperty('--p', p.toFixed(4));
    dock?.classList.toggle('show', scrollY > hero.offsetHeight * 0.8);
  });
}

// 風格：點了才換（不自己輪播），同一頁正文換成那種風格。
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
