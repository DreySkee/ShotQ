import AppKit
import CryptoKit
import Foundation

enum PasteboardImage {
    case png(Data)
    case tiff(Data)
}

struct Capture: Identifiable, Equatable {
    let url: URL
    let date: Date
    /// SHA-256 of the PNG data; nil for captures loaded from disk at startup.
    var hash: String?
    var id: URL { url }

    var filename: String { url.lastPathComponent }
}

/// Persists captures as PNG files under ~/Pictures/ShotQueue/YYYY/MM/.
/// Heavy work (TIFF→PNG conversion, hashing, disk writes) runs on a serial
/// background queue; completions are delivered on the main queue.
final class VaultStore {
    let baseURL: URL

    private let queue = DispatchQueue(label: "dev.andrey.ShotQueue.store", qos: .utility)
    private var recentHashes: [String] = []
    private let maxRememberedHashes = 64

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM"
        return formatter
    }()

    init() {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        baseURL = pictures.appendingPathComponent("ShotQueue", isDirectory: true)
    }

    /// Completion receives nil for duplicates and failures; runs on main queue.
    func save(_ image: PasteboardImage, completion: @escaping (Capture?) -> Void) {
        queue.async {
            let capture = self.performSave(image)
            DispatchQueue.main.async {
                completion(capture)
            }
        }
    }

    private func performSave(_ image: PasteboardImage) -> Capture? {
        let pngData: Data
        switch image {
        case .png(let data):
            pngData = data
        case .tiff(let data):
            guard let rep = NSBitmapImageRep(data: data),
                  let converted = rep.representation(using: .png, properties: [:]) else {
                return nil
            }
            pngData = converted
        }

        let hash = SHA256.hash(data: pngData).map { String(format: "%02x", $0) }.joined()
        if recentHashes.contains(hash) { return nil }
        recentHashes.append(hash)
        if recentHashes.count > maxRememberedHashes {
            recentHashes.removeFirst(recentHashes.count - maxRememberedHashes)
        }

        let now = Date()
        let directory = baseURL.appendingPathComponent(Self.monthFormatter.string(from: now), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = availableURL(in: directory, date: now)
            try pngData.write(to: url, options: .atomic)
            return Capture(url: url, date: now, hash: hash)
        } catch {
            NSLog("ShotQueue: failed to save capture: \(error.localizedDescription)")
            return nil
        }
    }

    private func availableURL(in directory: URL, date: Date) -> URL {
        let base = "Screenshot \(Self.nameFormatter.string(from: date))"
        var candidate = directory.appendingPathComponent("\(base).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(counter)).png")
            counter += 1
        }
        return candidate
    }

    /// Drops remembered hashes so an identical capture can be archived again
    /// after its file was erased.
    func forget(hashes: [String]) {
        guard !hashes.isEmpty else { return }
        queue.async {
            self.recentHashes.removeAll(where: hashes.contains)
        }
    }

    func forgetAllHashes() {
        queue.async {
            self.recentHashes.removeAll()
        }
    }

    /// All archived captures, newest first.
    func loadAllSorted() -> [Capture] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var captures: [Capture] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "png" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            captures.append(Capture(url: url, date: date, hash: nil))
        }
        return captures.sorted { $0.date > $1.date }
    }
}
