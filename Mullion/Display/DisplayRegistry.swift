import AppKit
import CoreGraphics

/// Tracks connected displays with stable identity. `CGDirectDisplayID` is
/// NOT stable across reconnect, so persistence keys on the UUID from
/// `CGDisplayCreateUUIDFromDisplayID`. Falls back to a name+size signature
/// for displays without a UUID (rare on physical hardware).
final class DisplayRegistry {
    static let shared = DisplayRegistry()

    private(set) var screens: [NSScreen]
    private var debouncer: DispatchWorkItem?

    var onChange: (() -> Void)?

    private init() {
        self.screens = NSScreen.screens
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        debouncer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.screens = NSScreen.screens
            self.onChange?()
        }
        debouncer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    static func uuid(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            if let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                return CFUUIDCreateString(nil, uuidRef) as String
            }
        }
        return "fallback:\(screen.localizedName):\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    func screen(forUUID uuid: String) -> NSScreen? {
        screens.first { Self.uuid(for: $0) == uuid }
    }
}
