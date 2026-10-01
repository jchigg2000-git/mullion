import Foundation
import os

/// Atomic, debounced Codable storage. Loads on init, writes 500ms after the
/// last mutation. `reload()` is the menu-driven refresh path. Synchronous;
/// all calls must happen on the main thread.
///
/// A config file that exists but cannot be decoded (a hand-edit with a stray
/// comma, a file written by a newer build) is never silently replaced: the
/// store keeps running on its in-memory value, logs the failure, and copies
/// the unreadable bytes aside (`<name>.unreadable-<timestamp>`) before the
/// next write would overwrite them.
@MainActor
final class JSONStore<Model: Codable> {
    private let url: URL
    private(set) var value: Model
    private let debounce: TimeInterval
    private var debouncer: DispatchWorkItem?
    /// A mutation has been made that no write has covered yet.
    private var hasPendingWrite = false
    /// The file at `url` was last seen, and could not be decoded.
    private var diskFileUnreadable = false

    private static var log: Logger { Logger(subsystem: "com.mullion.Mullion", category: "json-store") }

    init(url: URL, default fallback: Model, debounce: TimeInterval = 0.5) {
        self.url = url
        self.debounce = debounce
        do {
            self.value = try Self.read(from: url)
        } catch {
            self.value = fallback
            noteReadFailure(error, keeping: "defaults")
        }
    }

    func update(_ transform: (inout Model) -> Void) {
        transform(&value)
        scheduleWrite()
    }

    func replace(_ newValue: Model) {
        value = newValue
        scheduleWrite()
    }

    func reload() {
        do {
            value = try Self.read(from: url)
            diskFileUnreadable = false
        } catch {
            noteReadFailure(error, keeping: "the in-memory value")
        }
    }

    func flush() {
        debouncer?.cancel()
        debouncer = nil
        hasPendingWrite = false
        writeNow()
    }

    /// Write only if a mutation is waiting out its debounce. For app quit:
    /// an edit made in the last half second would otherwise be lost, while an
    /// unconditional flush would overwrite a hand-edit the file watcher has
    /// not reloaded yet.
    func flushIfPending() {
        guard hasPendingWrite else { return }
        flush()
    }

    private func scheduleWrite() {
        debouncer?.cancel()
        hasPendingWrite = true
        let item = DispatchWorkItem { [self] in
            debouncer = nil
            hasPendingWrite = false
            writeNow()
        }
        debouncer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func writeNow() {
        if diskFileUnreadable {
            preserveUnreadableFile()
        }
        do {
            try Self.write(value, to: url)
            diskFileUnreadable = false
        } catch {
            Self.log.error("could not write \(self.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A missing file is the normal first-run state; anything else that
    /// stops a read is worth a log line and a flag so the bytes get saved.
    private func noteReadFailure(_ error: Error, keeping kept: String) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        diskFileUnreadable = true
        Self.log.error("\(self.url.lastPathComponent, privacy: .public) exists but could not be read (\(error.localizedDescription, privacy: .public)); keeping \(kept, privacy: .public) and saving a copy of the file before it is overwritten")
    }

    private func preserveUnreadableFile() {
        defer { diskFileUnreadable = false }
        let fm = FileManager.default
        // An empty file holds nothing worth keeping.
        guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
              size.intValue > 0 else { return }
        let stamp = Self.backupStamp.string(from: Date())
        var backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).unreadable-\(stamp)")
        if fm.fileExists(atPath: backup.path) {
            backup.deleteLastPathComponent()
            backup.appendPathComponent("\(url.lastPathComponent).unreadable-\(stamp)-\(UUID().uuidString.prefix(4))")
        }
        do {
            try fm.copyItem(at: url, to: backup)
            Self.log.notice("saved unreadable \(self.url.lastPathComponent, privacy: .public) as \(backup.lastPathComponent, privacy: .public)")
        } catch {
            Self.log.error("could not save a copy of unreadable \(self.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var backupStamp: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }

    private static func read(from url: URL) throws -> Model {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Model.self, from: data)
    }

    private static func write(_ value: Model, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
