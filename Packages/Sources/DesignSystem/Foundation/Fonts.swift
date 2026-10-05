import CoreText
import Foundation

/// The typefaces the app ships, and their registration.
///
/// **Nunito** for text, **Geist Mono** for code. Both are SIL Open Font
/// License (`Fonts/OFL-*.txt`, bundled beside them as the licence requires),
/// which is what makes shipping them inside the binary allowed — a font in the
/// app is a font being redistributed.
///
/// Nunito's round terminals are the soft feel the editor asked for, and it
/// stays legible at 10–11pt, where most of an editor's text lives. Geist read
/// as too neutral; Rubik was tried next and set aside for Nunito. Neither
/// rounded face has a monospaced cut, so code keeps Geist Mono.
///
/// Static weights rather than the variable file: `Font.custom` names a face by
/// its PostScript name, and a static file per weight is a name per weight that
/// can be checked. A variable font leaves the weight to an axis SwiftUI may or
/// may not drive. Upstream only publishes Nunito as a variable font, so the
/// statics are instanced from it with `fonttools varLib.instancer
/// Nunito[wght].ttf wght=<300|400|500|600> --update-name-table`.
public extension Theme {
    enum FontFace {
        public static let light = "Nunito-Light"
        public static let regular = "Nunito-Regular"
        public static let medium = "Nunito-Medium"
        public static let semibold = "Nunito-SemiBold"
        public static let mono = "GeistMono-Regular"

        /// Every face the bundle is expected to provide.
        public static let all = [light, regular, medium, semibold, mono]
    }

    /// Makes the bundled faces available to the process.
    ///
    /// SwiftPM has no `Info.plist` to declare `ATSApplicationFontsPath`, so
    /// nothing registers them on its own — and an unregistered name passed to
    /// `Font.custom` falls back to the system font **without a word**. Call
    /// this before the first view is built; calling it again is harmless.
    ///
    /// Process scope: the faces exist for this app only, never installed on the
    /// user's machine.
    static func registerFonts() {
        guard !fontsRegistered else { return }
        fontsRegistered = true

        let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            // An error here is a face already registered (a second call, or a
            // test after the app) — the only failure that is not a missing
            // file, and the test that looks each face up catches that one.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Whether registration already ran. `nonisolated(unsafe)` because it is set
/// once at launch, before any concurrency exists to race it.
nonisolated(unsafe) private var fontsRegistered = false
