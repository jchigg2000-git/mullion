import Foundation

enum ApplicationSupport {
    static var directory: URL {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Mullion", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename, isDirectory: false)
    }
}
