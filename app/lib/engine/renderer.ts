import { Application, Sprite, Texture, Container, Text } from 'pixi.js'
import type { SpriteRenderState, StoryboardSprite } from '~/types'
import { Origin, Layer } from '~/types'
import { prepareStoryboard, resolveStoryboard } from './timeline'
import type { PreparedSprite } from './timeline'

// ─── osu! canvas constants (16:9) ────────────────────────────────────────────
//
// Storyboard coordinate space: x ∈ [-107, 747], y ∈ [0, 480], centre = (320, 240)
// Canvas pixel space:          x ∈ [0,    854], y ∈ [0, 480]
// Conversion: canvas_x = storyboard_x + OSU_X_OFFSET

export const OSU_WIDTH    = 854   // 16:9 storyboard canvas width
export const OSU_HEIGHT   = 480
export const OSU_X_OFFSET = 107   // storyboard origin → canvas origin

// ─── Layer render order (bottom → top) ───────────────────────────────────────

const LAYER_RENDER_ORDER: Record<Layer, number> = {
    [Layer.Background]: 0,
    [Layer.Fail]:       1,
    [Layer.Pass]:       2,
    [Layer.Foreground]: 3,
    [Layer.Overlay]:    4,
}

// ─── Origin → PixiJS anchor ──────────────────────────────────────────────────

const ORIGIN_ANCHOR: Record<Origin, [number, number]> = {
    [Origin.TopLeft]: [0, 0],
    [Origin.TopCentre]: [0.5, 0],
    [Origin.TopRight]: [1, 0],
    [Origin.CentreLeft]: [0, 0.5],
    [Origin.Centre]: [0.5, 0.5],
    [Origin.CentreRight]: [1, 0.5],
    [Origin.BottomLeft]: [0, 1],
    [Origin.BottomCentre]: [0.5, 1],
    [Origin.BottomRight]: [1, 1],
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function loadTextureFromUrl(url: string): Promise<Texture> {
    return new Promise((resolve, reject) => {
        const img = new Image()
        img.onload = () => resolve(Texture.from(img))
        img.onerror = () => reject(new Error(`Failed to load image: ${url}`))
        img.src = url
    })
}

// ─── Renderer ────────────────────────────────────────────────────────────────

export class StoryboardRenderer {
    private app!: Application
    private stage!: Container
    /** Child container for storyboard sprites — always below the overlay layer */
    private spritesLayer!: Container

    /** PixiJS sprites keyed by storyboard sprite id */
    private pixiSprites = new Map<string, Sprite>()

    /** Blob URLs created for textures — revoked on destroy */
    private blobUrls = new Map<string, string>()

    /** Textures keyed by sprite filePath */
    private textureCache = new Map<string, Texture>()

    /** Sprite definitions for origin/anchor lookups */
    private spriteIndex = new Map<string, StoryboardSprite>()

    /** Pre-processed sprites for per-frame resolution */
    private prepared: PreparedSprite[] = []

    /** FPS overlay */
    private fpsText!: Text
    private fpsSmooth = 60
    private lastRenderTime = 0

    get canvas(): HTMLCanvasElement {
        return this.app.canvas as HTMLCanvasElement
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    async init(container: HTMLElement): Promise<void> {
        this.app = new Application()

        await this.app.init({
            width: OSU_WIDTH,
            height: OSU_HEIGHT,
            backgroundColor: 0x000000,
            antialias: true,
            autoDensity: true,
            resolution: window.devicePixelRatio || 1,
        })

        this.stage = this.app.stage
        this.spritesLayer = new Container()
        this.stage.addChild(this.spritesLayer) // layer 0: storyboard sprites
        container.appendChild(this.canvas)
        this.fitToContainer(container)

        this.fpsText = new Text({
            text: '',
            style: { fontFamily: 'monospace', fontSize: 14, fill: 0xffffff, stroke: { color: 0x000000, width: 3 } },
        })
        this.fpsText.x = 6
        this.fpsText.y = 6
        this.fpsText.visible = false
        this.stage.addChild(this.fpsText) // layer 1: always on top

        const ro = new ResizeObserver(() => this.fitToContainer(container))
        ro.observe(container)
    }

    toggleFps(): void {
        this.fpsText.visible = !this.fpsText.visible
        if (!this.fpsText.visible) this.lastRenderTime = 0
    }

    /**
     * Clears all sprites, textures and blob URLs without destroying the PixiJS app.
     * Call before loading a new project to prevent the texture cache bleeding across projects.
     */
    reset(): void {
        this.pixiSprites.forEach(s => { this.spritesLayer.removeChild(s); s.destroy() })
        this.pixiSprites.clear()
        this.spriteIndex.clear()
        this.blobUrls.forEach(url => URL.revokeObjectURL(url))
        this.blobUrls.clear()
        this.textureCache.forEach(t => t.destroy())
        this.textureCache.clear()
        this.prepared = []
    }

    destroy(): void {
        this.reset()
        this.app.destroy(true)
    }

    // ── Frame update ──────────────────────────────────────────────────────────

    /**
     * Renders all sprites at the given timestamp (ms).
     * Requires loadSprites() to have been called first.
     */
    render(timeMs: number): void {
        if (this.fpsText.visible) {
            const now = performance.now()
            if (this.lastRenderTime > 0) {
                const instant = 1000 / (now - this.lastRenderTime)
                this.fpsSmooth = this.fpsSmooth * 0.85 + instant * 0.15
                this.fpsText.text = `${this.fpsSmooth.toFixed(0)} fps`
            }
            this.lastRenderTime = now
        }

        const states = resolveStoryboard(this.prepared, timeMs)
        const activeIds = new Set(states.map(s => s.spriteId))

        for (const state of states) {
            this.applyState(this.getOrCreateSprite(state.spriteId), state)
        }

        // Hide sprites outside their active window
        this.pixiSprites.forEach((sprite, id) => {
            if (!activeIds.has(id)) sprite.visible = false
        })
    }

    // ── Reorder (same sprites, new order) ─────────────────────────────────────

    /**
     * Re-orders the display list without loading new textures.
     * Use when the same sprites are present but their render order changed.
     * Synchronous and non-blocking.
     */
    reorder(sprites: StoryboardSprite[]): void {
        this.prepared = prepareStoryboard(sprites)
        const sorted = [...sprites].sort((a, b) =>
            LAYER_RENDER_ORDER[a.layer] - LAYER_RENDER_ORDER[b.layer]
        )
        for (const s of sorted) {
            const ps = this.pixiSprites.get(s.id)
            if (ps) this.spritesLayer.addChild(ps)
        }
    }

    // ── Sprite update (incremental) ───────────────────────────────────────────

    /**
     * Incrementally updates sprites and textures.
     * - Only loads file paths not already in the texture cache (no reload of unchanged images).
     * - Removes PixiJS sprites for IDs no longer present.
     * - Re-orders the display list to match layer order.
     * Does NOT clear existing sprites/textures — call reset() first for a full project change.
     */
    async updateSprites(
        sprites: StoryboardSprite[],
        getFileHandle: (path: string) => Promise<FileSystemFileHandle | null>,
    ): Promise<void> {
        // 1. Rebuild sprite index
        this.spriteIndex.clear()
        for (const sprite of sprites) {
            this.spriteIndex.set(sprite.id, sprite)
        }

        // 2. Load only file paths not already cached
        const seenPaths = new Set<string>()
        for (const sprite of sprites) {
            if (seenPaths.has(sprite.filePath) || this.textureCache.has(sprite.filePath)) {
                seenPaths.add(sprite.filePath)
                continue
            }
            seenPaths.add(sprite.filePath)
            const handle = await getFileHandle(sprite.filePath)
            if (!handle) {
                console.warn('[renderer] file not found:', sprite.filePath)
                continue
            }
            const file = await handle.getFile()
            const blobUrl = URL.createObjectURL(file)
            this.blobUrls.set(sprite.filePath, blobUrl)
            try {
                const texture = await loadTextureFromUrl(blobUrl)
                this.textureCache.set(sprite.filePath, texture)
            } catch (err) {
                console.warn('[renderer] texture failed', sprite.filePath, err)
            }
        }

        // 3. Remove PixiJS sprites for IDs no longer in the list
        const activeIds = new Set(sprites.map(s => s.id))
        for (const [id, pSprite] of [...this.pixiSprites]) {
            if (!activeIds.has(id)) {
                this.spritesLayer.removeChild(pSprite)
                pSprite.destroy()
                this.pixiSprites.delete(id)
            }
        }

        // 4. Update timeline data
        this.prepared = prepareStoryboard(sprites)

        // 5. Ensure all sprites have correct texture + anchor, sorted by layer
        const sorted = [...sprites].sort((a, b) =>
            LAYER_RENDER_ORDER[a.layer] - LAYER_RENDER_ORDER[b.layer]
        )
        for (const sprite of sorted) {
            const pixiSprite = this.getOrCreateSprite(sprite.id)
            const texture = this.textureCache.get(sprite.filePath) ?? Texture.EMPTY
            pixiSprite.texture = texture
            const anchor = ORIGIN_ANCHOR[sprite.origin]
            pixiSprite.anchor.set(anchor[0], anchor[1])
        }

        // 6. Re-order display list to match layer sort
        //    addChild on an existing child moves it to the end — calling in sorted order re-sorts.
        for (const sprite of sorted) {
            const pixiSprite = this.pixiSprites.get(sprite.id)
            if (pixiSprite) this.spritesLayer.addChild(pixiSprite)
        }
    }

    // ── Internals ─────────────────────────────────────────────────────────────

    private getOrCreateSprite(spriteId: string): Sprite {
        const cached = this.pixiSprites.get(spriteId)
        if (cached) return cached

        const def = this.spriteIndex.get(spriteId)
        const texture = (def && this.textureCache.get(def.filePath)) ?? Texture.EMPTY
        const anchor = def ? ORIGIN_ANCHOR[def.origin] : ORIGIN_ANCHOR[Origin.Centre]

        const pixiSprite = new Sprite(texture)
        pixiSprite.anchor.set(anchor[0], anchor[1])
        pixiSprite.visible = false // hidden until first render

        this.spritesLayer.addChild(pixiSprite)
        this.pixiSprites.set(spriteId, pixiSprite)
        return pixiSprite
    }

    private applyState(sprite: Sprite, state: SpriteRenderState): void {
        sprite.visible = state.visible
        sprite.x = state.x + OSU_X_OFFSET
        sprite.y = state.y
        sprite.alpha = state.opacity
        sprite.rotation = state.rotation
        sprite.tint = (state.r << 16) | (state.g << 8) | state.b

        sprite.scale.set(
            state.flipH ? -state.scaleX : state.scaleX,
            state.flipV ? -state.scaleY : state.scaleY,
        )

        sprite.blendMode = state.additive ? 'add' : 'normal'
    }

    /** Scales the canvas to fill the container while preserving 16:9 ratio. */
    private fitToContainer(container: HTMLElement): void {
        const { clientWidth: w, clientHeight: h } = container
        const scale = Math.min(w / OSU_WIDTH, h / OSU_HEIGHT)
        const cw = OSU_WIDTH * scale
        const ch = OSU_HEIGHT * scale

        this.canvas.style.position = 'absolute'
        this.canvas.style.left = `${(w - cw) / 2}px`
        this.canvas.style.top = `${(h - ch) / 2}px`
        this.canvas.style.width = `${cw}px`
        this.canvas.style.height = `${ch}px`
    }
}
