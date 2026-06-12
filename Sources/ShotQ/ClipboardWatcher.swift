import AppKit
import Combine

enum SettingsKeys {
    static let multiPaste = "multiPasteEnabled"
    static let eraseAfterPaste = "eraseAfterPaste"
    static let pasteDelaySeconds = "pasteDelaySeconds"
}

/// Polls NSPasteboard for new screenshots (Ctrl-Shift-Cmd-3/4 put the capture
/// on the clipboard) and hands them to the VaultStore for archiving. Captures
/// accumulate in `pendingBatch`; a Ctrl+V in a terminal pastes the whole batch.
/// Main-thread only.
final class ClipboardWatcher: ObservableObject {
    let store: VaultStore

    @Published var isPaused = false
    @Published var captureCount = 0
    @Published var recent: [Capture] = []
    @Published var pendingBatch: [Capture] = []
    @Published var interceptorActive = false

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    /// changeCount of the most recently archived screenshot; while the
    /// clipboard still shows this value, Cmd+V batch paste may hijack.
    private var lastScreenshotChangeCount = -1
    private var timer: Timer?
    private let interceptor = PasteInterceptor()

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let nspasteboardSource = NSPasteboard.PasteboardType("org.nspasteboard.source")

    init(store: VaultStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount

        let existing = store.loadAllSorted()
        self.recent = Array(existing.prefix(10))
        self.captureCount = existing.count

        interceptor.onCtrlV = { [weak self] in
            self?.handlePasteRequest() ?? false
        }
        interceptor.onCmdV = { [weak self] in
            self?.handleCmdVPasteRequest() ?? false
        }
        interceptor.onStatusChange = { [weak self] active in
            self?.interceptorActive = active
        }
        if UserDefaults.standard.bool(forKey: SettingsKeys.multiPaste) {
            interceptor.start()
        }

        startPolling()
    }

    func enableInterceptor() {
        interceptor.start()
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let change = pasteboard.changeCount
        guard change != lastChangeCount else { return }
        lastChangeCount = change

        let typeList = (pasteboard.types ?? []).map(\.rawValue).joined(separator: ", ")
        guard !isPaused else {
            DebugLog.log("clipboard #\(change) ignored: paused")
            return
        }
        guard looksLikeScreenshot() else {
            DebugLog.log("clipboard #\(change) skipped, not a screenshot: [\(typeList)]")
            return
        }
        guard let image = rawImageData() else {
            DebugLog.log("clipboard #\(change) image flavors but no data: [\(typeList)]")
            return
        }
        DebugLog.log("clipboard #\(change) archiving: [\(typeList)]")
        lastScreenshotChangeCount = change

        store.save(image) { [weak self] capture in
            guard let self else { return }
            guard let capture else {
                DebugLog.log("clipboard #\(change) not saved (duplicate or write failure)")
                return
            }
            self.recent.insert(capture, at: 0)
            if self.recent.count > 10 {
                self.recent.removeLast(self.recent.count - 10)
            }
            self.captureCount += 1
            self.pendingBatch.append(capture)
            DebugLog.log("saved \(capture.filename), pending batch = \(self.pendingBatch.count)")
        }
    }

    /// Screenshots arrive as bare image data. Images copied from apps carry
    /// extra flavors (file URLs, HTML, text); their presence disqualifies.
    private func looksLikeScreenshot() -> Bool {
        guard let types = pasteboard.types else { return false }

        if types.contains(Self.concealedType) { return false }

        let hasImage = types.contains(.png) || types.contains(.tiff)
        guard hasImage else { return false }

        let disqualifying: [NSPasteboard.PasteboardType] = [
            .fileURL, .URL, .string, .html, .rtf, .pdf,
            Self.nspasteboardSource,
        ]
        return !types.contains(where: disqualifying.contains)
    }

    private func rawImageData() -> PasteboardImage? {
        if let png = pasteboard.data(forType: .png) {
            return .png(png)
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            return .tiff(tiff)
        }
        return nil
    }

    // MARK: - Batch paste (Ctrl+V interception)

    /// Called by the interceptor on Ctrl+V in a terminal. Returns true when
    /// the keystroke was consumed by a batch paste.
    private func handlePasteRequest() -> Bool {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.multiPaste),
              !pendingBatch.isEmpty else {
            DebugLog.log("Ctrl+V passthrough (batch empty or multi-paste disabled)")
            return false
        }
        DebugLog.log("Ctrl+V intercepted — pasting batch of \(pendingBatch.count)")
        performBatchPaste(flags: .maskControl)
        return true
    }

    /// Cmd+V hijacks only while the clipboard still holds the screenshot we
    /// archived last — anything copied since means the user wants that paste.
    private func handleCmdVPasteRequest() -> Bool {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.multiPaste),
              !pendingBatch.isEmpty else {
            return false
        }
        guard pasteboard.changeCount == lastScreenshotChangeCount else {
            DebugLog.log("Cmd+V passthrough (clipboard changed since last screenshot)")
            return false
        }
        DebugLog.log("Cmd+V intercepted — pasting batch of \(pendingBatch.count)")
        performBatchPaste(flags: .maskCommand)
        return true
    }

    func performBatchPaste(flags: CGEventFlags = .maskControl) {
        let batch = pendingBatch
        guard !batch.isEmpty else { return }
        pendingBatch = []
        pasteSequence(batch, index: 0, flags: flags)
    }

    /// Pastes batch[index], then schedules the next item. The delay gives the
    /// receiving app time to read the clipboard before it is swapped for the
    /// next image.
    private func pasteSequence(_ batch: [Capture], index: Int, flags: CGEventFlags) {
        if index >= batch.count {
            if UserDefaults.standard.bool(forKey: SettingsKeys.eraseAfterPaste) {
                erase(batch)
            }
            return
        }

        let capture = batch[index]
        if let data = try? Data(contentsOf: capture.url) {
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
            lastChangeCount = pasteboard.changeCount
            PasteInterceptor.postSyntheticPaste(flags: flags)
        }

        let configured = UserDefaults.standard.double(forKey: SettingsKeys.pasteDelaySeconds)
        let delay = max(0.15, configured)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pasteSequence(batch, index: index + 1, flags: flags)
        }
    }

    /// Moves captures to the Trash (recoverable) and drops them from the UI.
    private func erase(_ batch: [Capture]) {
        DebugLog.log("erasing \(batch.count) pasted captures to Trash")
        for capture in batch {
            try? FileManager.default.trashItem(at: capture.url, resultingItemURL: nil)
        }
        let urls = Set(batch.map(\.url))
        recent.removeAll { urls.contains($0.url) }
        captureCount = max(0, captureCount - batch.count)
        store.forget(hashes: batch.compactMap(\.hash))
    }

    // MARK: - Deletion

    /// Moves one capture to the Trash and refreshes the list from disk.
    func delete(_ capture: Capture) {
        try? FileManager.default.trashItem(at: capture.url, resultingItemURL: nil)
        pendingBatch.removeAll { $0.url == capture.url }
        if let hash = capture.hash {
            store.forget(hashes: [hash])
        }
        DebugLog.log("deleted \(capture.filename)")
        reloadFromDisk()
    }

    /// Moves the entire vault folder to the Trash (recoverable as one item).
    func deleteAll() {
        DebugLog.log("deleting all \(captureCount) captures")
        try? FileManager.default.trashItem(at: store.baseURL, resultingItemURL: nil)
        pendingBatch = []
        recent = []
        captureCount = 0
        store.forgetAllHashes()
    }

    private func reloadFromDisk() {
        let all = store.loadAllSorted()
        recent = Array(all.prefix(10))
        captureCount = all.count
    }

    // MARK: - Manual clipboard actions

    /// Copies an archived capture back to the clipboard without re-archiving it.
    func copyToClipboard(_ capture: Capture) {
        guard let data = try? Data(contentsOf: capture.url) else { return }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        lastChangeCount = pasteboard.changeCount
    }

    /// Copies the file paths of recent captures as newline-separated text,
    /// for pasting into CLIs (e.g. Claude Code) that read images from paths.
    func copyRecentPaths(limit: Int = 10) {
        let paths = recent.prefix(limit).map(\.url.path).joined(separator: "\n")
        guard !paths.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(paths, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }
}
