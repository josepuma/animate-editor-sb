import PlaybackFeature
import ProjectBrowserFeature
import SwiftUI

/// Switches between the two features.
///
/// Neither feature knows the other exists — the browser reports a folder, this
/// view decides what happens next. That is what keeps features independent.
struct AppRootView: View {
    @State private var openFolder: URL?
    @State private var loadFailure: String?

    var body: some View {
        Group {
            if let source = playbackSource {
                EditorWindow(source: source)
                    .toolbar { closeButton }
            } else {
                ProjectBrowserView { url in
                    openFolder = url
                }
            }
        }
        // The canvas is black by osu!'s convention, so the chrome around it is
        // dark by nature; a light appearance would frame it in pale panels.
        .preferredColorScheme(.dark)
        .alert(
            "Could not load that storyboard",
            isPresented: Binding(
                get: { loadFailure != nil },
                set: { if !$0 { loadFailure = nil } },
            ),
        ) {
            Button("OK", role: .cancel) {
                loadFailure = nil
                openFolder = nil
            }
        } message: {
            Text(loadFailure ?? "")
        }
    }

    /// The browser has already validated the folder, so a failure here means
    /// it changed on disk in between.
    private var playbackSource: BeatmapStoryboardSource? {
        guard let openFolder else { return nil }
        do {
            return try BeatmapStoryboardSource(folderURL: openFolder)
        } catch {
            Task { @MainActor in loadFailure = String(describing: error) }
            return nil
        }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                openFolder = nil
            } label: {
                Label("Close", systemImage: "chevron.left")
            }
            .help("Back to projects")
        }
    }
}
