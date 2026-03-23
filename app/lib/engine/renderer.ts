import { Application, Sprite, Texture, Container } from 'pixi.js'
import type { SpriteRenderState, StoryboardSprite } from '~/types'
import { Origin } from '~/types'
import { prepareStoryboard, resolveStoryboard } from './timeline'
import type { PreparedSprite } from './timeline'

// ─── osu! canvas constants ───────────────────────────────────────────────────

export const OSU_WIDTH = 640
export const OSU_HEIGHT = 480

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

    /** PixiJS sprites keyed by storyboard sprite id */
    private pixiSprites = new Map<string, Sprite>()

    /** Blob URLs created for textures — revoked on destroy */
    private blobUrls = new Map<string, string>()

    /** Textures keyed by sprite filePath */
    private textureCache = new Map<string, Texture>()

    /** Sprite definitions for origin/anchor lookups */
    private spriteIndex = new Map<string, StoryboardSprite>()

    /** Pre-processed sprites for per-frame resolution (O(log n) binary search) */
    private prepared: PreparedSprite[] = []

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
        container.appendChild(this.canvas)
        this.fitToContainer(container)

        const ro = new ResizeObserver(() => this.fitToContainer(container))
        ro.observe(container)
    }

    destroy(): void {
        this.blobUrls.forEach(url => URL.revokeObjectURL(url))
        this.blobUrls.clear()
        this.textureCache.clear()
        this.pixiSprites.clear()
        this.spriteIndex.clear()
        this.prepared = []
        this.app.destroy(true)
    }

    // ── Frame update ──────────────────────────────────────────────────────────

    /**
     * Renders all sprites at the given timestamp (ms).
     * Requires loadSprites() to have been called first.
     */
    render(timeMs: number): void {
        const states = resolveStoryboard(this.prepared, timeMs)
        if (states.length > 0) console.debug('[renderer] render', timeMs.toFixed(0), 'ms →', states.length, 'active sprites')
        const activeIds = new Set(states.map(s => s.spriteId))

        for (const state of states) {
            this.applyState(this.getOrCreateSprite(state.spriteId), state)
        }

        // Hide sprites outside their active window
        this.pixiSprites.forEach((sprite, id) => {
            if (!activeIds.has(id)) sprite.visible = false
        })
    }

    // ── Texture loading ───────────────────────────────────────────────────────

    /**
     * Loads textures for a list of sprites.
     * `getFileHandle` resolves a project-relative path to a FileSystemFileHandle.
     */
    async loadTextures(
        sprites: StoryboardSprite[],
        getFileHandle: (path: string) => Promise<FileSystemFileHandle | null>,
    ): Promise<void> {
        this.prepared = prepareStoryboard(sprites)

        for (const sprite of sprites) {
            this.spriteIndex.set(sprite.id, sprite)
            if (this.blobUrls.has(sprite.filePath)) continue

            const handle = await getFileHandle(sprite.filePath)
            if (!handle) {
                console.warn('[renderer] file not found:', sprite.filePath)
                continue
            }

            const file = await handle.getFile()
            const blobUrl = URL.createObjectURL(file)
            this.blobUrls.set(sprite.filePath, blobUrl)

            console.debug('[renderer] loading texture', sprite.filePath)
            try {
                const texture = await loadTextureFromUrl(blobUrl)
                this.textureCache.set(sprite.filePath, texture)
                console.debug('[renderer] texture ok', sprite.filePath, texture.width, 'x', texture.height)
            } catch (err) {
                console.warn('[renderer] texture failed', sprite.filePath, err)
            }
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

        this.stage.addChild(pixiSprite)
        this.pixiSprites.set(spriteId, pixiSprite)
        return pixiSprite
    }

    private applyState(sprite: Sprite, state: SpriteRenderState): void {
        sprite.visible = state.visible
        sprite.x = state.x
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

    /** Scales the canvas to fill the container while preserving 4:3 ratio. */
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
