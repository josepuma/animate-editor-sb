import CoreTransferable
import UniformTypeIdentifiers

/// What travels when a filter is dragged out of the library.
///
/// Only the type: the filter itself is a value in the library, and a node is
/// made at the drop site with that lane's defaults. Carrying a whole node would
/// mean a half-configured one existing while it is still in the air.
///
/// ## Why plain text
///
/// The obvious move is a `UTType` of this app's own. It does not work here: an
/// *exported* type has to be declared in the bundle's `Info.plist`, and a
/// SwiftPM executable has no plist to declare it in. The type is then unknown
/// to the system, so a drop destination waiting for it never matches — the drag
/// starts, the ghost follows the pointer, and nothing ever accepts it. That is
/// exactly the shape of the bug this replaced.
///
/// So the payload rides on `.text`, which needs no declaration, with a prefix
/// that says it is ours. A stray piece of text dragged in from elsewhere fails
/// the prefix check and is refused.
struct FilterTransfer: Transferable {
    let type: String

    /// Marks the payload as this app's, so text from anywhere else is ignored.
    private static let marker = "animate-editor.filter:"

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation<FilterTransfer, String>(
            exporting: { "\(marker)\($0.type)" },
            importing: { text in
                guard text.hasPrefix(marker) else {
                    throw FilterTransferError.notAFilter
                }
                return FilterTransfer(type: String(text.dropFirst(marker.count)))
            },
        )
    }

    /// Parses a dropped string, or `nil` when it is not one of ours.
    ///
    /// Exposed so a drop site can filter its own payloads without going through
    /// the transferable machinery, and so the parsing is testable.
    static func parse(_ text: String) -> FilterTransfer? {
        guard text.hasPrefix(marker) else { return nil }
        return FilterTransfer(type: String(text.dropFirst(marker.count)))
    }

    var payload: String { "\(Self.marker)\(type)" }
}

enum FilterTransferError: Error {
    case notAFilter
}

/// What travels when an asset is dragged out of the library.
///
/// Rides on text for the same reason a filter does: a custom `UTType` has to be
/// declared in a bundle's `Info.plist`, and a SwiftPM executable has none, so
/// the type is unknown to the system and no drop destination ever matches it.
struct AssetTransfer: Transferable {
    let path: String

    private static let marker = "animate-editor.asset:"

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation<AssetTransfer, String>(
            exporting: { "\(marker)\($0.path)" },
            importing: { text in
                guard text.hasPrefix(marker) else { throw FilterTransferError.notAFilter }
                return AssetTransfer(path: String(text.dropFirst(marker.count)))
            },
        )
    }

    static func parse(_ text: String) -> AssetTransfer? {
        guard text.hasPrefix(marker) else { return nil }
        return AssetTransfer(path: String(text.dropFirst(marker.count)))
    }

    var payload: String { "\(Self.marker)\(path)" }
}

