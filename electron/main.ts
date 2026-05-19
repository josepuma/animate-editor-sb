import { app, BrowserWindow, protocol, net, session } from 'electron'
import path from 'node:path'
import http from 'node:http'

const STATIC_DIR = path.join(__dirname, '../../.output/public')
const DEV_URL = 'http://localhost:3100'
const isDev = !app.isPackaged

protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { secure: true, standard: true, supportFetchAPI: true } },
])

// Polls until Vite responds with 200 on the root — this fires only after dep
// optimization completes, avoiding the 504 Outdated Optimize Dep race.
const waitForVite = (url: string, interval = 300): Promise<void> =>
  new Promise((resolve) => {
    const check = () =>
      http.get(url, (res) => {
        if (res.statusCode === 200) return resolve()
        setTimeout(check, interval)
      }).on('error', () => setTimeout(check, interval))
    check()
  })

const createWindow = (): void => {
  const win = new BrowserWindow({
    width: 1400,
    height: 900,
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'hidden',
    webPreferences: {
      preload: path.join(__dirname, '../preload/preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      // sandbox must be false — FSAA createWritable() hangs indefinitely with
      // sandbox enabled because the sandboxed renderer cannot acquire write
      // privileges through the OS broker. contextIsolation + nodeIntegration:false
      // provide the security boundary instead.
      sandbox: false,
    },
  })

  if (isDev) {
    win.loadURL(DEV_URL)
  } else {
    win.loadURL('app://localhost/index.html')
  }
}

app.whenReady().then(async () => {
  // unsafe-eval: required by Monaco TS language service and esbuild-wasm.
  // unsafe-inline: required by Nuxt inline bootstrap scripts.
  // blob:: required for ?worker&inline blob URLs.
  const CSP = [
    "default-src 'self'",
    "script-src 'self' 'unsafe-eval' 'unsafe-inline' blob:",
    "worker-src 'self' blob:",
    "style-src 'self' 'unsafe-inline'",
    "font-src 'self' data:",
    "img-src 'self' blob: data:",
    "connect-src 'self' ws: wss: http://localhost:3100",
  ].join('; ')

  session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        'Content-Security-Policy': [CSP],
      },
    })
  })

  if (!isDev) {
    protocol.handle('app', (request) => {
      const url = request.url.replace('app://localhost/', '')
      const filePath = path.join(STATIC_DIR, ...decodeURIComponent(url).split('/'))
      const mimeType = filePath.endsWith('.wasm') ? 'application/wasm' : undefined
      if (mimeType) {
        return net.fetch(`file://${filePath}`).then(async (res) => {
          const body = await res.arrayBuffer()
          return new Response(body, {
            status: res.status,
            headers: { 'Content-Type': mimeType },
          })
        })
      }
      return net.fetch(`file://${filePath}`)
    })
  } else {
    await waitForVite(DEV_URL)
    // Clear browser cache between dev sessions so stale Vite dep hashes
    // never cause 504 Outdated Optimize Dep errors.
    await session.defaultSession.clearCache()
  }
  createWindow()
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow()
})
