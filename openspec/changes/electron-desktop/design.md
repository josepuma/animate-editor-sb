# Design: Electron Desktop Packaging
**Change**: electron-desktop
**Status**: draft
**Date**: 2026-05-19

---

## 1. Architecture Overview

The app stays a standard three-process Electron application:

```
Main Process (Node.js)
├── electron/main.ts        ← BrowserWindow lifecycle, app:// protocol, app menu
├── electron/preload.ts     ← Sandboxed bridge (minimal for v1)
└── Renderer Process (Chromium)
    └── Nuxt SPA (loaded via app:// protocol from .output/public/)
```

No existing app source files change. All Electron-specific code lives in `electron/`.

---

## 2. Architecture Decisions

### 2.1 Loading Strategy: Custom `app://` Protocol (not `file://`)

**Decision**: Register a custom `app://` protocol in the main process that serves files from `.output/public/`.

**Rationale**:
- `file://` URLs have a null origin, which can break `fetch()` calls to relative paths and causes CORS issues with WASM loading in some Chromium versions
- A custom protocol provides a real origin (`app://localhost`) — Monaco blob workers and esbuild-wasm's WASM load without CORS/MIME errors
- The protocol handler explicitly sets `application/wasm` for `.wasm` files, solving the MIME type requirement for esbuild-wasm
- Cost: ~15 lines in main.ts vs `file://` approach

**Implementation**:
```ts
// electron/main.ts
protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { secure: true, standard: true, supportFetchAPI: true } }
])

protocol.handle('app', (request) => {
  const url = request.url.replace('app://localhost/', '')
  const filePath = path.join(staticOutputDir, ...url.split('/'))
  return net.fetch(`file://${filePath}`)
})
```

### 2.2 Toolchain: electron-forge + @electron-forge/plugin-vite

**Decision**: Use electron-forge with the official Vite plugin.

**Rationale**: electron-forge is the officially maintained Electron scaffolding tool. The `@electron-forge/plugin-vite` plugin handles TypeScript compilation of main/preload via Vite (consistent with the existing Nuxt/Vite setup), produces `out/` artifacts, and ships makers for all three platforms out of the box.

### 2.3 Dev Workflow: concurrently

**Decision**: Use `concurrently` (or `wait-on` + shell sequencing) to start the Nuxt dev server and Electron in parallel, with Electron waiting until port 3000 is ready.

```json
"electron:dev": "concurrently -k \"nuxt dev\" \"wait-on http://localhost:3000 && electron-forge start\""
```

---

## 3. Directory Structure

```
animate-editor-sb/
├── electron/
│   ├── main.ts             ← BrowserWindow, app:// protocol, lifecycle
│   └── preload.ts          ← Empty bridge for v1 (contextBridge ready for phase 2)
├── forge.config.ts         ← electron-forge makers (dmg, squirrel, appimage)
├── nuxt.config.ts          ← Add app.baseURL + icon.clientBundle config
├── package.json            ← New devDeps + scripts
└── out/                    ← electron-forge output (gitignored)
```

---

## 4. Key File Designs

### 4.1 `electron/main.ts`

```ts
import { app, BrowserWindow, protocol, net } from 'electron'
import path from 'node:path'

const STATIC_DIR = path.join(__dirname, '../../.output/public')
const DEV_URL = 'http://localhost:3000'
const isDev = !app.isPackaged

protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { secure: true, standard: true, supportFetchAPI: true } },
])

const createWindow = () => {
  const win = new BrowserWindow({
    width: 1400,
    height: 900,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
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
      return net.fetch(`file://${filePath}`)
    })
  }
  createWindow()
})

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow() })
```

### 4.2 `electron/preload.ts`

```ts
// Minimal preload — contextBridge ready for phase 2 native integrations
import { contextBridge } from 'electron'

contextBridge.exposeInMainWorld('electronAPI', {
  platform: process.platform,
})
```

### 4.3 `forge.config.ts`

```ts
import type { ForgeConfig } from '@electron-forge/shared-types'
import { VitePlugin } from '@electron-forge/plugin-vite'

const config: ForgeConfig = {
  packagerConfig: { asar: true },
  rebuildConfig: {},
  makers: [
    { name: '@electron-forge/maker-squirrel', config: {} },
    { name: '@electron-forge/maker-dmg', config: {} },
    { name: '@electron-forge/maker-appimage', config: {} },
  ],
  plugins: [
    new VitePlugin({
      build: [
        { entry: 'electron/main.ts', config: 'vite.main.config.ts' },
        { entry: 'electron/preload.ts', config: 'vite.preload.config.ts' },
      ],
      renderer: [],
    }),
  ],
}

export default config
```

### 4.4 `nuxt.config.ts` changes

```ts
export default defineNuxtConfig({
  // ... existing config ...
  app: {
    baseURL: './',        // relative paths for file:// / app:// compatibility
  },
  icon: {
    clientBundle: {
      scan: true,         // pre-bundle all icons found in source at build time
    },
  },
})
```

---

## 5. Icon Offline Strategy

### 5.1 Why icons currently break offline

No `@iconify-json/*` package is installed. `@nuxt/icon` falls back to runtime CDN fetch (`api.iconify.design`) for every icon not found locally.

### 5.2 Fix

1. Install `@iconify-json/tabler` as a devDependency
2. Set `icon.clientBundle.scan: true` in `nuxt.config.ts`
3. Replace the 14 `lucide:*` icon strings in `app/pages/index.vue` with `tabler:*` equivalents per the normative table in spec §6.3

### 5.3 Limitation to document

`clientBundle.scan` only captures **static string literals**. Dynamic bindings like `:name="\`tabler:${expr}\`"` are not captured. The one dynamic binding in `index.vue` (the play/pause toggle) uses two known values — both MUST be listed explicitly if scan doesn't pick them up, via `clientBundle.icons: ['tabler:player-play', 'tabler:player-pause']`.

---

## 6. Build Pipeline

```
pnpm electron:make
  └── 1. nuxt generate          → .output/public/
  └── 2. vite build (main)      → .vite/build/main/main.js
  └── 3. vite build (preload)   → .vite/build/preload/preload.js
  └── 4. electron-forge package → out/animate-editor-sb-{platform}/
  └── 5. electron-forge make    → out/make/{dmg,exe,AppImage}
```

---

## 7. New Dependencies

| Package | Type | Purpose |
|---------|------|---------|
| `electron` | devDep | Electron runtime |
| `@electron-forge/cli` | devDep | Forge CLI |
| `@electron-forge/plugin-vite` | devDep | Vite integration for main/preload |
| `@electron-forge/maker-dmg` | devDep | macOS .dmg maker |
| `@electron-forge/maker-squirrel` | devDep | Windows .exe maker |
| `@electron-forge/maker-appimage` | devDep | Linux .AppImage maker |
| `@electron-forge/shared-types` | devDep | TypeScript types for forge.config |
| `concurrently` | devDep | Parallel dev server + Electron |
| `wait-on` | devDep | Wait for Nuxt port before opening Electron |
| `@iconify-json/tabler` | devDep | Tabler icon data for offline bundling |

---

## 8. Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `nuxt generate` emits absolute `/_nuxt/...` URLs despite `app.baseURL: './'` | Med | Protocol handler strips leading slash; test with `nuxt generate` before packaging |
| Dynamic `tabler:player-play/pause` binding missed by `clientBundle.scan` | Med | Explicitly list in `clientBundle.icons` as fallback |
| AppImage on Wayland requires `--no-sandbox` | Low | Document; test on Ubuntu 24.04 before release |
| Windows Squirrel installer shows SmartScreen warning (unsigned) | High | Accepted for v1; code signing deferred to phase 2 |
| Packaged app ~200 MB | Certain | Documented in README as accepted trade-off |
