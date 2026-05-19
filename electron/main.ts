import { app, BrowserWindow, protocol, net } from 'electron'
import path from 'node:path'

const STATIC_DIR = path.join(__dirname, '../../.output/public')
const DEV_URL = 'http://localhost:3000'
const isDev = !app.isPackaged

protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { secure: true, standard: true, supportFetchAPI: true } },
])

const createWindow = (): void => {
  const win = new BrowserWindow({
    width: 1400,
    height: 900,
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'hidden',
    webPreferences: {
      preload: path.join(__dirname, '../preload/preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  })

  if (isDev) {
    win.loadURL(DEV_URL)
  } else {
    win.loadURL('app://localhost/index.html')
  }
}

app.whenReady().then(() => {
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
  }
  createWindow()
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow()
})
