import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { createServer } from "node:http";
import { WebSocket } from "ws";

const CDP_PORT = 9222;
const MANAGE_PORT = 8080;

let chromeProcess = null;
let cdpWsUrl = "";
let cdpWs = null;

function findChromeBinary() {
  for (const p of ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome"]) {
    if (existsSync(p)) return p;
  }
  return "/usr/bin/chromium";
}

function startChromium() {
  return new Promise((resolve, reject) => {
    const chromePath = findChromeBinary();
    console.log(`Starting Chromium from: ${chromePath}`);

    const args = [
      "--headless=new",
      "--no-sandbox",
      "--disable-gpu",
      `--remote-debugging-port=${CDP_PORT}`,
      "--disable-dev-shm-usage",
      "--window-size=1920,1080",
      "--disable-extensions",
      "--disable-background-networking",
      "--disable-sync",
      "--no-first-run",
      "--disable-translate",
      "--disable-setuid-sandbox",
    ];

    chromeProcess = spawn(chromePath, args, {
      stdio: ["ignore", "pipe", "pipe"],
    });

    const timeout = setTimeout(() => reject(new Error("Chromium start timeout")), 15_000);

    chromeProcess.on("error", (err) => { clearTimeout(timeout); reject(err); });

    const onData = (data) => {
      const line = data.toString();
      console.log("[chrome]", line.trim());
      const match = line.match(/DevTools listening on (ws:\/\/.+)/);
      if (match) {
        clearTimeout(timeout);
        cdpWsUrl = match[1];
        resolve(cdpWsUrl);
      }
    };

    chromeProcess.stdout.on("data", onData);
    chromeProcess.stderr.on("data", onData);
    chromeProcess.on("exit", (code) => {
      console.log(`Chromium exited with code ${code}`);
      chromeProcess = null;
      cdpWsUrl = "";
    });
  });
}

function ensureCdpConnection() {
  return new Promise((resolve, reject) => {
    if (cdpWs && cdpWs.readyState === WebSocket.OPEN) {
      return resolve(cdpWs);
    }

    if (!cdpWsUrl) return reject(new Error("CDP URL not available"));

    // Convert ws://127.0.0.1:9222/devtools/browser/... to connect
    const ws = new WebSocket(cdpWsUrl);
    ws.on("open", () => { cdpWs = ws; resolve(ws); });
    ws.on("error", (e) => reject(e));
    setTimeout(() => reject(new Error("CDP WebSocket connect timeout")), 5_000);
  });
}

let msgId = 0;
const pending = new Map();

function sendCDP(method, params = {}) {
  return new Promise(async (resolve, reject) => {
    const ws = await ensureCdpConnection();
    const id = ++msgId;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 30_000);
    pending.set(id, { resolve, reject, timer });

    ws.send(JSON.stringify({ id, method, params }));
  });
}

function setupCdpHandler(ws) {
  ws.on("message", (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (msg.id !== undefined && pending.has(msg.id)) {
        const p = pending.get(msg.id);
        clearTimeout(p.timer);
        pending.delete(msg.id);
        p.resolve(msg);
      }
    } catch {}
  });
  ws.on("close", () => { cdpWs = null; });
  ws.on("error", () => { cdpWs = null; });
}

// Wrap ensureCdpConnection to set up handlers
const origEnsure = ensureCdpConnection;
ensureCdpConnection = function() {
  return new Promise((resolve, reject) => {
    if (cdpWs && cdpWs.readyState === WebSocket.OPEN) return resolve(cdpWs);
    if (!cdpWsUrl) return reject(new Error("CDP URL not available"));

    const ws = new WebSocket(cdpWsUrl);
    ws.on("open", () => { cdpWs = ws; setupCdpHandler(ws); resolve(ws); });
    ws.on("error", (e) => reject(e));
    setTimeout(() => reject(new Error("CDP WebSocket connect timeout")), 5_000);
  });
}

async function handleRequest(req, res) {
  const url = new URL(req.url, `http://localhost:${MANAGE_PORT}`);

  // Debug: log incoming request
  console.log(`[request] ${req.method} ${req.url} -> pathname=${url.pathname}`);

  // Health check
  if (req.method === "GET" && url.pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", chrome: chromeProcess !== null }));
    return;
  }

  // Get CDP URL
  if (req.method === "GET" && url.pathname === "/cdp-url") {
    if (!cdpWsUrl) {
      res.writeHead(503, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Chromium not running" }));
      return;
    }
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ url: cdpWsUrl }));
    return;
  }

  // Execute CDP command via HTTP
  if (url.pathname === "/cdp") {
    try {
      const body = await readBody(req);
      console.log(`[/cdp] method=${req.method} body=${body.substring(0, 100)}`);
      const { method, params } = JSON.parse(body);
      const result = await sendCDP(method, params);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(result));
    } catch (e) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: String(e) }));
    }
    return;
  }

  // Close
  if (req.method === "POST" && url.pathname === "/close") {
    if (chromeProcess) chromeProcess.kill("SIGTERM");
    chromeProcess = null; cdpWsUrl = "";
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "closed" }));
    return;
  }

  // Start
  if (req.method === "POST" && url.pathname === "/start") {
    if (chromeProcess) {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ url: cdpWsUrl }));
      return;
    }
    try {
      const wsUrl = await startChromium();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ url: wsUrl }));
    } catch (e) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: String(e) }));
    }
    return;
  }

  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (chunk) => { data += chunk; });
    req.on("end", () => resolve(data));
  });
}

async function main() {
  console.log("Starting Chromium on boot...");
  try {
    const wsUrl = await startChromium();
    console.log(`Chromium ready: ${wsUrl}`);
  } catch (e) {
    console.error(`Failed to start Chromium: ${e}`);
    process.exit(1);
  }

  createServer(handleRequest).listen(MANAGE_PORT, () => {
    console.log(`Management API on port ${MANAGE_PORT}`);
  });
}

main();
