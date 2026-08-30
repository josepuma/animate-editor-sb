import StoryboardCore
import Testing

@testable import EditorShellFeature

/// The payload a filter drag carries.
///
/// It rides on plain text rather than a `UTType` of this app's own, because an
/// *exported* type has to be declared in a bundle's `Info.plist` and a SwiftPM
/// executable has none. The type is then unknown to the system, and a drop
/// destination waiting for it never matches — the drag starts, the ghost
/// follows the pointer, and nothing accepts it.
@Suite("Filter transfer")
struct FilterTransferTests {
    @Test("a payload round-trips")
    func roundTrip() {
        let sent = FilterTransfer(type: "glow")
        let received = FilterTransfer.parse(sent.payload)

        #expect(received?.type == "glow")
    }

    /// Text dragged in from anywhere else must not apply a filter.
    @Test("unrelated text is refused")
    func unrelatedTextIsRefused() {
        #expect(FilterTransfer.parse("glow") == nil)
        #expect(FilterTransfer.parse("") == nil)
        #expect(FilterTransfer.parse("https://example.com") == nil)
    }

    @Test("every library filter survives the trip", arguments: FilterLibrary.standard.descriptors)
    func libraryFiltersRoundTrip(descriptor: FilterDescriptor) {
        let payload = FilterTransfer(type: descriptor.type).payload

        #expect(FilterTransfer.parse(payload)?.type == descriptor.type)
        #expect(FilterLibrary.standard.descriptor(for: descriptor.type) != nil)
    }
}
