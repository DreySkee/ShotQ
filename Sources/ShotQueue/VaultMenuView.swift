import SwiftUI

struct VaultMenuView: View {
    @EnvironmentObject private var watcher: ClipboardWatcher
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginItemError: String?
    @AppStorage(SettingsKeys.multiPaste) private var multiPaste = true
    @AppStorage(SettingsKeys.eraseAfterPaste) private var eraseAfterPaste = true
    @State private var confirmingDeleteAll = false

    private static let rowHeight: CGFloat = 56
    private static let maxVisibleRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            captureList
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("ShotQueue").font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                watcher.isPaused.toggle()
            } label: {
                Image(systemName: watcher.isPaused ? "play.circle.fill" : "pause.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(watcher.isPaused ? "Resume watching" : "Pause watching")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusText: String {
        if watcher.isPaused { return "Paused" }
        var text = "Watching · \(watcher.captureCount) saved"
        if !watcher.pendingBatch.isEmpty {
            text += " · \(watcher.pendingBatch.count) pending ⌃V"
        }
        return text
    }

    @ViewBuilder
    private var captureList: some View {
        if watcher.recent.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "rectangle.dashed")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No screenshots yet")
                    .foregroundStyle(.secondary)
                Text("Press ⌃⇧⌘4, capture an area — it lands here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(watcher.recent) { capture in
                        CaptureRow(capture: capture)
                            .frame(height: Self.rowHeight)
                    }
                }
            }
            .frame(height: CGFloat(min(watcher.recent.count, Self.maxVisibleRows)) * Self.rowHeight)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingRow("Batch paste on ⌃V / ⌘V", isOn: $multiPaste)
                .onChange(of: multiPaste) { enabled in
                    if enabled { watcher.enableInterceptor() }
                }

            settingRow("Erase screenshots after paste", isOn: $eraseAfterPaste)
                .disabled(!multiPaste)
                .opacity(multiPaste ? 1 : 0.5)

            if multiPaste && !watcher.interceptorActive {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text("Needs Accessibility permission")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        if let url = URL(string: pane) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.mini)
                }
            }

            settingRow("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        try LaunchAtLogin.set(enabled)
                        loginItemError = nil
                    } catch {
                        loginItemError = error.localizedDescription
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Open Folder") {
                    let folder = watcher.store.baseURL
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
                Button("Copy Paths") {
                    watcher.copyRecentPaths()
                }
                .disabled(watcher.recent.isEmpty)
                .help("Copy file paths of recent captures — paste into Claude Code or any CLI")
                Spacer()
                Button(confirmingDeleteAll ? "Really?" : "Delete All") {
                    if confirmingDeleteAll {
                        watcher.deleteAll()
                        confirmingDeleteAll = false
                    } else {
                        confirmingDeleteAll = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            confirmingDeleteAll = false
                        }
                    }
                }
                .tint(.red)
                .disabled(watcher.captureCount == 0)
                .help("Move every capture in the vault to the Trash")
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(12)
    }

    private func settingRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct CaptureRow: View {
    let capture: Capture
    @EnvironmentObject private var watcher: ClipboardWatcher
    @State private var thumbnail: NSImage?
    @State private var justCopied = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            thumbnailView
                .frame(width: 64, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(capture.filename)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.relativeFormatter.localizedString(for: capture.date, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                watcher.copyToClipboard(capture)
                justCopied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    justCopied = false
                }
            } label: {
                Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(justCopied ? .green : .primary)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([capture.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")

            Button {
                watcher.delete(capture)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Move to Trash")
        }
        .padding(.horizontal, 12)
        .task(id: capture.url) {
            thumbnail = Thumbnailer.thumbnail(for: capture.url)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}
