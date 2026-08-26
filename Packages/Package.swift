// swift-tools-version: 6.0
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────────
//  Architecture
//
//  Dependencies point inwards. A layer may depend on the layers above it in
//  this list, never below:
//
//    Core        StoryboardCore — parsing, animation resolution, types.
//                No platform frameworks, so it is testable without a GPU or a
//                window. This is the layer that must stay clean.
//
//    Platform    StoryboardShaderTypes, StoryboardRendering, DesignSystem.
//                Talks to Metal, AppKit and SwiftUI on the core's behalf.
//
//    Features    PlaybackFeature, and later Scripting, Exporting, …
//                One vertical slice per product capability: its own domain
//                logic, its own UI, its own tests. Features never import each
//                other — when two need to share, the shared part belongs in
//                Core behind a protocol.
//
//    Apps        RendererHarness today; the shipping app later.
//                Composition only: windows, menus, wiring.
// ─────────────────────────────────────────────────────────────────────────────

let package = Package(
    name: "AnimateEditor",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "StoryboardCore", targets: ["StoryboardCore"]),
        .library(name: "StoryboardRendering", targets: ["StoryboardRendering"]),
        .library(name: "StoryboardPersistence", targets: ["StoryboardPersistence"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "PlaybackFeature", targets: ["PlaybackFeature"]),
        .library(name: "ProjectBrowserFeature", targets: ["ProjectBrowserFeature"]),
        .library(name: "EditorShellFeature", targets: ["EditorShellFeature"]),
        .executable(name: "AnimateEditor", targets: ["AnimateEditorApp"]),
        .executable(name: "RendererHarness", targets: ["RendererHarness"]),
    ],
    targets: [
        // ── Core ────────────────────────────────────────────────────────────
        .target(
            name: "StoryboardCore",
        ),
        .testTarget(
            name: "StoryboardCoreTests",
            dependencies: ["StoryboardCore"],
            resources: [.copy("Fixtures")],
        ),

        // ── Platform ────────────────────────────────────────────────────────

        // C struct definitions shared between Swift and the Metal shaders, so
        // both sides agree on memory layout.
        .target(
            name: "StoryboardShaderTypes",
        ),

        // `Shaders.metal` is copied verbatim, not compiled: SwiftPM has no Metal
        // compilation step, so the renderer builds the library from source at
        // startup. See MetalStoryboardRenderer.makeLibrary(device:).
        .target(
            name: "StoryboardRendering",
            dependencies: ["StoryboardCore", "StoryboardShaderTypes"],
            resources: [.copy("Shaders.metal")],
        ),
        .testTarget(
            name: "StoryboardRenderingTests",
            dependencies: ["StoryboardRendering", "StoryboardShaderTypes"],
            resources: [.copy("../../Sources/StoryboardRendering/Shaders.metal")],
        ),

        // Reading beatmap folders and remembering which ones were opened.
        .target(
            name: "StoryboardPersistence",
            dependencies: ["StoryboardCore"],
        ),
        .testTarget(
            name: "StoryboardPersistenceTests",
            dependencies: ["StoryboardPersistence"],
        ),

        .target(
            name: "DesignSystem",
        ),

        // ── Features ────────────────────────────────────────────────────────
        .target(
            name: "PlaybackFeature",
            dependencies: [
                "StoryboardCore",
                "StoryboardRendering",
                "StoryboardPersistence",
                "DesignSystem",
            ],
        ),
        .target(
            name: "ProjectBrowserFeature",
            dependencies: ["StoryboardPersistence", "DesignSystem"],
        ),

        // Arrangement only: panels, rail, track timeline. The canvas and
        // transport are injected, so this target knows nothing about rendering
        // or playback.
        .target(
            name: "EditorShellFeature",
            dependencies: ["StoryboardCore", "DesignSystem"],
        ),
        .testTarget(
            name: "EditorShellFeatureTests",
            dependencies: ["EditorShellFeature", "StoryboardCore"],
        ),

        // ── Apps ────────────────────────────────────────────────────────────

        // The shipping app. Composition only: it wires features together and
        // owns the window.
        .executableTarget(
            name: "AnimateEditorApp",
            dependencies: ["PlaybackFeature", "ProjectBrowserFeature", "EditorShellFeature"],
        ),

        // Development harness: runs the renderer against a generated storyboard
        // so rendering work needs no beatmap folder on disk.
        .executableTarget(
            name: "RendererHarness",
            dependencies: ["StoryboardCore", "StoryboardRendering", "PlaybackFeature"],
        ),
    ],
)
