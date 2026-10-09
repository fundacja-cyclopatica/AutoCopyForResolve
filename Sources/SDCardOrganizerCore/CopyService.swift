import Foundation

/// Rezultat zgrywania pojedynczego pliku.
public enum CopyFileResult: Equatable {
    case copied(URL)
    case skippedDuplicate(URL)
    case failed(URL, String)
}

/// Informacja o nieudanym skopiowaniu pliku.
public struct FailedCopy: Equatable {
    public let url: URL
    public let error: String

    public init(url: URL, error: String) {
        self.url = url
        self.error = error
    }
}

/// Raport z całego zgrywania.
public struct CopyReport: Equatable {
    public var copied: [URL] = []
    public var skipped: [URL] = []
    public var failed: [FailedCopy] = []
    public var totalBytesCopied: Int64 = 0

    public var totalCopied: Int { copied.count }
    public var totalSkipped: Int { skipped.count }
    public var totalFailed: Int { failed.count }
}

/// Wykonuje kopiowanie plików z postępem i deduplikacją.
public final class CopyService {
    public let verifyChecksums: Bool
    private let fileManager = FileManager.default

    /// Zamknięcie wywoływane po skopiowaniu każdego pliku (0.0...1.0).
    public var onProgress: ((Double, URL) -> Void)?

    public init(verifyChecksums: Bool) {
        self.verifyChecksums = verifyChecksums
    }

    /// Kopiuje pliki do struktury projektu (z opcjonalnym podfolderem kamery) i zwraca raport.
    public func copy(files: [MediaFile], to layout: ProjectLayout, cameraLabel: String? = nil) throws -> CopyReport {
        var report = CopyReport()
        let total = files.count
        var done = 0

        // Zapewnij istnienie katalogów docelowych.
        try fileManager.createDirectory(at: layout.videoDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.audioDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.photoDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.daVinciDir, withIntermediateDirectories: true)

        let videoTarget = layout.targetDirectory(for: .video, cameraLabel: cameraLabel)
        let audioTarget = layout.targetDirectory(for: .audio, cameraLabel: cameraLabel)
        let photoTarget = layout.targetDirectory(for: .photo, cameraLabel: cameraLabel)

        try fileManager.createDirectory(at: videoTarget, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: audioTarget, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: photoTarget, withIntermediateDirectories: true)

        // Zbiór nazw już zajętych w każdym katalogu — do wykrywania kolizji.
        var existingNamesByCategory: [MediaCategory: Set<String>] = [
            .video: Set(initialNames(of: videoTarget)),
            .audio: Set(initialNames(of: audioTarget)),
            .photo: Set(initialNames(of: photoTarget))
        ]

        for file in files {
            let destDir = layout.targetDirectory(for: file.category, cameraLabel: cameraLabel)
            let decision = CopyPlanner.decision(
                source: file.url,
                destinationDirectory: destDir,
                verifyChecksums: verifyChecksums,
                existingNames: existingNamesByCategory[file.category] ?? []
            )

            switch decision {
            case .skipDuplicate:
                report.skipped.append(file.url)
            case .copyAsIs(let dest):
                let bytes = try copyFile(from: file.url, to: dest)
                report.copied.append(dest)
                report.totalBytesCopied += bytes
                existingNamesByCategory[file.category, default: []].insert(dest.lastPathComponent)
            case .copy(let dest):
                let bytes = try copyFile(from: file.url, to: dest)
                report.copied.append(dest)
                report.totalBytesCopied += bytes
                existingNamesByCategory[file.category, default: []].insert(dest.lastPathComponent)
            }

            done += 1
            onProgress?(Double(done) / Double(total), file.url)
        }
        return report
    }

    private func directory(for category: MediaCategory, in layout: ProjectLayout) -> URL {
        switch category {
        case .video: return layout.videoDir
        case .audio: return layout.audioDir
        case .photo: return layout.photoDir
        }
    }

    private func contentsNames(of dir: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: dir.path)
    }

    private func initialNames(of dir: URL) -> [String] {
        (try? contentsNames(of: dir)) ?? []
    }

    /// Kopiuje pojedynczy plik z zachowaniem dat utworzenia i atrybutów.
    /// Zwraca liczbę skopiowanych bajtów.
    @discardableResult
    private func copyFile(from source: URL, to destination: URL) throws -> Int64 {
        // Upewnij się, że katalog docelowy istnieje
        let parentDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        // Usuwamy ewentualny istniejący plik docelowy
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw CopyError.copyItemFailed(source: source.path, destination: destination.path, reason: error.localizedDescription)
        }

        let attrs = try? fileManager.attributesOfItem(atPath: destination.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    public enum CopyError: LocalizedError {
        case cannotOpenSource(String)
        case cannotCreateDestination(String)
        case copyItemFailed(source: String, destination: String, reason: String)
        case readFailed(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .cannotOpenSource(let p): return "Nie można otworzyć pliku źródłowego: \(p)"
            case .cannotCreateDestination(let p): return "Nie można utworzyć folderu docelowego: \(p)"
            case .copyItemFailed(_, let d, let reason): return "Błąd zapisu pliku \(d): \(reason)"
            case .readFailed(let p): return "Błąd odczytu pliku: \(p)"
            case .writeFailed(let p): return "Błąd zapisu pliku: \(p)"
            }
        }
    }
}
