export interface Color {
    r: number;
    g: number;
    b: number;
}

export interface GradientStep {
    pos: number;
    color: Color;
}

/**
 * Converts a hex color string to a Color object.
 * Accepts #RGB and #RRGGBB formats, with or without the leading #.
 */
export const hex = (value: string): Color => {
    const v = value.startsWith('#') ? value.slice(1) : value
    if (v.length === 3) {
        const r = parseInt(v[0]! + v[0]!, 16)
        const g = parseInt(v[1]! + v[1]!, 16)
        const b = parseInt(v[2]! + v[2]!, 16)
        return { r, g, b }
    }
    const r = parseInt(v.slice(0, 2), 16)
    const g = parseInt(v.slice(2, 4), 16)
    const b = parseInt(v.slice(4, 6), 16)
    return { r, g, b }
}

/**
 * Converts HSL values to a Color object.
 * @param h - Hue in degrees [0, 360]
 * @param s - Saturation percentage [0, 100]
 * @param l - Lightness percentage [0, 100]
 */
export const hsl = (h: number, s: number, l: number): Color => {
    const sn = s / 100
    const ln = l / 100
    const a = sn * Math.min(ln, 1 - ln)
    const channel = (n: number): number => {
        const k = (n + h / 30) % 12
        return Math.round((ln - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))) * 255)
    }
    return { r: channel(0), g: channel(8), b: channel(4) }
}
