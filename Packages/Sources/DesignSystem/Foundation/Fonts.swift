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
/// Nunito[wght].ttf wght=<300|400|500|600|700> --update-name-table`.
public extension Theme {
    enum FontFace {
        public static let light = "Nunito-Light"
        public static let regular = "Nunito-Regular"
        public static let medium = "Nunito-Medium"
        public static let semibold = "Nunito-SemiBold"
        /// Only the featured title uses it: Bold everywhere would shout.
        public static let bold = "Nunito-Bold"
        public static let mono = "GeistMono-Regular"

        /// Every face the bundle is expected to provide.
        public static let all = [light, regular, medium, semibold, bold, mono]
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
        _ = fontRegistration
    }

    /// The registration itself, run exactly once.
    ///
    /// A lazy `static let` rather than a flag: Swift initialises one exactly
    /// once and makes every other caller **wait** until it has finished. The
    /// flag this replaced was set before the work began, so a second caller —
    /// two tests running in parallel — saw it set, returned at once, and
    /// looked up a face that was still being registered. Some faces were
    /// found and some were not, from one run to the next.
    private static let fontRegistration: Void = {
        let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            // An error here is a face already registered (a test after the
            // app, say) — the only failure that is not a missing file, and the
            // test that looks each face up catches that one.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}
