// 用法：node shoot.mjs <網站根目錄 website/> <輸出資料夾> [頁面 a,b] [情境 light,dark] [尺寸 desktop,mobile]
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [root, outDir, pagesArg = 'a,b', schemesArg = 'light,dark', sizesArg = 'desktop,mobile'] = process.argv.slice(2);
mkdirSync(outDir, { recursive: true });
const chromePath = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const httpPort = 8791, cdpPort = 9334;

const server = spawn('python', ['-I', '-m', 'http.server', String(httpPort), '--bind', '127.0.0.1', '--directory', root], { stdio: 'ignore' });
const profile = mkdtempSync(join(tmpdir(), 'nr-shoot-'));
const chrome = spawn(chromePath, [`--remote-debugging-port=${cdpPort}`, `--user-data-dir=${profile}`, '--headless=new', '--hide-scrollbars', '--no-first-run', '--disable-gpu-vsync', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function connect() {
  for (let i = 0; i < 60; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${cdpPort}/json`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page) return page.webSocketDebuggerUrl;
    } catch (_) {}
    await sleep(250);
  }
  throw new Error('chrome 沒起來');
}

const ws = new WebSocket(await connect());
await new Promise((r) => (ws.onopen = r));
let id = 0; const pending = new Map();
ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } };
const send = (method, params = {}) => new Promise((res, rej) => { const i = ++id; pending.set(i, (d) => (d.error ? rej(new Error(method + ': ' + d.error.message)) : res(d.result))); ws.send(JSON.stringify({ id: i, method, params })); });
const evalJs = async (expr) => (await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })).result.value;

const sizes = { desktop: { width: 1440, height: 900, dpr: 1, mobile: false }, mobile: { width: 390, height: 844, dpr: 2, mobile: true } };
// 每個頁面要拍哪些捲動位置：回傳 [名稱, scrollY]
const stops = {
  a: `(() => { const max = document.documentElement.scrollHeight - innerHeight; const f = document.querySelectorAll('.feature'); const y = (e) => e.getBoundingClientRect().top + scrollY - innerHeight * 0.18; return [['hero', 0], ['f1', y(f[0])], ['f2', y(f[1])], ['f3', y(f[2])], ['f4', y(f[3])], ['f5', y(f[4])], ['more', document.querySelector('.more').getBoundingClientRect().top + scrollY - innerHeight * 0.3], ['end', max]]; })()`,
  b: `(() => { const max = document.documentElement.scrollHeight - innerHeight; const s = document.querySelector('.stage'); const r = s.offsetHeight - innerHeight; const out = [['hero', 0]]; for (let i = 0; i < 5; i++) out.push(['s' + (i + 1), s.offsetTop + ((i + 0.5) / 5) * r]); out.push(['more', document.querySelector('.more').getBoundingClientRect().top + scrollY - innerHeight * 0.3]); out.push(['end', max]); return out; })()`,
};

await send('Page.enable');
for (const page of pagesArg.split(',')) {
  for (const scheme of schemesArg.split(',')) {
    for (const sz of sizesArg.split(',')) {
      const S = sizes[sz];
      await send('Emulation.setDeviceMetricsOverride', { width: S.width, height: S.height, deviceScaleFactor: S.dpr, mobile: S.mobile });
      await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: scheme }] });
      await send('Page.navigate', { url: `http://127.0.0.1:${httpPort}/proto/${page}.html` });
      await sleep(2500);
      const list = await evalJs(stops[page]);
      for (const [name, y] of list) {
        await evalJs(`document.documentElement.style.scrollBehavior='auto'; scrollTo(0, ${Math.round(y)}); 0`);
        await sleep(1300);
        const shot = await send('Page.captureScreenshot', { format: 'png' });
        writeFileSync(join(outDir, `${page}-${sz}-${scheme}-${name}.png`), Buffer.from(shot.data, 'base64'));
      }
      console.log('完成', page, scheme, sz, list.length);
    }
  }
}
ws.close(); chrome.kill(); server.kill();
process.exit(0);
