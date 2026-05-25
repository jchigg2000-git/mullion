import AppKit
import ApplicationServices
import os

/// Per-zone MRU list of windows recently placed into each zone. Populated
/// by every successful `.snap` and consulted by every `.focus` dispatch.
///
/// v1 populates the MRU only on snap. Observer-driven updates from
/// `kAXFocusedWindowChangedNotification` are intentionally deferred —
/// "snap a window, later focus it back" is the dominant `.focus` flow
/// and doesn't need them. Entries for terminated processes are cleared
/// via `NSWorkspace.didTerminateApplicationNotification`.
final class FocusIndex {
    private let log = Logger(subsystem: "com.mullion.Mullion", category: "focus-index")
    private var byZone: [UUID: [Entry]] = [:]
    private let perZoneCap: Int
    private var terminationObserver: NSObjectProtocol?

    private struct Entry {
        let element: AXUIElement
        let pid: pid_t
    }

    init(perZoneCap: Int = 32) {
        self.perZoneCap = perZoneCap
        self.terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.evict(pid: app.processIdentifier)
        }
    }

    deinit {
        if let observer = terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func record(window: AXWindow, zoneID: UUID) {
        var list = byZone[zoneID] ?? []
        list.removeAll { CFEqual($0.element, window.element) }
        list.insert(Entry(element: window.element, pid: window.pid), at: 0)
        if list.count > perZoneCap {
            list = Array(list.prefix(perZoneCap))
        }
        byZone[zoneID] = list
    }

    /// Most-recent window in `zoneID` whose process is still running.
    /// Walks the MRU, dropping entries for terminated pids as it goes.
    func mostRecentAliveWindow(in zoneID: UUID) -> AXWindow? {
        var list = byZone[zoneID] ?? []
        while let entry = list.first {
            if NSRunningApplication(processIdentifier: entry.pid) != nil {
                byZone[zoneID] = list
                return AXWindow(element: entry.element, pid: entry.pid)
            }
            list.removeFirst()
        }
        byZone[zoneID] = list
        return nil
    }

    /// Raises the window via `kAXRaiseAction` and activates its app.
    @discardableResult
    func raise(_ window: AXWindow) -> Bool {
        let raised = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) == .success
        let activated = NSRunningApplication(processIdentifier: window.pid)?.activate() ?? false
        if !raised {
            log.notice("AXRaise failed for pid=\(window.pid, privacy: .public)")
        }
        return raised && activated
    }

    /// Drops every entry across all zones whose pid matches. Used when an
    /// app terminates and on demand for dead-pid cleanup.
    func evict(pid: pid_t) {
        for (zoneID, entries) in byZone {
            let filtered = entries.filter { $0.pid != pid }
            byZone[zoneID] = filtered
        }
    }

    /// Test hook — exposes the count for assertions without leaking entry
    /// internals.
    func count(in zoneID: UUID) -> Int {
        byZone[zoneID]?.count ?? 0
    }
}
