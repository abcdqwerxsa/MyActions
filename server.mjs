import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { createServer } from "node:http";

const CDP_PORT = 9222;
const MANAGE_PORT = 8080;

let chromeProcess = null;
let cdpWsUrl = "";

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

    const timeout = setTimeout(() => {
      reject(new Error("Chromium start timeout after 15s"));
    }, 15_000);

    chromeProcess.on("error", (err) => {
      clearTimeout(timeout);
      reject(err);
    });

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

async function closeChromium() {
  if (chromeProcess) {
    chromeProcess.kill("SIGTERM");
    await new Promise((r) => setTimeout(r, 1000));
    if (chromeProcess) chromeProcess.kill("SIGKILL");
    chromeProcess = null;
    cdpWsUrl = "";
  }
}

async function handleRequest(req, res) {
  const url = new URL(req.url, `http://localhost:${MANAGE_PORT}`);

  if (req.method === "GET" && url.pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", chrome: chromeProcess !== null }));
    return;
  }

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

  if (req.method === "POST" && url.pathname === "/close") {
    await closeChromium();
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "closed" }));
    return;
  }

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
    console.log(`Management API listening on port ${MANAGE_PORT}`);
  });
}

main();
