// 夜讀網站原型：捲動時換天色、風格切換、手機的下載鈕。
// 背景固定不位移（site.css 的 .backdrop），這裡只算現在是黃昏還是夜裡。

const root = document.documentElement;
const dock = document.querySelector('.dock');
const hero = document.querySelector('.hero');
const darkScheme = matchMedia('(prefers-color-scheme: dark)');

function isDark() {
  if (root.dataset.theme) return root.dataset.theme === 'dark';
  return darkScheme.matches;
}

// 淺色：前段黃昏、後段夜裡，天色只在捲到 38%–62% 這段換過去，中間調不會停留
// 太久；字色在一半的地方切換。深色：一開始就是夜，捲到底再暗成接近純黑。
function frame() {
  const max = root.scrollHeight - innerHeight;
  const p = Math.min(1, Math.max(0, scrollY / Math.max(1, max)));
  const dark = isDark();
  const t = Math.min(1, Math.max(0, (p - 0.38) / 0.24));
  const night = dark ? 1 : t * t * (3 - 2 * t);
  root.style.setProperty('--n', night.toFixed(4));
  root.style.setProperty('--deep', dark ? p.toFixed(4) : '0');
  root.dataset.ink = night >= 0.5 ? 'night' : 'day';
  dock?.classList.toggle('show', scrollY > hero.offsetHeight * 0.8);
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
