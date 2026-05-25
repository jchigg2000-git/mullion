import Foundation

enum ApplicationSupport {
    static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let url = base.appendingPathComponent("Mullion", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename, isDirectory: false)
    }
}
