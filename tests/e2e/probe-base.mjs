// E2E test for the xeus-lean base image (Dockerfile.native).
// Opens a fresh notebook, picks the xlean kernel, runs #eval 1, asserts
// the cell prints "1". Dumps browser console + server logs on failure.
import { chromium } from 'playwright';

const BASE = process.argv[2] ?? 'http://127.0.0.1:18890';
const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1100, height: 700 } });
const page = await ctx.newPage();

const consoleLines = [];
page.on('console', (m) => consoleLines.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => consoleLines.push(`[pageerror] ${e.message}`));

// Register WS listener up-front, before any navigation.
//
// Jupyter websocket v1.kernel.websocket.jupyter.org binary frame:
//   u64 nbufs (LE)
//   u64 offsets[nbufs] (LE)
//   buf[0] = channel name (utf-8) — "shell"/"iopub"/"stdin"/"control"
//   buf[1] = header JSON
//   buf[2] = parent_header JSON
//   buf[3] = metadata JSON
//   buf[4] = content JSON
//   buf[5+] = extra binary buffers
function decodeJupyterV1(payload) {
  const u8 = typeof payload === 'string' ? new TextEncoder().encode(payload) : new Uint8Array(payload);
  const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
  if (u8.byteLength < 8) return null;
  const nbufs = Number(dv.getBigUint64(0, true));
  if (nbufs > 32 || u8.byteLength < 8 + 8 * nbufs) return null;
  const offs = [];
  for (let i = 0; i < nbufs; i++) offs.push(Number(dv.getBigUint64(8 + 8 * i, true)));
  offs.push(u8.byteLength);
  const dec = new TextDecoder('utf-8', { fatal: false });
  const slice = (i) => u8.subarray(offs[i], offs[i + 1]);
  let channel = '?', header = {}, parent = {}, content = {};
  try { channel = dec.decode(slice(0)); } catch {}
  try { header = JSON.parse(dec.decode(slice(1))); } catch {}
  try { parent = JSON.parse(dec.decode(slice(2))); } catch {}
  try { content = JSON.parse(dec.decode(slice(4))); } catch {}
  return { channel, header, parent, content };
}
function decodeText(payload) {
  if (typeof payload !== 'string') return null;
  try { return JSON.parse(payload); } catch { return null; }
}
const wsLog = [];
let dumpedOne = false;
function previewPayload(p) {
  if (typeof p === 'string') return `STR(${p.length}): ${p.slice(0, 200)}`;
  const u8 = new Uint8Array(p);
  const head = Array.from(u8.subarray(0, 32))
    .map((b) => b.toString(16).padStart(2, '0')).join(' ');
  let asAscii = '';
  for (const b of u8.subarray(0, 200)) asAscii += b >= 32 && b < 127 ? String.fromCharCode(b) : '.';
  return `BIN(${u8.byteLength}) hex[0..32]=${head} ascii=${asAscii}`;
}
page.on('websocket', (ws) => {
  const url = ws.url();
  if (!url.includes('/api/kernels/')) return;
  console.log('WS opened:', url, 'subprotocol=', ws.url());
  const handle = (dir) => (f) => {
    if (!dumpedOne) {
      dumpedOne = true;
      console.log('=== first frame', dir, '===');
      console.log(previewPayload(f.payload));
    }
    let m = decodeText(f.payload) ?? decodeJupyterV1(f.payload);
    if (m?.header?.msg_type) {
      const type = m.header.msg_type;
      const parent = m.parent?.header?.msg_type ?? '-';
      const state = m.content?.execution_state ?? '-';
      const ch = m.channel ?? '?';
      wsLog.push(`${dir} [${ch}] ${type} parent=${parent} state=${state}`);
    } else {
      wsLog.push(`${dir} <unparseable ${typeof f.payload === 'string' ? f.payload.length : f.payload.byteLength}>`);
    }
  };
  ws.on('framesent', handle('->'));
  ws.on('framereceived', handle('<-'));
  ws.on('close', () => wsLog.push(`WS closed: ${url}`));
  ws.on('socketerror', (e) => wsLog.push(`WS error: ${e}`));
});

console.log(`--- navigating to ${BASE}/lab ---`);
await page.goto(`${BASE}/lab`);

// Confirm JupyterLab actually booted. The DOM shape varies a bit
// across JupyterLab versions; wait for *anything* JupyterLab-shaped
// to appear, then sanity-check the title.
await page.waitForFunction(
  () => document.querySelector('[data-jp-theme-light]') ||
        document.querySelector('.jp-LabShell') ||
        document.querySelector('.jp-Application') ||
        document.title.includes('JupyterLab'),
  null,
  { timeout: 60_000 }
);
await page.waitForTimeout(2000);
console.log('JupyterLab UI is up; title:', await page.title());

// Inspect available kernelspecs via the REST API the page already
// has cookies for. This is what catches "kernel not registered" cases
// before we even try to open a notebook.
const ks = await page.evaluate(async () => {
  const r = await fetch('/api/kernelspecs');
  return r.json();
});
console.log('kernelspecs:', JSON.stringify(Object.keys(ks.kernelspecs || {})));
if (!ks.kernelspecs || !ks.kernelspecs.xlean) {
  console.log('FAIL: xlean kernelspec missing');
  process.exit(2);
}

// Create a new notebook with the xlean kernel via the REST API. Going
// through the Launcher UI is fragile because it needs the kernel name
// to match a card's data attribute; the REST path is direct.
const nbResp = await page.evaluate(async () => {
  // Need to send the XSRF token JupyterLab stamps into a cookie when we
  // first touch /lab. Without it, PUT /api/contents returns 403.
  function cookie(name) {
    const m = document.cookie.match(new RegExp('(^| )' + name + '=([^;]+)'));
    return m ? decodeURIComponent(m[2]) : null;
  }
  const xsrf = cookie('_xsrf');
  const r = await fetch('/api/contents/probe.ipynb', {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      ...(xsrf ? { 'X-XSRFToken': xsrf } : {}),
    },
    credentials: 'same-origin',
    body: JSON.stringify({
      type: 'notebook',
      content: {
        nbformat: 4,
        nbformat_minor: 5,
        metadata: {
          kernelspec: { name: 'xlean', display_name: 'Lean 4', language: 'lean' }
        },
        cells: [
          { cell_type: 'code', execution_count: null, metadata: {},
            outputs: [], source: '#eval 1\n' }
        ]
      }
    })
  });
  return { ok: r.ok, status: r.status, body: await r.text().then(s => s.slice(0, 200)) };
});
console.log('notebook created:', JSON.stringify(nbResp));

// Open it. JupyterLab creates the kernel session itself based on
// metadata.kernelspec.name in the notebook.
await page.goto(`${BASE}/lab/tree/probe.ipynb`);
await page.locator('.jp-Notebook').waitFor({ state: 'visible', timeout: 60_000 });
await page.locator('.jp-Notebook .jp-CodeCell .cm-content').first()
  .waitFor({ state: 'visible', timeout: 60_000 });

// Wait for the kernel to be ready by watching the iopub stream for an
// idle status message that isn't a reply to history_request — i.e.,
// the kernel has finished its boot handshake and is sitting waiting
// for user input. The DOM-based status indicator differs across
// JupyterLab versions and is brittle; the WebSocket truth is not.
console.log('--- waiting for kernel idle (via WS) ---');
const t0 = Date.now();
let bootDone = false;
while (Date.now() - t0 < 60_000) {
  const got = wsLog.filter((l) => l.includes('kernel_info_reply')).length;
  if (got > 0) { bootDone = true; break; }
  await page.waitForTimeout(250);
}
if (!bootDone) {
  console.log('TIMED OUT waiting for kernel_info_reply');
  console.log('=== ws (last 30) ===');
  for (const l of wsLog.slice(-30)) console.log(l);
  console.log('=== console (last 30) ===');
  for (const l of consoleLines.slice(-30)) console.log(l);
  await browser.close();
  process.exit(3);
}
console.log('kernel handshake complete');

// Run cell 0.
const cell = page.locator('.jp-Notebook .jp-CodeCell').first();
await cell.locator('.cm-content').first().click();
await page.keyboard.press('Shift+Enter');

const out = cell.locator('.jp-OutputArea-output').first();
let outText = '<no output>';
try {
  await out.waitFor({ state: 'visible', timeout: 60_000 });
  outText = (await out.textContent()) ?? '';
} catch (e) {
  outText = `<TIMEOUT: ${e.message}>`;
}

console.log('=== cell output ===');
console.log(outText);
console.log('=== console (last 30) ===');
for (const l of consoleLines.slice(-30)) console.log(l);

await browser.close();
process.exit(outText.trim().includes('1') ? 0 : 4);
