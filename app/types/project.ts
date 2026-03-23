import type { Storyboard } from './storyboard'

export interface ProjectConfig {
  name: string
  audioFile: string
  /** osu! canvas resolution */
  width: 640
  height: 480
  /** BPM used by the scripting API */
  bpm: number
  /** Audio offset in milliseconds */
  offset: number
}

export interface Project {
  config: ProjectConfig
  /** Root directory handle (File System Access API) */
  rootHandle: FileSystemDirectoryHandle | null
  storyboard: Storyboard
}
