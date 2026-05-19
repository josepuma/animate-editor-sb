# Tasks: Electron Desktop Packaging
**Change**: electron-desktop
**Status**: pending
**Date**: 2026-05-19
**Delivery**: single-pr (estimated < 400 lines, additive scaffold + icon rename)

---

## Review Workload Forecast

| Metric | Value |
|--------|-------|
| Estimated changed lines | ~300 |
| New files | 5 (electron/main.ts, electron/preload.ts, forge.config.ts, vite.main.config.ts, vite.preload.config.ts) |
| Modified files | 4 (package.json, nuxt.config.ts, .gitignore, app/pages/index.vue) |
| Chained PRs recommended | No |
| 400-line budget risk | Low |
| Decision needed before apply | No |

---

## Phase 1 — Dependencies & Config

> Sequential. Must complete before any Electron file is created or tested.

- [x] **1.1** Install Electron runtime and forge toolchain as devDependencies
  ```
  pnpm add -D electron @electron-forge/cli @electron-forge/plugin-vite \
    @electron-forge/shared-types \
    @electron-forge/maker-dmg \
    @electron-forge/maker-squirrel \
    @electron-forge/maker-appimage
  ```
  Spec ref: §3 (scaffold requirements), §5.1 (artifact production), design §7

- [x] **1.2** Install dev-workflow helpers as devDependencies
  ```
  pnpm add -D concurrently wait-on
  ```
  Spec ref: §3.4 (dev workflow), design §2.3

- [x] **1.3** Install tabler icon data as devDependency
  ```
  pnpm add -D @iconify-json/tabler
  ```
  Spec ref: §4.2 (icon bundle configuration), §6 (icon migration)

- [x] **1.4** Add three scripts to `package.json`
  - `"electron:dev"`: `"concurrently -k \"nuxt dev\" \"wait-on http://localhost:3000 && electron-forge start\""`
  - `"electron:build"`: `"nuxt generate && electron-forge build"`
  - `"electron:make"`: `"nuxt generate && electron-forge make"`

  Spec ref: §3.5 (required npm scripts)

- [x] **1.5** Update `nuxt.config.ts` — add two config blocks
  - `app: { baseURL: './' }` — relative asset paths for `app://` / `file://` loading
  - `icon: { clientBundle: { scan: true, icons: ['tabler:player-play', 'tabler:player-pause'] } }` — pre-bundle all scanned icons plus the two dynamic bindings that scan may miss

  Spec ref: §3.3 (loading strategy), §4.2 (icon bundle), design §2.1, §5.3

- [x] **1.6** Update `.gitignore` — append the following entries
  ```
  # Electron build artifacts
  out/
  .vite/
  dist-electron/
  ```
  Spec ref: §5.3 (gitignore requirement)

---

## Phase 2 — Electron Scaffold

> Tasks 2.1–2.5 are independent of each other once Phase 1 is done; they can be applied in any order or in parallel.

- [x] **2.1** Create `electron/main.ts`
  - Register `app://` as a privileged scheme (secure, standard, supportFetchAPI)
  - `createWindow()` creates BrowserWindow with:
    - `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true`
    - preload pointing to compiled `preload.js`
  - In dev: `win.loadURL('http://localhost:3000')`
  - In prod: `protocol.handle('app', ...)` serves files from `.output/public/` with explicit `application/wasm` for `.wasm` files; `win.loadURL('app://localhost/index.html')`
  - Standard macOS `window-all-closed` / `activate` lifecycle hooks

  Spec ref: §3.1, §3.2, §3.3, §3.4, §4.3, design §4.1

- [x] **2.2** Create `electron/preload.ts`
  - Import `contextBridge` from `'electron'`
  - Expose single `electronAPI` object with `platform: process.platform`
  - No other Node.js APIs exposed

  Spec ref: §3.2 (preload MUST NOT expose arbitrary Node.js APIs), design §4.2

- [x] **2.3** Create `forge.config.ts` at project root
  - `packagerConfig: { asar: true }`
  - Three makers: `@electron-forge/maker-squirrel` (Windows), `@electron-forge/maker-dmg` (macOS), `@electron-forge/maker-appimage` (Linux)
  - `VitePlugin` with two build entries: `electron/main.ts → vite.main.config.ts`, `electron/preload.ts → vite.preload.config.ts`
  - `renderer: []` (renderer is handled by Nuxt, not forge)

  Spec ref: §3.1, §5.1, design §4.3

- [x] **2.4** Create `vite.main.config.ts` at project root
  - Target: `node` + `electron-main`
  - Entry: `electron/main.ts`
  - Externalize `electron` (do not bundle it)
  - Output to `.vite/build/main/`

  Spec ref: §3 (scaffold), design §2.2, §6

- [x] **2.5** Create `vite.preload.config.ts` at project root
  - Target: `node` + `electron-preload`
  - Entry: `electron/preload.ts`
  - Externalize `electron`
  - Output to `.vite/build/preload/`

  Spec ref: §3 (scaffold), design §2.2, §6

---

## Phase 3 — Icon Migration

> Independent of Phase 2. Can run in parallel with Phase 2 once Phase 1 (task 1.3 + 1.5) is done.

- [x] **3.1** Replace all `lucide:*` icon name strings in `app/pages/index.vue` with `tabler:*` equivalents per the normative table (spec §6.3)

  Exact replacements (15 occurrences across the 14 logical icons):

  | Line(s) | Old value | New value |
  |---------|-----------|-----------|
  | `lucide:expand` | `tabler:maximize` |
  | `lucide:folder-open` (×2) | `tabler:folder-open` |
  | `lucide:chevron-up` | `tabler:chevron-up` |
  | `lucide:chevron-down` | `tabler:chevron-down` |
  | `lucide:folder-plus` | `tabler:folder-plus` |
  | `lucide:shrink` | `tabler:minimize` |
  | `lucide:pause` (dynamic) | `tabler:player-pause` |
  | `lucide:play` (dynamic) | `tabler:player-play` |
  | `lucide:check` (dynamic) | `tabler:check` |
  | `lucide:copy` (dynamic) | `tabler:copy` |
  | `lucide:loader-circle` (×3) | `tabler:loader-2` |
  | `lucide:save` | `tabler:device-floppy` |
  | `lucide:x` | `tabler:x` |
  | `lucide:circle-x` | `tabler:circle-x` |

  After replacement: `grep "lucide:" app/pages/index.vue` MUST return zero matches.

  Spec ref: §6.1, §6.2, §6.3 (normative table), Scenario 4

---

## Phase 4 — Verification (Manual Checklist)

> Sequential after Phases 1–3. Cannot be automated without a display; manual steps only.

- [ ] **4.1** Run `pnpm dev` and confirm the web SPA opens in a browser without error
  - Spec ref: §7 (compatibility), Scenario 5

- [ ] **4.2** Run `pnpm electron:dev` and confirm:
  - Nuxt dev server starts (port 3000)
  - Electron window opens showing the editor UI
  - Editing a `.vue` file triggers HMR in the window
  - Spec ref: §3.4, Scenario 1

- [ ] **4.3** In the running Electron dev window:
  - Open a project (File System Access API prompt appears and works)
  - Create a script, write a sprite command, press Ctrl+S
  - Confirm esbuild-wasm compiles without error
  - Confirm PixiJS renders sprites in the preview canvas
  - Confirm Web Audio plays audio
  - Spec ref: §7, Scenario 3

- [ ] **4.4** Run `pnpm electron:make` and confirm:
  - `nuxt generate` produces `.output/public/`
  - Main and preload scripts compile without TypeScript errors
  - `out/make/` contains platform artifact (`.dmg` / `.exe` / `.AppImage`)
  - Spec ref: §5.1, §5.2

- [ ] **4.5** Launch the packaged app with network disabled (DevTools → Network → Offline):
  - All icons render (no broken icon glyphs)
  - DevTools Network panel shows zero requests to `api.iconify.design` or any CDN
  - esbuild-wasm, PixiJS, and Web Audio still work
  - Spec ref: §4.1, §4.2, §4.4, Scenario 2

---

## Task Dependency Summary

```
1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6    (sequential, Phase 1)
                                 ↓
              ┌──────────────────┼──────────────────────┐
             2.1               2.2              2.3+2.4+2.5
              └──────────────────┴──────────────────────┘
                                 │
             3.1 (parallel with Phase 2, requires 1.3+1.5)
                                 │
                               4.1–4.5 (sequential verification)
```

**Parallelizable**: Tasks 2.1, 2.2, 2.3, 2.4, 2.5, and 3.1 can all run concurrently once Phase 1 is complete.

**Bottleneck**: Phase 1 is strictly sequential and blocks everything else. All Phase 4 steps block on Phases 2 and 3.
