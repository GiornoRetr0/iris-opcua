#!/usr/bin/env node
/**
 * Drive the running app in a real browser, for the DESIGN-QA.md pass.
 *
 * DESIGN-QA.md insists its assertions be checked against the running app rather
 * than the source, because that is exactly the gap that let a finished sparkline
 * ship invisible. This is the harness for doing that: it seeds a working config,
 * navigates, optionally runs a snippet in the page, and then either prints what
 * the snippet returned or writes a screenshot.
 *
 * Deliberately dependency-free beyond `ws`, which Angular already brings in —
 * adding Playwright to a project that doesn't otherwise need it is a bigger
 * commitment than this is worth.
 *
 * Setup (once per session):
 *   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
 *     --headless=new --remote-debugging-port=9222 --user-data-dir=/tmp/cdp-profile \
 *     --no-first-run --disable-gpu --disable-web-security --window-size=1600,1100 about:blank &
 *
 * `--disable-web-security` is needed because ng serve on :4200 calls the IRIS API
 * on :52783. Local verification only — never a browsing profile you use.
 *
 * Usage:
 *   node tools/qa-drive.mjs <url> [--shot out.png] [--eval snippet.mjs] [--servers N]
 *
 * Examples:
 *   node tools/qa-drive.mjs http://localhost:4200/pipelines --shot /tmp/pipelines.png
 *   node tools/qa-drive.mjs http://localhost:4200/explorer --servers 0 --shot /tmp/empty.png
 *   node tools/qa-drive.mjs http://localhost:4200/explorer --eval /tmp/check.mjs
 *
 * The --eval snippet runs as an async function body in the page and may `return`
 * a string or a JSON-serialisable value, which is printed.
 */
import { WebSocket } from 'ws';
import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const url = args.find((a) => a.startsWith('http'));
const flag = (name) => {
  const i = args.indexOf(name);
  return i === -1 ? null : args[i + 1];
};
if (!url) {
  console.error('usage: node tools/qa-drive.mjs <url> [--shot out.png] [--eval snippet.mjs] [--servers N]');
  process.exit(1);
}
const shot = flag('--shot');
const evalFile = flag('--eval');
const serverCount = flag('--servers') == null ? 1 : Number(flag('--servers'));

const targets = await (await fetch('http://localhost:9222/json/list')).json().catch(() => {
  console.error('No browser on :9222 — see the setup command in this file’s header.');
  process.exit(1);
});
const target = targets.find((t) => t.type === 'page');
if (!target) { console.error('no page target'); process.exit(1); }

const ws = new WebSocket(target.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
const send = (method, params = {}) =>
  new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
ws.on('message', (d) => {
  const m = JSON.parse(d);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
await new Promise((r) => ws.on('open', r));
await send('Page.enable');
await send('Runtime.enable');

async function evalJs(expression) {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (r.result?.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails, null, 2));
  return r.result?.result?.value;
}

/** The compose environment's servers, so --servers 0..3 covers the F24 check. */
const BASE = {
  id: 's1', name: 'plc', url: 'opc.tcp://plc:4840', securityMode: 1,
  username: '', password: '', certPath: '', keyPath: '', trustDir: '',
  crlDir: '', clientURI: '', rootNodeId: '85', rootNodeNs: 0,
};
const servers = [
  BASE,
  { ...BASE, id: 's2', name: 'plc2', url: 'opc.tcp://plc2:4840' },
  { ...BASE, id: 's3', name: 'certified', url: 'opc.tcp://certified-server:4840', securityMode: 3 },
].slice(0, serverCount);

const config = {
  apiBaseUrl: 'http://localhost:52783/csp/opcua/api',
  apiUsername: 'SuperUser', apiPassword: 'SYS', autoRefreshInterval: 5,
  servers,
  serverUrl: servers[0]?.url || '', securityMode: servers[0]?.securityMode || 1,
  username: '', password: '', certPath: '', keyPath: '', trustDir: '',
  crlDir: '', clientURI: '', rootNodeId: '85', rootNodeNs: 0,
};

// Land on the target's own origin first so localStorage is writable — it is
// per-origin, so seeding on :4200 does nothing for a build served from :4300.
await send('Page.navigate', { url: new URL(url).origin + '/' });
await new Promise((r) => setTimeout(r, 2200));
await evalJs(`localStorage.setItem('opcua-console::config', ${JSON.stringify(JSON.stringify(config))})`);
await send('Page.navigate', { url });
await new Promise((r) => setTimeout(r, 4000));

if (evalFile) {
  const out = await evalJs(`(async () => { ${readFileSync(evalFile, 'utf8')} })()`);
  console.log(typeof out === 'string' ? out : JSON.stringify(out, null, 2));
}
if (shot) {
  const png = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
  writeFileSync(shot, Buffer.from(png.result.data, 'base64'));
  console.log('wrote ' + shot);
}
ws.close();
