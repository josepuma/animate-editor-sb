import type { StoryboardSprite } from './sprite'

export interface Storyboard {
    sprites: StoryboardSprite[]
    /** .osb [Variables] section */
    variables?: Record<string, string>
}
