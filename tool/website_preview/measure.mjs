// 用法：node measure.mjs <website/>   量 A、B 兩版：傳輸量、請求數、頁面長度、全頁字數、捲動時每幀 JS 時間
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const root = process.argv[2];
const httpPort = 8792, cdpPort = 9335;
const server = spawn('python', ['-I', '-m', 'http.server', String(httpPort), '--bind', '127.0.0.1', '--directory', root], { stdio: 'ignore' });
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [`--remote-debugging-port=${cdpPort}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), 'nr-meas-'))}`, '--headless=new', '--hide-scrollbars', '--no-first-run', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function wsUrl() { for (let i = 0; i < 60; i++) { try { const l = await (await fetch(`http://127.0.0.1:${cdpPort}/json`)).json(); const p = l.find((t) => t.type === 'page'); if (p) return p.webSocketDebuggerUrl; } catch (_) {} await sleep(250); } throw new Error('no chrome'); }
const ws = new WebSocket(await wsUrl());
await new Promise((r) => (ws.onopen = r));
let id = 0; const pend = new Map();
ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && pend.has(d.id)) { pend.get(d.id)(d); pend.delete(d.id); } };
const send = (method, params = {}) => new Promise((res, rej) => { const i = ++id; pend.set(i, (d) => (d.error ? rej(new Error(d.error.message)) : res(d.result))); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result.value;

await send('Page.enable');
await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }] });
for (const [sz, w, h, dpr, mob] of [['桌面 1440×900', 1440, 900, 1, false], ['手機 390×844', 390, 844, 2, true]]) {
  await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: dpr, mobile: mob });
  for (const page of ['a', 'b']) {
    await send('Page.navigate', { url: `http://127.0.0.1:${httpPort}/proto/${page}.html` });
    await sleep(2500);
    const r = await ev(`(async () => {
      const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
      const max = document.documentElement.scrollHeight - innerHeight;
      // 慢慢捲到底：每步 60px、等一幀，記每一步 JS 到下一幀的時間
      const dts = [];
      let last = performance.now();
      for (let y = 0; y <= max; y += 60) { scrollTo(0, y); await new Promise((r) => requestAnimationFrame(r)); const t = performance.now(); dts.push(t - last); last = t; }
      await sleep(800);
      dts.sort((a, b) => a - b);
      const res = performance.getEntriesByType('resource').filter((e) => !e.name.includes('api.github.com'));
      const bytes = res.reduce((s, e) => s + (e.encodedBodySize || 0), 0) + performance.getEntriesByType('navigation')[0].encodedBodySize;
      const copy = [...document.querySelectorAll('.hero-copy, .feature .text, .step-copy, .more, .source, .download')].map((e) => e.textContent.replace(/\\s+/g, '')).join('');
      return { kb: Math.round(bytes / 1024), reqs: res.length + 1, screens: +(document.documentElement.scrollHeight / innerHeight).toFixed(1), chars: copy.length, p50: +dts[Math.floor(dts.length * 0.5)].toFixed(1), p95: +dts[Math.floor(dts.length * 0.95)].toFixed(1), max: +dts[dts.length - 1].toFixed(1), steps: dts.length };
    })()`);
    console.log(sz, page.toUpperCase(), JSON.stringify(r));
  }
}
ws.close(); chrome.kill(); server.kill(); process.exit(0);
