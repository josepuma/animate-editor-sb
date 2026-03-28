import { ref, readonly } from 'vue'

export type ProjectFileHandle = {
    name: string
    path: string
    handle: FileSystemFileHandle
}

export type ProjectDirHandle = {
    name: string
    path: string
    handle: FileSystemDirectoryHandle
    children: (ProjectFileHandle | ProjectDirHandle)[]
}

// ─── Composable ──────────────────────────────────────────────────────────────

export function useFileSystem() {
    const rootHandle = ref<FileSystemDirectoryHandle | null>(null)
    const fileTree = ref<ProjectDirHandle | null>(null)
    const isSupported = typeof window !== 'undefined' && 'showDirectoryPicker' in window

    // ── Open project folder ───────────────────────────────────────────────────

    async function openProject(): Promise<boolean> {
        if (!isSupported) {
            console.warn('[useFileSystem] File System Access API not supported')
            return false
        }

        try {
            const handle = await window.showDirectoryPicker({ mode: 'readwrite' })
            rootHandle.value = handle
            fileTree.value = await buildTree(handle, '', true)
            return true
        } catch (err) {
            // User cancelled the picker
            if ((err as DOMException).name !== 'AbortError') console.error(err)
            return false
        }
    }

    // ── File resolution ───────────────────────────────────────────────────────

    /**
     * Resolves a project-relative path (e.g. "sb/logo.png") to a FileSystemFileHandle.
     * Returns null if the file doesn't exist.
     */
    async function getFileHandle(relativePath: string): Promise<FileSystemFileHandle | null> {
        if (!rootHandle.value) return null

        const parts = relativePath.replace(/\\/g, '/').split('/').filter(Boolean)

        // buildTree prefixes paths with the root folder name — skip it since
        // we already start traversal from rootHandle itself.
        const start = parts[0] === rootHandle.value.name ? 1 : 0

        let dir: FileSystemDirectoryHandle = rootHandle.value

        try {
            for (let i = start; i < parts.length - 1; i++) {
                dir = await dir.getDirectoryHandle(parts[i]!)
            }
            const filename = parts[parts.length - 1]
            if (!filename) return null
            return await dir.getFileHandle(filename)
        } catch {
            return null
        }
    }

    /**
     * Reads a text file by project-relative path.
     */
    async function readTextFile(relativePath: string): Promise<string | null> {
        const handle = await getFileHandle(relativePath)
        if (!handle) return null
        const file = await handle.getFile()
        return file.text()
    }

    /**
     * Lists all files in the project matching an extension filter.
     * e.g. listFiles('.png', '.jpg')
     */
    function listFiles(
        ...extensions: string[]
    ): ProjectFileHandle[] {
        if (!fileTree.value) return []
        return collectFiles(fileTree.value, extensions.map(e => e.toLowerCase()))
    }

    /**
     * Writes a text file to a project-relative path, creating intermediate
     * directories as needed.
     */
    /** Re-scans the project folder and updates the file tree. */
    async function refresh(): Promise<void> {
        if (!rootHandle.value) return
        fileTree.value = await buildTree(rootHandle.value, '', true)
    }

    async function writeTextFile(relativePath: string, content: string): Promise<boolean> {
        if (!rootHandle.value) return false

        const parts = relativePath.replace(/\\/g, '/').split('/').filter(Boolean)
        const start = parts[0] === rootHandle.value.name ? 1 : 0

        let dir: FileSystemDirectoryHandle = rootHandle.value

        try {
            for (let i = start; i < parts.length - 1; i++) {
                dir = await dir.getDirectoryHandle(parts[i]!, { create: true })
            }
            const filename = parts[parts.length - 1]
            if (!filename) return false
            const fileHandle = await dir.getFileHandle(filename, { create: true })
            const writable = await fileHandle.createWritable()
            await writable.write(content)
            await writable.close()
            // Refresh the file tree so new files appear in the sidebar
            fileTree.value = await buildTree(rootHandle.value, '', true)
            return true
        } catch (err) {
            console.error('[useFileSystem] writeTextFile failed', err)
            return false
        }
    }

    return {
        isSupported,
        rootHandle: readonly(rootHandle),
        fileTree: readonly(fileTree),
        openProject,
        getFileHandle,
        readTextFile,
        writeTextFile,
        listFiles,
        refresh,
    }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function buildTree(
    handle: FileSystemDirectoryHandle,
    parentPath: string,
    isRoot = false,
): Promise<ProjectDirHandle> {
    // Root node gets path '' so all child paths are truly project-relative
    // (e.g. "scripts/bg.ts" instead of "myProject/scripts/bg.ts").
    const path = isRoot ? '' : (parentPath ? `${parentPath}/${handle.name}` : handle.name)
    const children: (ProjectFileHandle | ProjectDirHandle)[] = []

    // FileSystemDirectoryHandle.values() is part of the File System Access API
    // not yet in the standard TypeScript DOM lib — cast required.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    for await (const entry of (handle as any).values() as AsyncIterable<FileSystemHandle>) {
        if (entry.kind === 'file') {
            children.push({
                name: entry.name,
                path: path ? `${path}/${entry.name}` : entry.name,
                handle: entry as FileSystemFileHandle,
            })
        } else if (entry.kind === 'directory') {
            children.push(await buildTree(entry as FileSystemDirectoryHandle, path))
        }
    }

    // Sort: directories first, then files, both alphabetically
    children.sort((a, b) => {
        const aIsDir = 'children' in a
        const bIsDir = 'children' in b
        if (aIsDir !== bIsDir) return aIsDir ? -1 : 1
        return a.name.localeCompare(b.name)
    })

    return { name: handle.name, path, handle, children }
}

function collectFiles(
    node: ProjectDirHandle,
    extensions: string[],
): ProjectFileHandle[] {
    const result: ProjectFileHandle[] = []

    for (const child of node.children) {
        if ('children' in child) {
            result.push(...collectFiles(child, extensions))
        } else if (!extensions.length || extensions.some(ext => child.name.toLowerCase().endsWith(ext))) {
            result.push(child)
        }
    }

    return result
}
