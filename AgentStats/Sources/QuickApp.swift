import AppKit

// The Quick App slot's tap behaviour, shared by agents-stat and the Pock
// AgentStats widget. Not running: launch. Running: `action`, one of
// "minimize" (default), "close" or "fullscreen".
enum QuickApp {
    static func tap(path: String, action: String) {
        let url = URL(fileURLWithPath: path)
        // Not running → launch. Running → the configured action.
        guard let bid = Bundle(url: url)?.bundleIdentifier,
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first
        else {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        // Hidden app: bring it back regardless of action — the visible half
        // of every toggle (also prevents "close" from quitting a hidden app).
        if running.isHidden {
            running.unhide()
            activate(running)
            return
        }
        // Running but with no windows (e.g. the last one was closed by this
        // button): the tap reopens one, completing the open ↔ close cycle.
        if AXIsProcessTrusted(),
           axWindows(running.processIdentifier) == nil {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        switch action {
        case "close":
            closeWindows(running)
        case "fullscreen":
            toggleFullscreen(running)
        default:
            toggleMinimize(running)
        }
    }

    // All three actions press the window's real traffic-light buttons via
    // Accessibility — same animation and events as a mouse click, so tools
    // that hook window actions (DockDoor etc.) see them too.

    private static func toggleMinimize(_ app: NSRunningApplication) {
        guard let wins = axWindows(app.processIdentifier) else {
            app.hide()  // no Accessibility: hide/unhide is the closest toggle
            return
        }
        let minimized = wins.filter { axBool($0, kAXMinimizedAttribute) }
        if minimized.isEmpty {
            var pressed = false
            for w in wins { pressed = pressButton(w, kAXMinimizeButtonAttribute) || pressed }
            if !pressed { app.hide() }  // window without a minimize button
        } else {
            for w in minimized {
                AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            activate(app)
        }
    }

    private static func closeWindows(_ app: NSRunningApplication) {
        guard let wins = axWindows(app.processIdentifier) else {
            app.terminate()  // no Accessibility: quit ↔ launch is the toggle
            return
        }
        var closed = false
        for w in wins { closed = pressButton(w, kAXCloseButtonAttribute) || closed }
        if !closed { app.terminate() }
    }

    private static func toggleFullscreen(_ app: NSRunningApplication) {
        guard let front = frontWindow(app.processIdentifier) else {
            activate(app)  // no Accessibility: best we can do is bring it forward
            return
        }
        if axBool(front, "AXFullScreen") {
            AXUIElementSetAttributeValue(front, "AXFullScreen" as CFString, kCFBooleanFalse)
        } else {
            if !pressButton(front, "AXFullScreenButton") {
                AXUIElementSetAttributeValue(front, "AXFullScreen" as CFString, kCFBooleanTrue)
            }
            activate(app)
        }
    }

    private static func frontWindow(_ pid: pid_t) -> AXUIElement? {
        var ref: CFTypeRef?
        if AXIsProcessTrusted(),
           AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),
                                         kAXMainWindowAttribute as CFString, &ref) == .success,
           let w = ref {
            return (w as! AXUIElement)
        }
        return axWindows(pid)?.first
    }

    private static func pressButton(_ win: AXUIElement, _ attr: String) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, attr as CFString, &ref) == .success,
              let button = ref else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) { app.activate() }
        else { app.activate(options: []) }
    }

    private static func axWindows(_ pid: pid_t) -> [AXUIElement]? {
        guard AXIsProcessTrusted() else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),
                                            kAXWindowsAttribute as CFString, &ref) == .success,
              let wins = ref as? [AXUIElement], !wins.isEmpty else { return nil }
        return wins
    }

    private static func axBool(_ el: AXUIElement, _ attr: String) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return false }
        return (ref as? Bool) ?? false
    }
}
