import AppKit
import ApplicationServices

/// Intercepts plain Ctrl+V system-wide via a CGEventTap so a pending batch of
/// screenshots can be pasted sequentially into terminal CLIs. Requires the
/// Accessibility permission; until granted, creation is retried periodically.
/// Main-thread only — the tap's run loop source is attached to the main loop.
final class PasteInterceptor {
    /// Marks synthetic events so the tap lets them through.
    private static let syntheticMarker: Int64 = 0x5356_4150 // 'SVAP'

    private static let vKeyCode: Int64 = 9

    /// Frontmost apps in which Ctrl+V is intercepted.
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.vscodium",
    ]

    /// Return true to swallow the keystroke.
    var onCtrlV: () -> Bool = { false }
    /// Cmd+V in non-terminal apps; return true to swallow.
    var onCmdV: () -> Bool = { false }
    /// Reports whether the tap is installed (false = permission missing).
    var onStatusChange: (Bool) -> Void = { _ in }

    private(set) var isActive = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    func start() {
        guard tap == nil else { return }
        DebugLog.log("interceptor starting (AXIsProcessTrusted=\(AXIsProcessTrusted()))")
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        attemptTapCreation()
        if !isActive, retryTimer == nil {
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                self?.attemptTapCreation()
            }
            RunLoop.main.add(timer, forMode: .common)
            retryTimer = timer
        }
    }

    private func attemptTapCreation() {
        guard tap == nil, AXIsProcessTrusted() else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: PasteInterceptor.callback,
            userInfo: refcon
        ) else {
            DebugLog.log("CGEvent.tapCreate failed despite Accessibility trust — check Input Monitoring pane too")
            onStatusChange(false)
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isActive = true
        retryTimer?.invalidate()
        retryTimer = nil
        DebugLog.log("Ctrl+V event tap installed")
        onStatusChange(true)
    }

    fileprivate func reenableTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    fileprivate func handleCtrlV() -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard Self.terminalBundleIDs.contains(frontmost) else {
            DebugLog.log("Ctrl+V in \"\(frontmost)\" — not in terminal allowlist, passing through")
            return false
        }
        return onCtrlV()
    }

    /// Cmd+V batch paste applies everywhere EXCEPT terminals (there Cmd+V is
    /// plain text paste and Ctrl+V handles batches).
    fileprivate func handleCmdV() -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard !Self.terminalBundleIDs.contains(frontmost) else { return false }
        return onCmdV()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        let passthrough = Unmanaged.passUnretained(event)
        guard let refcon else { return passthrough }
        let interceptor = Unmanaged<PasteInterceptor>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            interceptor.reenableTap()
            return passthrough
        }
        guard type == .keyDown else { return passthrough }
        guard event.getIntegerValueField(.eventSourceUserData) != syntheticMarker else { return passthrough }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == vKeyCode else { return passthrough }
        let flags = event.flags
        let ctrl = flags.contains(.maskControl)
        let cmd = flags.contains(.maskCommand)
        let alt = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)

        if ctrl && !cmd && !alt && !shift {
            return interceptor.handleCtrlV() ? nil : passthrough
        }
        if cmd && !ctrl && !alt && !shift {
            return interceptor.handleCmdV() ? nil : passthrough
        }
        return passthrough
    }

    /// Posts a paste keystroke (V + given modifier) tagged so our own tap
    /// ignores it.
    static func postSyntheticPaste(flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        source.userData = syntheticMarker
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vKeyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vKeyCode), keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
