# Spec: Electron Desktop Packaging
**Change**: electron-desktop
**Domain**: desktop
**Status**: draft
**Date**: 2026-05-19

---

## 1. Overview

This spec describes what MUST be true after the `electron-desktop` change is applied. It covers:

1. Electron scaffold wrapping the existing Nuxt SPA as a cross-platform desktop application
2. Icon migration from `lucide:*` (Iconify CDN) to `tabler:*` (pre-bundled) in `index.vue`
3. Offline operation guarantee — zero network requests at runtime for app assets

It does NOT describe HOW to implement these requirements.

---

## 2. Definitions

| Term | Meaning |
|------|---------|
| **Renderer** | The Chromium window that runs the Nuxt SPA inside Electron |
| **Main process** | The Node.js process that manages BrowserWindow, app lifecycle, and OS integration |
| **Preload script** | Sandboxed script injected into the renderer before page load |
| **Static output** | The result of `nuxt generate` — directory of static HTML, JS, CSS, and WASM files |
| **`lucide:*` icons** | `@nuxt/icon` dynamic string-keyed icons fetched from Iconify CDN at runtime |
| **`lucide-vue-next` imports** | Direct Vue component imports from `lucide-vue-next` npm package; already bundled by Vite and offline-safe — NOT in scope for icon migration |
| **`tabler:*` icons** | `@nuxt/icon` string-keyed icons resolved from the locally installed `@iconify-json/tabler` package |

---

## 3. Electron Scaffold Requirements

### 3.1 Project Structure

- An `electron/` directory MUST exist at the project root containing at minimum:
  - `electron/main.ts` — main process entry point
  - `electron/preload.ts` — preload script
- A `forge.config.ts` (or equivalent Electron Forge configuration file) MUST exist at the project root.

### 3.2 BrowserWindow Security

- The BrowserWindow MUST be created with `contextIsolation: true`.
- The BrowserWindow MUST be created with `nodeIntegration: false`.
- The BrowserWindow MUST be created with `sandbox: true`.
- The preload script MUST NOT expose arbitrary Node.js APIs to the renderer.

### 3.3 Loading the Nuxt Output

- In production, the BrowserWindow MUST load the Nuxt static output either:
  - (a) via a custom `app://` protocol serving files from the static output directory, OR
  - (b) via a `file://` protocol pointing to the `index.html` in the static output directory.
- Whichever loading strategy is chosen, ALL assets (JS, CSS, WASM, source maps) MUST resolve correctly inside the packaged app without any external network request.
- The Nuxt configuration MUST set `app.baseURL: './'` to ensure asset paths resolve correctly.

### 3.4 Development Workflow

- Running `pnpm electron:dev` MUST:
  1. Start the Nuxt dev server (HMR active)
  2. Open an Electron window pointing to the Nuxt dev server URL
- Changes to Vue/TS files MUST trigger Hot Module Replacement in the Electron renderer window.
- The Electron window MUST open only after the Nuxt dev server is ready.

### 3.5 npm Scripts

The following scripts MUST be added to `package.json`:
- `electron:dev` — launches the dev workflow described in §3.4
- `electron:build` — generates the Nuxt static output and compiles Electron main/preload
- `electron:make` — runs the full build pipeline and produces distributable artifacts

---

## 4. Offline Operation Requirements

### 4.1 Asset Coverage

All of the following asset categories MUST be served locally at runtime:

| Asset Category | Offline Mechanism |
|----------------|-------------------|
| App JS/CSS | Packaged in Electron ASAR |
| Monaco workers | Already offline via Vite `?worker` imports — no change required |
| esbuild-wasm `.wasm` | MUST resolve correctly from ASAR or via custom protocol |
| PixiJS | Already offline via npm bundle — no change required |
| Icons | Pre-bundled via `@iconify-json/tabler` + `clientBundle.scan: true` |

### 4.2 Icon Bundle Configuration

- `@iconify-json/tabler` MUST be installed as a project dependency.
- `nuxt.config.ts` MUST configure `@nuxt/icon` with `clientBundle: { scan: true }`.
- At runtime, ZERO requests to `api.iconify.design` or any Iconify CDN MUST be made.

### 4.3 esbuild-wasm WASM File

- The `esbuild.wasm` binary MUST be accessible inside the packaged app.
- If a custom protocol is used, it MUST serve `.wasm` files with `application/wasm` MIME type.

### 4.4 Verification

```
GIVEN the packaged app is launched with no internet access
WHEN the user opens a project, edits a script, compiles it, and previews the animation
THEN all functionality MUST work without any network error in DevTools Network panel
```

---

## 5. Build Pipeline Requirements

### 5.1 Artifact Production

Running `pnpm electron:make` MUST produce:
- **macOS**: `.dmg` installer
- **Windows**: `.exe` installer
- **Linux**: `.AppImage`

Artifacts MUST be written to an `out/` directory.

### 5.2 Build Sequence

1. `nuxt generate` — produces the static SPA output
2. Electron main/preload TypeScript compilation
3. `electron-forge make` — packages and produces installers

### 5.3 Gitignore

`.gitignore` MUST include entries for `out/` and intermediate Electron build directories.

---

## 6. Icon Migration Requirements

### 6.1 Scope

Migration applies ONLY to `@nuxt/icon` string-keyed icons (`<Icon name="lucide:*">` usages in `app/pages/index.vue`). Direct `lucide-vue-next` Vue component imports in `app/components/ui/**` MUST NOT be modified.

### 6.2 Migration Rule

Every `name="lucide:<icon-name>"` in `app/pages/index.vue` MUST be replaced with a semantically equivalent `name="tabler:<icon-name>"`. After migration, ZERO `lucide:*` strings MUST remain in that file.

### 6.3 Icon Equivalence (normative)

| `lucide:` icon | `tabler:` replacement |
|----------------|-----------------------|
| `expand` | `maximize` |
| `folder-open` | `folder-open` |
| `chevron-up` | `chevron-up` |
| `chevron-down` | `chevron-down` |
| `folder-plus` | `folder-plus` |
| `shrink` | `minimize` |
| `pause` | `player-pause` |
| `play` | `player-play` |
| `check` | `check` |
| `copy` | `copy` |
| `loader-circle` | `loader-2` |
| `save` | `device-floppy` |
| `x` | `x` |
| `circle-x` | `circle-x` |

---

## 7. Compatibility Requirements

- `pnpm dev`, `pnpm build`, and `pnpm generate` MUST continue to work unchanged.
- File System Access API, Web Audio API, and Monaco Editor MUST function inside the packaged app with NO changes to their respective source files.
- No Electron-specific code MUST be required in existing `app/` source files.

---

## 8. Acceptance Scenarios

### Scenario 1 — Dev workflow with HMR
```
GIVEN the developer runs `pnpm electron:dev`
THEN the Nuxt dev server starts AND an Electron window opens showing the UI
AND editing a .vue file triggers HMR in the Electron window
```

### Scenario 2 — Packaged app launches offline
```
GIVEN the packaged app with no internet access
WHEN the user opens the app
THEN all icons render and zero requests are made to api.iconify.design or any CDN
```

### Scenario 3 — End-to-end scripting pipeline
```
GIVEN the packaged app
WHEN the user opens a project, creates a script, and saves (Ctrl+S)
THEN esbuild-wasm compiles, PixiJS renders sprites, and Web Audio plays audio
```

### Scenario 4 — Icon migration complete
```
GIVEN the migrated source
WHEN grep searches app/pages/index.vue for "lucide:"
THEN zero matches are found
```

### Scenario 5 — Web flows unaffected
```
GIVEN the change applied
WHEN pnpm dev is run
THEN the app opens in a browser without error
AND pnpm build succeeds
```

---

## 9. Out-of-Scope

The following MUST NOT be implemented in this change:
- Auto-updater
- Code signing / notarization
- Custom native menus
- Native file dialogs via IPC replacing File System Access API
- Migration of `lucide-vue-next` direct imports in `app/components/ui/**`
