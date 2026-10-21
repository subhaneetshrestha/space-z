// build/check-web.mjs — load the web build in a real Edge and fail if it does not run.
//
//   node build/check-web.mjs [url] [outDir]     # default http://localhost:8080/  dist/web-check
//
// Serve the build first (pwsh build/build-web.ps1 -Serve). No dependencies: Node 22+ for the
// built-in WebSocket, and Microsoft Edge, which is driven over its DevTools protocol.
// It checks what a first visit needs and what the headless suite cannot see:
//   * no fatal love.js alert (a Lua error before the first frame shows one, and a modal
//     dialog freezes the page, so it looks like a hang from the outside),
//   * no uncaught exception, a canvas exists, and the page keeps drawing frames,
//   * after LAUNCH the screen shows more than a flat background (the sprite atlas works).
// Screenshots go to outDir. Exit code 0 = ok, 1 = a check failed. Not run in CI (needs a browser).
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";

const URL = process.argv[2] || "http://localhost:8080/";
const OUT = process.argv[3] || "dist/web-check";
const EDGE = process.env.EDGE_PATH || "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe";
const PORT = 9334;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
mkdirSync(OUT, { recursive: true });

const proc = spawn(EDGE, [
  "--headless=new", `--remote-debugging-port=${PORT}`, `--user-data-dir=${OUT}/profile`,
  "--ignore-gpu-blocklist", "--window-size=520,1000", "about:blank",
], { stdio: "ignore" });

const problems = [];
const fail = (msg) => { problems.push(msg); console.log("FAIL: " + msg); };

let page;
for (let i = 0; i < 60 && !page; i++) {
  try { page = (await (await fetch(`http://127.0.0.1:${PORT}/json`)).json()).find((t) => t.type === "page"); } catch {}
  if (!page) await sleep(250);
}
if (!page) { console.log("FAIL: could not start Edge at " + EDGE); proc.kill(); process.exit(1); }

const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let id = 0;
const pending = new Map();
const send = (method, params = {}, ms = 8000) => new Promise((res) => {
  const i = ++id;
  const to = setTimeout(() => { pending.delete(i); res(null); }, ms);
  pending.set(i, (r) => { clearTimeout(to); res(r); });
  ws.send(JSON.stringify({ id: i, method, params }));
});
ws.onmessage = (m) => {
  const d = JSON.parse(m.data);
  if (d.id && pending.has(d.id)) { pending.get(d.id)(d.result ?? d.error ?? {}); pending.delete(d.id); return; }
  if (d.method === "Page.javascriptDialogOpening") {
    fail("a dialog opened: " + d.params.message);
    ws.send(JSON.stringify({ id: ++id, method: "Page.handleJavaScriptDialog", params: { accept: true } }));
  }
  if (d.method === "Runtime.exceptionThrown") {
    fail("uncaught exception: " + (d.params.exceptionDetails.exception?.description ?? d.params.exceptionDetails.text));
  }
  if (d.method === "Runtime.consoleAPICalled" && d.params.type === "log") {
    const text = d.params.args.map((a) => a.value ?? "").join(" ");
    if (/^Error:/.test(text)) fail("the game logged: " + text);
  }
};
const shot = async (name) => {
  const r = await send("Page.captureScreenshot", { format: "png" }, 15000);
  if (r?.data) writeFileSync(`${OUT}/${name}.png`, Buffer.from(r.data, "base64"));
  else fail("no screenshot " + name + " (is the page frozen?)");
  return r?.data;
};
const evalJs = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true }, 8000))?.result?.value;
const click = async (x, y) => {
  for (const type of ["mousePressed", "mouseReleased"]) {
    await send("Input.dispatchMouseEvent", { type, x, y, button: "left", buttons: type === "mousePressed" ? 1 : 0, clickCount: 1 }, 5000);
  }
};

await send("Runtime.enable"); await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: 520, height: 1000, deviceScaleFactor: 1, mobile: false });
await send("Page.navigate", { url: URL });
await sleep(15000);

if (!(await evalJs("!!document.querySelector('canvas')"))) fail("no canvas on the page");
await shot("1-menu");
const rate = await evalJs(`new Promise(res => { let n = 0; const t0 = performance.now(); (function f() { n++; if (performance.now() - t0 < 2000) requestAnimationFrame(f); else res(n / 2); })(); })`);
console.log("frames per second the page draws:", rate);
if (!(rate > 10)) fail("the page is not drawing frames (" + rate + "/s)");

// LAUNCH is the first menu row (no saved run); give the run a few seconds, then compare how
// much of the screen is background: a working sprite atlas puts a ship and enemies there
await click(260, 529);
await sleep(7000);
const data = await shot("2-playing");
if (data) {
  const colours = await evalJs(`new Promise(res => { const img = new Image(); img.onload = () => {
    const c = document.createElement('canvas'); c.width = 480; c.height = 854; const g = c.getContext('2d');
    g.drawImage(img, 20, 80, 480, 854, 0, 0, 480, 854);
    const px = g.getImageData(0, 0, 480, 854).data; const seen = new Set();
    for (let i = 0; i < px.length; i += 4 * 7) seen.add((px[i] >> 4) * 256 + (px[i + 1] >> 4) * 16 + (px[i + 2] >> 4));
    res(seen.size); };
    img.src = 'data:image/png;base64,${data}'; })`);
  console.log("distinct colours on the playfield:", colours);
  if (!(colours > 40)) fail("the playfield looks empty (" + colours + " colours): are the sprites drawn?");
}

console.log(problems.length ? `${problems.length} check(s) failed` : "OK: the web build starts, draws frames and shows sprites");
ws.close(); proc.kill();
process.exit(problems.length ? 1 : 0);
