import CoreServices
import Foundation
import StoryboardCore

/// Watches a project folder and reports the scripts that change in it.
///
/// The **folder**, never the files. An editor saves atomically — it writes a
/// temporary and renames it over the target — so a descriptor held on the
/// script goes permanently deaf after the first save, and the failure mode
/// looks exactly like success: the watcher is running, reporting nothing,
/// forever.
///
/// Verified with a real stream before this was written. All three save shapes
/// produce an event naming the **final** path:
///
/// | Save | Flags on `script.js` |
/// |---|---|
/// | Direct, in place | `created, modified, isFile` |
/// | Temp then rename | `renamed, isFile` — **twice** |
/// | Delete | `removed, renamed, isFile` |
///
/// The doubled rename is why `ScriptChangeCoalescer` exists, and the temporary
/// arriving under its own name is why it filters.
public final class ScriptFolderStream {
    private var stream: FSEventStreamRef?
    private let coalescer: ScriptChangeCoalescer
    private let report: @Sendable ([ScriptFile]) -> Void

    /// How long a burst is given to finish.
    ///
    /// Long enough to absorb one save's two events and short enough that the
    /// canvas still feels like it reloads on ⌘S.
    public static let coalescingInterval: TimeInterval = 0.12

    /// Starts watching `folder`, or does nothing if a stream cannot be made.
    ///
    /// Failing quietly rather than throwing: a folder that cannot be watched
    /// costs automatic reload, which is a degraded editor and not a broken
    /// one — the author can still reload by hand. Throwing here would mean a
    /// project that refuses to open because of a filesystem the app does not
    /// control.
    public init(folder: URL, report: @escaping @Sendable ([ScriptFile]) -> Void) {
        self.report = report
        coalescer = ScriptChangeCoalescer(interval: Self.coalescingInterval)

        // Retained unmanaged and released in `stop`: the C callback gets a raw
        // pointer, so something has to keep this object alive for as long as
        // the stream can call back into it.
        let context = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        var streamContext = FSEventStreamContext(
            version: 0,
            info: context,
            retain: nil,
            release: nil,
            copyDescription: nil,
        )

        // `FileEvents` is what makes an event name a file rather than the
        // folder — without it every save reports the directory and there is
        // nothing to tell one script from another. `NoDefer` reports the
        // first event immediately rather than at the end of the window, so a
        // single save is not held for the full latency.
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer,
        )

        guard let created = FSEventStreamCreate(
            nil,
            { _, info, count, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<ScriptFolderStream>.fromOpaque(info)
                    .takeUnretainedValue()
                // `assumingMemoryBound`, not `unsafeBitCast`: the callback
                // contract says this points at an array of C strings, so
                // saying so is the honest spelling — and it leaves no warning
                // behind. This project has already lost a runaway guard to a
                // warning nobody read.
                let names = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                let changed = (0 ..< count).map { index in
                    (String(cString: names[index]) as NSString).lastPathComponent
                }
                watcher.received(changed)
            },
            &streamContext,
            [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.coalescingInterval / 2,
            flags,
        ) else {
            Unmanaged<ScriptFolderStream>.fromOpaque(context).release()
            return
        }

        stream = created
        FSEventStreamSetDispatchQueue(created, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(created)
    }

    /// Stops watching. Safe to call more than once.
    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        Unmanaged.passUnretained(self).release()
    }

    deinit {
        // Not `stop()`: releasing the retain here would be releasing the one
        // keeping `self` alive, inside its own deinit.
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func received(_ names: [String]) {
        // The actor and the callback are captured as values, not `self`.
        //
        // Capturing `self` makes the closure non-`Sendable` — it would carry a
        // reference to a class the C callback also touches, which is the data
        // race the compiler is right to refuse. Both of these are already safe
        // to hand across: one is an actor, the other is `@Sendable`.
        let coalescer = coalescer
        let report = report
        Task { await coalescer.handle(names, report: report) }
    }
}
