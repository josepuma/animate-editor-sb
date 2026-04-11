import type { StoryboardSprite, Command, Storyboard, TextSpriteMap } from '~/types'
import { TEXT_SPRITE_PREFIX } from '~/types'
import { rasterizeChar, mergeStyle } from '~/lib/scripting/textRasterizer'

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Serializes a Storyboard to the osu! .osb file format.
 * Returns the full file contents as a string.
 */
export function exportOsb(storyboard: Storyboard): string {
    const lines: string[] = []

    lines.push('[Events]')
    lines.push('//Background and Video events')
    lines.push('//Storyboard Layer 0 (Background)')

    const byLayer = groupByLayer(storyboard.sprites)

    appendLayer(lines, byLayer.Background ?? [], '//Storyboard Layer 0 (Background)')
    appendLayer(lines, byLayer.Fail ?? [], '//Storyboard Layer 1 (Fail)')
    appendLayer(lines, byLayer.Pass ?? [], '//Storyboard Layer 2 (Pass)')
    appendLayer(lines, byLayer.Foreground ?? [], '//Storyboard Layer 3 (Foreground)')
    appendLayer(lines, byLayer.Overlay ?? [], '//Storyboard Layer 4 (Overlay)')

    if (storyboard.variables && Object.keys(storyboard.variables).length) {
        lines.push('')
        lines.push('[Variables]')
        for (const [key, value] of Object.entries(storyboard.variables)) {
            lines.push(`${key}=${value}`)
        }
    }

    return lines.join('\n')
}

/**
 * Triggers a browser download of the .osb file.
 */
export function downloadOsb(storyboard: Storyboard, filename = 'storyboard.osb'): void {
    const content = exportOsb(storyboard)
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    a.click()
    URL.revokeObjectURL(url)
}

/**
 * Writes the .osb file directly to the user's project folder
 * via the File System Access API.
 * If `textSpriteMap` is provided, rasterizes text sprites to PNG files under
 * `sb/_text/` before writing the .osb, and remaps their synthetic filePaths.
 */
export async function saveOsb(
    storyboard: Storyboard,
    rootHandle: FileSystemDirectoryHandle,
    filename = 'storyboard.osb',
    textSpriteMap: TextSpriteMap = {},
): Promise<void> {
    const pathMap = await prepareTextSprites(textSpriteMap, rootHandle)

    // Remap text sprite filePaths to their real on-disk paths
    const remappedSprites = storyboard.sprites.map((sprite) => {
        if (sprite.filePath.startsWith(TEXT_SPRITE_PREFIX)) {
            const realPath = pathMap[sprite.filePath]
            if (realPath) return { ...sprite, filePath: realPath }
        }
        return sprite
    })

    const content = exportOsb({ ...storyboard, sprites: remappedSprites })
    const fileHandle = await rootHandle.getFileHandle(filename, { create: true })
    const writable = await fileHandle.createWritable()
    await writable.write(content)
    await writable.close()
}

// ─── Text sprite preparation ──────────────────────────────────────────────────

/**
 * Rasterizes all text sprite definitions to PNG files under `sb/_text/`.
 * Returns a map from synthetic filePath key → real relative path.
 * Skips files that already exist on disk (idempotent re-export).
 */
async function prepareTextSprites(
    textSpriteMap: TextSpriteMap,
    rootHandle: FileSystemDirectoryHandle,
): Promise<Record<string, string>> {
    const pathMap: Record<string, string> = {}
    const entries = Object.entries(textSpriteMap)
    if (entries.length === 0) return pathMap

    // Ensure sb/_text/ directory exists
    const sbDir = await rootHandle.getDirectoryHandle('sb', { create: true })
    const textDir = await sbDir.getDirectoryHandle('_text', { create: true })

    for (const [key, def] of entries) {
        const hash = key.slice(TEXT_SPRITE_PREFIX.length)
        const fileName = `${hash}.png`
        const relativePath = `sb/_text/${fileName}`
        pathMap[key] = relativePath

        // Skip if already written
        try {
            await textDir.getFileHandle(fileName)
            continue
        } catch {
            // File does not exist — proceed to write
        }

        const canvas = rasterizeChar(def.char, mergeStyle(def.style))
        const blob = await canvas.convertToBlob({ type: 'image/png' })

        const fileHandle = await textDir.getFileHandle(fileName, { create: true })
        const writable = await fileHandle.createWritable()
        await writable.write(blob)
        await writable.close()
    }

    return pathMap
}

// ─── Internals ────────────────────────────────────────────────────────────────

type LayerMap = Partial<Record<string, StoryboardSprite[]>>

function groupByLayer(sprites: StoryboardSprite[]): LayerMap {
    const map: LayerMap = {}
    for (const sprite of sprites) {
        const layer = sprite.layer as string
            ; (map[layer] ??= []).push(sprite)
    }
    return map
}

function appendLayer(lines: string[], sprites: StoryboardSprite[], comment: string): void {
    lines.push(comment)
    for (const sprite of sprites) {
        lines.push(serializeSprite(sprite))
    }
}

function serializeSprite(sprite: StoryboardSprite): string {
    const lines: string[] = []

    // Header line
    lines.push(`Sprite,${sprite.layer},${sprite.origin},"${sprite.filePath}",${sprite.defaultX},${sprite.defaultY}`)

    // Commands
    for (const cmd of sprite.commands) {
        lines.push(` ${serializeCommand(cmd)}`)
    }

    return lines.join('\n')
}

function serializeCommand(cmd: Command): string {
    const e = cmd.easing
    const t0 = cmd.startTime
    const t1 = cmd.endTime

    switch (cmd.type) {
        case 'F':
            return `_F,${e},${t0},${t1},${fmt(cmd.startOpacity)},${fmt(cmd.endOpacity)}`

        case 'M':
            return `_M,${e},${t0},${t1},${fmt(cmd.startX)},${fmt(cmd.startY)},${fmt(cmd.endX)},${fmt(cmd.endY)}`

        case 'MX':
            return `_MX,${e},${t0},${t1},${fmt(cmd.startX)},${fmt(cmd.endX)}`

        case 'MY':
            return `_MY,${e},${t0},${t1},${fmt(cmd.startY)},${fmt(cmd.endY)}`

        case 'S':
            return `_S,${e},${t0},${t1},${fmt(cmd.startScale)},${fmt(cmd.endScale)}`

        case 'V':
            return `_V,${e},${t0},${t1},${fmt(cmd.startX)},${fmt(cmd.startY)},${fmt(cmd.endX)},${fmt(cmd.endY)}`

        case 'R':
            return `_R,${e},${t0},${t1},${fmt(cmd.startAngle)},${fmt(cmd.endAngle)}`

        case 'C':
            return `_C,${e},${t0},${t1},${Math.round(cmd.startR)},${Math.round(cmd.startG)},${Math.round(cmd.startB)},${Math.round(cmd.endR)},${Math.round(cmd.endG)},${Math.round(cmd.endB)}`

        case 'P':
            return `_P,${e},${t0},${t1},${cmd.parameter}`

        default:
            return ''
    }
}

/** Formats a float: omits decimal if it's a whole number. */
function fmt(n: number): string {
    return Number.isInteger(n) ? String(n) : n.toFixed(3).replace(/\.?0+$/, '')
}
