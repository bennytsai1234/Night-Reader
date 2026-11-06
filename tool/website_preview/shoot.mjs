// 把網站（website/）照一般視窗大小捲到每一段拍下來，看版面有沒有壞、主控台有沒有錯。
//
//   node tool/website_preview/shoot.mjs <輸出資料夾> [desktop,mobile]
//
// 自己開一個 http 伺服器與無頭 Chrome；每一段存成 <尺寸>-<序號>-<名稱>.png，
// 主控台的錯誤印在最後。短片在拍之前停在封面（不等它播）。
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const [outDir, sizesArg = 'desktop,mobile'] = process.argv.slice(2);
if (!outDir) {
  console.error('用法：node tool/website_preview/shoot.mjs <輸出資料夾> [desktop,mobile]');
  process.exit(1);
}
mkdirSync(outDir, { recursive: true });
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../website');
const chromePath = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const httpPort = 8793, cdpPort = 9336;

const server = spawn('python', ['-I', '-m', 'http.server', String(httpPort), '--bind', '127.0.0.1', '--directory', root], { stdio: 'ignore' });
const chrome = spawn(chromePath, [`--remote-debugging-port=${cdpPort}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), 'nr-shoot-'))}`, '--headless=new', '--hide-scrollbars', '--no-first-run', 'about:blank'], { stdio: 'ignore' });
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
let id = 0;
const pending = new Map();
const errors = [];
ws.onmessage = (m) => {
  const d = JSON.parse(m.data);
  if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); }
  if (d.method === 'Runtime.exceptionThrown') errors.push(d.params.exceptionDetails.exception?.description ?? d.params.exceptionDetails.text);
  if (d.method === 'Log.entryAdded' && d.params.entry.level === 'error') errors.push(`${d.params.entry.text} ${d.params.entry.url ?? ''}`);
};
const send = (method, params = {}) => new Promise((res, rej) => { const i = ++id; pending.set(i, (d) => (d.error ? rej(new Error(method + ': ' + d.error.message)) : res(d.result))); ws.send(JSON.stringify({ id: i, method, params })); });
const evalJs = async (expr) => (await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })).result.value;

const sizes = { desktop: { width: 1440, height: 900, dpr: 1, mobile: false }, mobile: { width: 390, height: 844, dpr: 2, mobile: true } };
// 要拍的捲動位置：開頭、每一卷的卷名、每個功能、書源那段、下載。
const stops = `(() => {
  const y = (e, k = 0.18) => e.getBoundingClientRect().top + scrollY - innerHeight * k;
  const out = [['hero', 0]];
  document.querySelectorAll('.feature, .source-note').forEach((e, i) => out.push([(e.querySelector('h3')?.textContent ?? 'f' + i).slice(0, 8), y(e)]));
  out.push(['download', document.documentElement.scrollHeight - innerHeight]);
  return out;
})()`;

await send('Page.enable');
await send('Runtime.enable');
await send('Log.enable');
for (const sz of sizesArg.split(',')) {
  const S = sizes[sz];
  await send('Emulation.setDeviceMetricsOverride', { width: S.width, height: S.height, deviceScaleFactor: S.dpr, mobile: S.mobile });
  await send('Page.navigate', { url: `http://127.0.0.1:${httpPort}/index.html` });
  await sleep(2500);
  const list = await evalJs(stops);
  for (const [n, [name, y]] of list.entries()) {
    await evalJs(`document.documentElement.style.scrollBehavior='auto'; scrollTo(0, ${Math.round(y)}); document.querySelectorAll('video').forEach((v) => v.pause()); 0`);
    await sleep(1300);
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(join(outDir, `${sz}-${String(n).padStart(2, '0')}-${name}.png`), Buffer.from(shot.data, 'base64'));
  }
  console.log('完成', sz, list.length, '張');
}
console.log(errors.length ? `主控台錯誤：\n${errors.join('\n')}` : '主控台沒有錯誤');
ws.close(); chrome.kill(); server.kill();
process.exit(0);
