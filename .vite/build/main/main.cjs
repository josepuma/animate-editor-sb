"use strict";
const electron = require("electron");
const path = require("node:path");
const http = require("node:http");
const STATIC_DIR = path.join(__dirname, "../../.output/public");
const DEV_URL = "http://localhost:3100";
const isDev = !electron.app.isPackaged;
electron.protocol.registerSchemesAsPrivileged([
  { scheme: "app", privileges: { secure: true, standard: true, supportFetchAPI: true } }
]);
const waitForVite = (url, interval = 300) => new Promise((resolve) => {
  const check = () => http.get(url, (res) => {
    if (res.statusCode === 200) return resolve();
    setTimeout(check, interval);
  }).on("error", () => setTimeout(check, interval));
  check();
});
const createWindow = () => {
  const win = new electron.BrowserWindow({
    width: 1400,
    height: 900,
    titleBarStyle: process.platform === "darwin" ? "hiddenInset" : "hidden",
    webPreferences: {
      preload: path.join(__dirname, "../preload/preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      // sandbox must be false — FSAA createWritable() hangs indefinitely with
      // sandbox enabled because the sandboxed renderer cannot acquire write
      // privileges through the OS broker. contextIsolation + nodeIntegration:false
      // provide the security boundary instead.
      sandbox: false
    }
  });
  if (isDev) {
    win.loadURL(DEV_URL);
  } else {
    win.loadURL("app://localhost/index.html");
  }
};
electron.app.whenReady().then(async () => {
  const CSP = [
    "default-src 'self'",
    "script-src 'self' 'unsafe-eval' 'unsafe-inline' blob:",
    "worker-src 'self' blob:",
    "style-src 'self' 'unsafe-inline'",
    "font-src 'self' data:",
    "img-src 'self' blob: data:",
    "connect-src 'self' ws: wss: http://localhost:3100"
  ].join("; ");
  electron.session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        "Content-Security-Policy": [CSP]
      }
    });
  });
  if (!isDev) {
    electron.protocol.handle("app", (request) => {
      const url = request.url.replace("app://localhost/", "");
      const filePath = path.join(STATIC_DIR, ...decodeURIComponent(url).split("/"));
      const mimeType = filePath.endsWith(".wasm") ? "application/wasm" : void 0;
      if (mimeType) {
        return electron.net.fetch(`file://${filePath}`).then(async (res) => {
          const body = await res.arrayBuffer();
          return new Response(body, {
            status: res.status,
            headers: { "Content-Type": mimeType }
          });
        });
      }
      return electron.net.fetch(`file://${filePath}`);
    });
  } else {
    await waitForVite(DEV_URL);
    await electron.session.defaultSession.clearCache();
  }
  createWindow();
});
electron.app.on("window-all-closed", () => {
  if (process.platform !== "darwin") electron.app.quit();
});
electron.app.on("activate", () => {
  if (electron.BrowserWindow.getAllWindows().length === 0) createWindow();
});
