import CoreGraphics

/// Strategy for placing a window into an AX-space rect. Implementations
/// return `true` if the window landed close enough to the target.
protocol WindowMover {
    func move(_ window: AXWindow, to axFrame: CGRect) -> Bool
}

/// Direct write. Works for most apps.
struct StandardWindowMover: WindowMover {
    func move(_ window: AXWindow, to axFrame: CGRect) -> Bool {
        WindowMutator.set(window, axFrame: axFrame)
        guard let result = window.axFrame else { return false }
        let dx = abs(result.origin.x - axFrame.origin.x)
        let dy = abs(result.origin.y - axFrame.origin.y)
        let dw = abs(result.size.width - axFrame.size.width)
        let dh = abs(result.size.height - axFrame.size.height)
        return dx < 2 && dy < 2 && dw < 2 && dh < 2
    }
}

/// Fixed-size apps (Calculator, some preferences windows) ignore size writes.
/// Center the current-size window within the target rect.
struct CenteringFixedSizeWindowMover: WindowMover {
    func move(_ window: AXWindow, to axFrame: CGRect) -> Bool {
        guard let current = window.axFrame else { return false }
        let centeredX = axFrame.origin.x + (axFrame.size.width - current.size.width) / 2
        let centeredY = axFrame.origin.y + (axFrame.size.height - current.size.height) / 2
        let centered = CGRect(origin: CGPoint(x: centeredX, y: centeredY), size: current.size)
        WindowMutator.set(window, axFrame: centered)
        return true
    }
}

/// Try movers in order, returning on the first success.
struct ChainedWindowMover: WindowMover {
    let movers: [WindowMover]

    func move(_ window: AXWindow, to axFrame: CGRect) -> Bool {
        for mover in movers {
            if mover.move(window, to: axFrame) { return true }
        }
        return false
    }

    static let `default` = ChainedWindowMover(movers: [
        StandardWindowMover(),
        CenteringFixedSizeWindowMover(),
    ])
}
