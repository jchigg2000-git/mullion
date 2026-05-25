import Foundation

/// Atomic, debounced Codable storage. Loads on init, writes 500ms after the
/// last mutation. `reload()` is the menu-driven refresh path. Synchronous;
/// all calls must happen on the main thread.
final class JSONStore<Model: Codable> {
    private let url: URL
    private(set) var value: Model
    private let debounce: TimeInterval
    private var debouncer: DispatchWorkItem?

    init(url: URL, default fallback: Model, debounce: TimeInterval = 0.5) {
        self.url = url
        self.debounce = debounce
        self.value = (try? Self.read(from: url)) ?? fallback
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
        guard let loaded = try? Self.read(from: url) else { return }
        value = loaded
    }

    func flush() {
        debouncer?.cancel()
        debouncer = nil
        try? Self.write(value, to: url)
    }

    private func scheduleWrite() {
        debouncer?.cancel()
        let snapshot = value
        let url = self.url
        let item = DispatchWorkItem {
            try? Self.write(snapshot, to: url)
        }
        debouncer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
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
