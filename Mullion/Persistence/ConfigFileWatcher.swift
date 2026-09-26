import CoreServices
import Foundation
import os

/// FSEvents wrapper that calls `onChange` on the main queue when files in
/// the watched directory change. Coalesces bursts of file-system events
/// (atomic writes show up as multiple events on a temp + rename pair) into
/// a single callback via a trailing debounce.
///
/// Loop safety with `JSONStore`: our own writes fire FSEvents, the callback
/// triggers a reload, but `JSONStore.reload()` only reads from disk — it
/// doesn't itself write. The cycle terminates.
///
/// Only configuration edits trigger a reload — see
/// `shouldReload(forChangedPaths:flags:watchedDirectory:)`.
final class ConfigFileWatcher {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "config-watcher")

    private var stream: FSEventStreamRef?
    private var debouncer: DispatchWorkItem?
    private let onChange: () -> Void
    private let debounceInterval: TimeInterval
    private let weakBox: WeakBox
    private var boxRef: Unmanaged<WeakBox>?

    /// Heap-allocated weak ref. The FSEvents C callback unwraps this and
    /// asks for `.watcher`, which will be `nil` after the watcher's `deinit`
    /// — defusing the race where a callback enqueued on the main queue
    /// fires after the watcher itself has been freed.
    private final class WeakBox {
        weak var watcher: ConfigFileWatcher?
        let directoryPath: String
        init(directoryPath: String) { self.directoryPath = directoryPath }
    }

    init?(directory: URL,
          debounceInterval: TimeInterval = 0.25,
          onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.debounceInterval = debounceInterval
        self.weakBox = WeakBox(directoryPath: directory.path)

        let boxRef = Unmanaged.passRetained(weakBox)
        self.boxRef = boxRef

        let paths = [directory.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: boxRef.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info else { return }
            let box = Unmanaged<WeakBox>.fromOpaque(info).takeUnretainedValue()
            // `kFSEventStreamCreateFlagUseCFTypes` below makes `eventPaths`
            // a CFArray of CFString.
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths)
                .takeUnretainedValue() as? [String] ?? []
            let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
            guard ConfigFileWatcher.shouldReload(forChangedPaths: paths,
                                                 flags: flags,
                                                 watchedDirectory: box.directoryPath)
            else { return }
            box.watcher?.scheduleFire()
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05, // FSEvents-internal coalescing latency (s)
            UInt32(kFSEventStreamCreateFlagFileEvents
                   | kFSEventStreamCreateFlagNoDefer
                   | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            log.error("FSEventStreamCreate failed for \(directory.path, privacy: .public)")
            boxRef.release()
            self.boxRef = nil
            return nil
        }
        self.stream = stream
        weakBox.watcher = self
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        log.notice("watching \(directory.path, privacy: .public)")
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        debouncer?.cancel()
        // Box outlives us by design — releases the retained reference now
        // that the stream is invalidated. The C callback can still fire
        // briefly afterward; the box's `watcher` weak ref is already nil,
        // so `box.watcher?.scheduleFire()` becomes a no-op.
        boxRef?.release()
    }

    /// Files in the config directory that Mullion rewrites during normal
    /// operation as runtime state, not configuration. `window-history.json`
    /// is written on every snap; treating that as a config edit reloaded
    /// every store, re-registered every hotkey and re-ran arrangement
    /// matching ~0.8s after each snap.
    static let runtimeStateFiles: Set<String> = ["window-history.json"]

    /// FSEvents flags meaning "events were lost or coalesced — rescan".
    /// Such an event carries the watched directory's path, not the file
    /// that changed, so the name filter below can't see the edit it hides.
    static let rescanFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
        | kFSEventStreamEventFlagUserDropped
        | kFSEventStreamEventFlagKernelDropped
        | kFSEventStreamEventFlagRootChanged
    )

    /// Reload only when a `.json` config file changed. Skips runtime state
    /// and non-JSON names — atomic-write temp files, editor swap files,
    /// `layouts.json.bak-*` backups. An atomic write of a config file still
    /// reports the final `<name>.json` path on its rename, so real edits
    /// always get through. Always reloads on a rescan notice (dropped
    /// events) or an event on the watched directory itself or an ancestor
    /// (config dir swapped into place by a restore) — neither names the
    /// files inside. No paths at all → reload, the safe default.
    static func shouldReload(forChangedPaths paths: [String],
                             flags: [FSEventStreamEventFlags] = [],
                             watchedDirectory: String? = nil) -> Bool {
        guard !paths.isEmpty else { return true }
        if flags.contains(where: { $0 & rescanFlags != 0 }) { return true }
        if let watchedDirectory {
            let watched = (watchedDirectory as NSString).standardizingPath
            let touchesWatchedDir = paths.contains { path in
                let standardized = (path as NSString).standardizingPath
                return standardized == watched || watched.hasPrefix(standardized + "/")
            }
            if touchesWatchedDir { return true }
        }
        return paths.contains { path in
            let name = (path as NSString).lastPathComponent
            return name.hasSuffix(".json") && !runtimeStateFiles.contains(name)
        }
    }

    /// Internal hook — also lets tests drive the debounce without producing
    /// real file-system events.
    func scheduleFire() {
        debouncer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debouncer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }
}
