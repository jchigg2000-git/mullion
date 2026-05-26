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
        init(_ watcher: ConfigFileWatcher? = nil) { self.watcher = watcher }
    }

    init?(directory: URL,
          debounceInterval: TimeInterval = 0.25,
          onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.debounceInterval = debounceInterval
        self.weakBox = WeakBox()

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

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let box = Unmanaged<WeakBox>.fromOpaque(info).takeUnretainedValue()
            box.watcher?.scheduleFire()
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05, // FSEvents-internal coalescing latency (s)
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
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
