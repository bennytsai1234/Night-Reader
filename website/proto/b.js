// 原型 B：手機黏在畫面中央的捲動敘事。捲動進度決定現在是第幾段，手機隨進度微微轉動。

(function stage() {
  const stage = document.querySelector('.stage');
  if (!stage) return;
  const steps = +getComputedStyle(stage).getPropertyValue('--steps') || 5;
  const shots = [...stage.querySelectorAll('.step-shot')];
  const copies = [...stage.querySelectorAll('.step-copy')];
  const dots = [...stage.querySelectorAll('.rail button')];
  let cur = -1;

  function set(i) {
    if (i === cur) return;
    cur = i;
    shots.forEach((e, k) => e.classList.toggle('on', k === i));
    copies.forEach((e, k) => e.classList.toggle('on', k === i));
    dots.forEach((e, k) => e.classList.toggle('on', k === i));
  }
  function update() {
    const range = stage.offsetHeight - innerHeight;
    const p = Math.min(1, Math.max(0, (scrollY - stage.offsetTop) / Math.max(1, range)));
    stage.style.setProperty('--sp', p.toFixed(4));
    set(Math.min(steps - 1, Math.floor(p * steps)));
  }
  let pending = false;
  addEventListener('scroll', () => {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => { pending = false; update(); });
  }, { passive: true });
  addEventListener('resize', update);
  update();

  dots.forEach((b, i) => b.addEventListener('click', () => {
    const range = stage.offsetHeight - innerHeight;
    scrollTo({ top: stage.offsetTop + ((i + 0.5) / steps) * range });
  }));
})();
