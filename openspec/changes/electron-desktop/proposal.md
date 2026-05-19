# Proposal: Electron Desktop Packaging

## Intent

Distribute animate-editor-sb as a cross-platform desktop application (macOS, Windows, Linux) without rewriting the existing web app. Currently users must serve the SPA via `pnpm dev` or a static host; a native installer makes the editor accessible to mappers who don't want to manage a dev environment and removes browser permission friction (File System Access API prompts, audio autoplay restrictions).

## Scope

### In Scope
- Add Electron + electron-forge scaffold (main process, preload, build config)
- Wire Nuxt static output (`nuxt generate` → `.output/public`) as the renderer source
- Production build pipeline producing `.dmg`, `.exe`, and `.AppImage` artifacts
- Local dev workflow: `pnpm electron:dev` boots Nuxt dev server + Electron shell with HMR
- Verify Monaco workers, esbuild-wasm, and PixiJS load correctly inside packaged Electron
- **Icon migration**: replace all `lucide:*` icons with `tabler:*` equivalents across `app/`
- **Offline guarantee**: install `@iconify-json/tabler` and configure `@nuxt/icon` with `clientBundle: { scan: true }` — all icons pre-bundled at build time, zero CDN fetch at runtime

### Out of Scope
- Auto-updater (deferred to phase 2)
- Code signing / notarization (deferred to phase 2, requires Apple/Windows certificates)
- Native menus beyond defaults (File/Edit/View)
- Native file dialogs replacing File System Access API (works as-is in Chromium)

## Capabilities

### New Capabilities
- `desktop-packaging`: Electron main process, preload script, build configuration, and dev/prod scripts to package the existing SPA as a native desktop app

### Modified Capabilities
- None — this change is purely additive scaffolding. No existing requirements change.

## Approach

Electron over Tauri/Rust-rewrite: Tauri uses each OS's native WebView, which lacks File System Access API on Windows and macOS — a hard requirement for the editor. A Rust rewrite has no Monaco-equivalent and would take months.

Steps:
1. Add `electron`, `electron-forge`, `@electron-forge/plugin-vite` (or `electron-builder`) as devDependencies
2. Create `electron/main.ts` (BrowserWindow, load Nuxt output) and `electron/preload.ts` (minimal, no `nodeIntegration`)
3. Add `forge.config.ts` with makers for `dmg`, `squirrel`, `appimage`
4. Add npm scripts: `electron:dev`, `electron:build`, `electron:make`
5. Adjust Nuxt config: `ssr: false` already set, ensure `app.baseURL` works with `file://` protocol or use a local static server inside Electron
6. Verify Monaco worker resolution (`MonacoEnvironment.getWorkerUrl`) and esbuild-wasm `.wasm` MIME serving

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `electron/` (new) | New | Main process, preload, forge config |
| `package.json` | Modified | New devDeps (`electron`, `electron-forge`, `@iconify-json/tabler`), new scripts |
| `nuxt.config.ts` | Modified | `app.baseURL: './'` for `file://` loading + `icon.clientBundle.scan: true` |
| `.gitignore` | Modified | Ignore `out/`, `dist-electron/` |
| `app/pages/index.vue` | Modified | Replace all `lucide:*` → `tabler:*` icon names |
| `app/components/ui/**` | Modified | Replace `lucide:*` → `tabler:*` in any UI component that uses `<Icon>` |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Monaco workers fail to load under `file://` | Med | Use custom protocol or local Express static server in main process |
| esbuild-wasm `.wasm` not served with correct MIME | Med | Same — internal static server with explicit content-type |
| PixiJS WebGL context issues on Linux | Low | Test AppImage on Ubuntu before tagging release |
| App size bloat (~200 MB) | High | Acceptable trade-off for v1; document in README |

## Rollback Plan

Remove the `electron/` directory, delete added devDeps and scripts from `package.json`, and revert `nuxt.config.ts`. No app code was touched — the web SPA continues to work identically. A single `git revert` of the implementation commit fully restores prior state.

## Dependencies

- Node 20+ (already required)
- pnpm 9+ (already required)
- Platform-specific build tools only at package time (notarytool on macOS for phase 2)

## Success Criteria

- [ ] `pnpm electron:dev` opens the editor in a native window with HMR working
- [ ] `pnpm electron:make` produces installable artifacts for macOS, Windows, Linux
- [ ] Inside the packaged app: create script, compile (esbuild-wasm), preview (PixiJS), pick directory (File System Access), play audio — all work
- [ ] All icons render correctly with zero network requests (verified with DevTools → Network offline mode)
- [ ] Existing `pnpm dev` / `pnpm build` web flows continue to work unchanged
