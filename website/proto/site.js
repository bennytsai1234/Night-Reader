// 夜讀網站原型共用：六種風格輪流換、捲到哪一段就換哪張圖、段落淡入。

const STYLES = ['plain', 'paper', 'tea', 'kraft', 'bamboo', 'bean'];
let styleIndex = 1;
let pausedUntil = 0;

function showStyle(i) {
  styleIndex = i;
  document.querySelectorAll('.style-stack').forEach((stack) => {
    stack.querySelectorAll(':scope > picture').forEach((p) => {
      p.classList.toggle('on', p.dataset.style === STYLES[i]);
    });
  });
  document.querySelectorAll('.chip[data-style]').forEach((c) => {
    c.classList.toggle('on', c.dataset.style === STYLES[i]);
  });
}

document.querySelectorAll('.chip[data-style]').forEach((chip) => {
  chip.addEventListener('click', () => {
    pausedUntil = Date.now() + 6000;
    showStyle(STYLES.indexOf(chip.dataset.style));
  });
});

let styleVisible = false;
const styleWatch = new IntersectionObserver((entries) => {
  styleVisible = entries.some((e) => e.isIntersecting) ||
    [...document.querySelectorAll('[data-style-zone]')].some((el) => {
      const r = el.getBoundingClientRect();
      return r.bottom > 0 && r.top < innerHeight;
    });
});
document.querySelectorAll('[data-style-zone]').forEach((el) => styleWatch.observe(el));

const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
if (!reduce) {
  setInterval(() => {
    if (!styleVisible || Date.now() < pausedUntil) return;
    showStyle((styleIndex + 1) % STYLES.length);
  }, 1800);
}
showStyle(styleIndex);

// 排法一：固定的手機，捲到哪一段就淡換成那一段的畫面。
const stage = document.querySelector('#stage');
if (stage) {
  const steps = document.querySelectorAll('.step[data-shot]');
  const pick = (shot) => {
    stage.querySelectorAll(':scope > [data-shot]').forEach((layer) => {
      layer.classList.toggle('on', layer.dataset.shot === shot);
    });
    steps.forEach((s) => s.classList.toggle('active', s.dataset.shot === shot));
  };
  const io = new IntersectionObserver((entries) => {
    entries.forEach((e) => { if (e.isIntersecting) pick(e.target.dataset.shot); });
  }, { rootMargin: '-45% 0px -45% 0px' });
  steps.forEach((s) => io.observe(s));
  pick(steps[0].dataset.shot);
}

// 段落捲進畫面時淡入（位置不動）。
const fades = document.querySelectorAll('.fade');
if (reduce) {
  fades.forEach((el) => el.classList.add('in'));
} else {
  const fio = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) { e.target.classList.add('in'); fio.unobserve(e.target); }
    });
  }, { rootMargin: '0px 0px -10% 0px' });
  fades.forEach((el) => fio.observe(el));
}
