# storybrew-web — Contexto y Arquitectura

## Qué es este proyecto

Un clon web de **storybrew** (herramienta para crear storyboards de osu!) construido con **Nuxt 4 + TypeScript**. La app corre completamente en el browser — no hay backend de procesamiento. Los assets y proyectos del usuario viven en su máquina local, accesados via **File System Access API**.

## Objetivo

Permitir a usuarios crear storyboards para osu! escribiendo scripts TypeScript en el browser, con preview en tiempo real sincronizado al audio, y exportación a formato `.osb`.

## Stack técnico

- **Framework**: Nuxt 4 (modo SPA, `ssr: false`)
- **UI**: Vue 3 + Tailwind CSS 4 + **Shadcn-vue** (reka-ui) + **Nuxt Icon**
- **Editor de código**: Monaco Editor (import dinámico/lazy)
- **Compilación TS en browser**: esbuild-wasm
- **Rendering**: PixiJS v8 (WebGL por default, Canvas 2D fallback automático)
- **Audio**: Web Audio API (nativo, sin librerías)
- **Archivos locales**: File System Access API (Chrome/Edge)
- **Utilidades**: VueUse

## Estructura de carpetas (implementada)

```
app/
├── components/
│   └── ui/              → componentes Shadcn-vue (ya instalados)
├── composables/
│   ├── useAudio.ts       → playback Web Audio API, currentMs, seek, play/pause
│   ├── useFileSystem.ts  → File System Access API, openProject, getFileHandle, fileTree
│   └── useScripting.ts   → compila TS → ejecuta en Worker → devuelve StoryboardSprite[]
├── lib/
│   ├── engine/
│   │   ├── easing.ts     → enum Easing, applyEasing(), easedLerp(), lerp()
│   │   ├── timeline.ts   → resolveSprite(), resolveStoryboard() — interpola comandos en el tiempo
│   │   └── renderer.ts   → clase StoryboardRenderer (PixiJS v8), init(), render(), loadTextures()
│   ├── scripting/
│   │   ├── api.ts        → clase SpriteBuilder (fluent API), createScriptContext()
│   │   └── compiler.ts   → initCompiler(), compileScript() — esbuild-wasm
│   └── exporter/
│       └── osb.ts        → exportOsb(), downloadOsb(), saveOsb()
├── pages/
│   └── index.vue         → (pendiente) página principal del editor
├── types/
│   ├── index.ts          → re-exporta todo
│   ├── layer.ts          → enum Layer, enum Origin
│   ├── easing.ts         → enum Easing
│   ├── commands.ts       → interfaces FadeCommand, MoveCommand, etc. + union Command
│   ├── sprite.ts         → interface StoryboardSprite
│   ├── storyboard.ts     → interface Storyboard
│   ├── project.ts        → interface Project, ProjectConfig
│   └── renderer.ts       → interface SpriteRenderState
└── workers/
    └── script-runner.ts  → Web Worker: recibe JS compilado → ejecuta → devuelve sprites
```

## Enums clave

```ts
enum Layer    { Background, Foreground, Overlay, Pass, Fail }
enum Origin   { TopLeft, TopCentre, TopRight, CentreLeft, Centre, CentreRight, BottomLeft, BottomCentre, BottomRight }
enum Easing   { Linear, Out, In, QuadIn, QuadOut, ... SineOut, ExpoIn, BounceOut, ... } // 35 valores (IDs osu!)
```

## API de scripting (lo que el usuario escribe en Monaco)

```ts
// Variables globales inyectadas: sprite, beat, bpm, offset, Layer, Origin, Easing
sprite('logo.png', Layer.Foreground, Origin.Centre)
  .fade(Easing.SineOut, 0, 500, 0, 1)
  .move(Easing.Linear, 0, 1000, 320, 480, 320, 240)
  .scale(Easing.QuadOut, 0, 300, 0.5, 1)

// beat(n) convierte beats → ms usando el BPM del proyecto
sprite('bg.png').fade(Easing.Linear, beat(0), beat(4), 0, 1)
```

## Flujo de datos completo

```
Usuario escribe TS en Monaco
  → useScripting.run(tsSource, bpm, offset)
    → compileScript() [esbuild-wasm, main thread]
    → Worker: executeScript(jsCode) con createScriptContext()
    → Worker devuelve StoryboardSprite[]
  → renderer.loadTextures(sprites, getFileHandle)
  → loop: useAudio.currentMs → renderer.render(sprites, currentMs)
    → resolveStoryboard(sprites, timeMs) [timeline.ts]
    → applyState() en cada PixiJS Sprite
  → exportOsb(storyboard) → archivo .osb
```

## Modelo de datos

### StoryboardSprite
```ts
{ id, layer: Layer, origin: Origin, filePath, defaultX, defaultY, commands: Command[] }
```

### Command (union)
```ts
// Todos extienden: { type, easing: Easing, startTime, endTime }
FadeCommand      → { startOpacity, endOpacity }
MoveCommand      → { startX, startY, endX, endY }
ScaleCommand     → { startScale, endScale }
RotateCommand    → { startAngle, endAngle }  // radianes
ColorCommand     → { startR/G/B, endR/G/B }  // 0-255
ParameterCommand → { parameter: 'H'|'V'|'A' } // flip/additive
```

### SpriteRenderState (output del timeline por frame)
```ts
{ spriteId, x, y, scaleX, scaleY, rotation, opacity, r, g, b, visible, additive, flipH, flipV }
```

## Formato .osb de osu! (referencia)

```
Sprite,Foreground,Centre,"logo.png",320,240
 _F,16,0,500,0,1
 _M,0,0,1000,320,480,320,240
 _S,4,0,300,0.5,1
 _R,0,0,1000,0,6.28
 _C,0,0,1000,255,255,255,128,0,255
 _P,0,0,500,H
```

## Componentes de UI pendientes

La UI debe construirse con **Shadcn-vue + Tailwind CSS 4**. Layout principal del editor:

```
┌─────────────────────────────────────────────────────┐
│  Toolbar (open project, run script, export, audio)  │
├──────────────┬──────────────────────┬───────────────┤
│  File Browser│   Preview (PixiJS)   │ Monaco Editor │
│  (árbol de   │   640×480, centrado  │ (TypeScript)  │
│   archivos)  │   en su contenedor   │               │
├──────────────┴──────────────────────┴───────────────┤
│  Timeline (scroll horizontal, posición actual)      │
│  Audio controls (play/pause, seek, tiempo, volumen) │
└─────────────────────────────────────────────────────┘
```

Componentes a crear:
- `components/editor/EditorLayout.vue` → layout principal con paneles redimensionables
- `components/editor/PreviewCanvas.vue` → monta StoryboardRenderer en un div, `ClientOnly`
- `components/editor/MonacoEditor.vue` → Monaco lazy-loaded, emite cambios de código
- `components/editor/FileBrowser.vue` → árbol de archivos del proyecto
- `components/editor/AudioControls.vue` → play/pause, seek slider, tiempo actual/total, volumen
- `components/editor/Toolbar.vue` → botones: abrir proyecto, ejecutar script, exportar .osb
- `pages/index.vue` → ensambla todo, instancia composables

## Performance considerations

- PixiJS maneja batch rendering automáticamente
- Los scripts generan datos estáticos (no lógica por frame) — el renderer solo interpola
- Monaco Editor debe ser lazy-loaded (`defineAsyncComponent` o `import()` dinámico)
- Los assets de imagen se leen desde disco bajo demanda via `loadTextures()`
- `resolveStoryboard()` itera todos los sprites por frame — mantener sprites < 500 por script

## Notas

- El usuario (José) trabaja con AdonisJS 6, Nuxt, Vue 3, TypeScript, Tailwind, y PostgreSQL
- Prefiere código completo (no diffs parciales), soluciones production-ready, comunicación directa
- Este es un proyecto personal/side project, no parte de RedCollege
- Usar siempre **enums** en vez de string unions o numeric IDs para tipos del dominio
- TypeScript strict + noUncheckedIndexedAccess activos — usar type guards (`isNonEmpty`) para arrays
- Para verificar tipos: `npx tsc -p .nuxt/tsconfig.app.json --noEmit` (NO `npx tsc --noEmit` a secas)
