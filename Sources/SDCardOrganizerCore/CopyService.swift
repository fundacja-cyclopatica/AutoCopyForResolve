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
    /// Skopiowane pliki, których zgodność z oryginałem potwierdzono sumą kontrolną.
    public var verified: [URL] = []
    public var totalBytesCopied: Int64 = 0

    public var totalCopied: Int { copied.count }
    public var totalSkipped: Int { skipped.count }
    public var totalFailed: Int { failed.count }
    public var totalVerified: Int { verified.count }

    public init() {}
}

/// Wykonuje kopiowanie plików z postępem i deduplikacją.
public final class CopyService {
    public let verifyChecksums: Bool
    /// Czy po skopiowaniu porównywać sumę kontrolną kopii z oryginałem.
    public let verifyCopies: Bool
    private let fileManager = FileManager.default
    private static let bufferSize = 8 * 1024 * 1024

    /// Zamknięcie wywoływane po skopiowaniu każdego pliku (0.0...1.0).
    public var onProgress: ((Double, URL) -> Void)?

    public init(verifyChecksums: Bool, verifyCopies: Bool = false) {
        self.verifyChecksums = verifyChecksums
        self.verifyCopies = verifyCopies
    }

    /// Kopiuje pliki do struktury projektu (z opcjonalnym podfolderem kamery) i zwraca raport.
    ///
    /// Błąd pojedynczego pliku nie przerywa zgrywania — trafia do `CopyReport.failed`,
    /// a kopiowanie przechodzi do kolejnego pliku. Wyjątek rzucany jest tylko wtedy,
    /// gdy nie da się utworzyć katalogów docelowych.
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
            case .copyAsIs(let dest), .copy(let dest):
                do {
                    let bytes = try copyFile(from: file.url, to: dest)
                    report.copied.append(dest)
                    report.totalBytesCopied += bytes
                    if verifyCopies {
                        report.verified.append(dest)
                    }
                    existingNamesByCategory[file.category, default: []].insert(dest.lastPathComponent)
                } catch {
                    report.failed.append(FailedCopy(url: file.url, error: error.localizedDescription))
                }
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

    /// Kopiuje pojedynczy plik z zachowaniem dat utworzenia i modyfikacji.
    /// Zwraca liczbę skopiowanych bajtów.
    ///
    /// Plik powstaje najpierw jako ukryty plik tymczasowy `.<nazwa>.part` i dopiero po
    /// udanym skopiowaniu (oraz weryfikacji) dostaje docelową nazwę. Przerwane kopiowanie
    /// nie zostawia więc w projekcie niepełnego pliku pod właściwą nazwą. Istniejący plik
    /// docelowy nigdy nie jest nadpisywany.
    @discardableResult
    private func copyFile(from source: URL, to destination: URL) throws -> Int64 {
        // Upewnij się, że katalog docelowy istnieje
        let parentDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let partial = parentDir.appendingPathComponent(".\(destination.lastPathComponent).part")
        // Pozostałość po wcześniej przerwanym kopiowaniu.
        try? fileManager.removeItem(at: partial)

        do {
            if verifyCopies {
                let sourceHash = try streamCopy(from: source, to: partial)
                let copyHash = try Self.checksum(of: partial, bypassingCache: true)
                guard sourceHash == copyHash else {
                    throw CopyError.verificationFailed(source.path)
                }
                try copyTimestamps(from: source, to: partial)
            } else {
                try fileManager.copyItem(at: source, to: partial)
            }
            try fileManager.moveItem(at: partial, to: destination)
        } catch let error as CopyError {
            try? fileManager.removeItem(at: partial)
            throw error
        } catch {
            try? fileManager.removeItem(at: partial)
            throw CopyError.copyItemFailed(source: source.path, destination: destination.path, reason: error.localizedDescription)
        }

        let attrs = try? fileManager.attributesOfItem(atPath: destination.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    /// Kopiuje plik strumieniowo, jednocześnie licząc SHA-256 odczytanych danych
    /// (karta jest czytana tylko raz). Zwraca checksum oryginału.
    private func streamCopy(from source: URL, to destination: URL) throws -> String {
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw CopyError.cannotCreateDestination(destination.path)
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        // Zapis z pominięciem pamięci podręcznej, aby weryfikacja czytała dane z dysku.
        Self.disableCache(for: output)

        var hasher = SHA256Hasher()
        while let chunk = try autoreleasepool(invoking: { try input.read(upToCount: Self.bufferSize) }),
              !chunk.isEmpty {
            hasher.update(chunk)
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
        return hasher.finalize()
    }

    /// Checksum SHA-256 pliku; opcjonalnie z pominięciem pamięci podręcznej systemu.
    static func checksum(of url: URL, bypassingCache: Bool) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if bypassingCache {
            disableCache(for: handle)
        }

        var hasher = SHA256Hasher()
        while let chunk = try autoreleasepool(invoking: { try handle.read(upToCount: bufferSize) }),
              !chunk.isEmpty {
            hasher.update(chunk)
        }
        return hasher.finalize()
    }

    private static func disableCache(for handle: FileHandle) {
        #if canImport(Darwin)
        _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
        #endif
    }

    /// Przenosi daty utworzenia i modyfikacji z oryginału na kopię (ważne dla grupowania po dniach).
    private func copyTimestamps(from source: URL, to destination: URL) throws {
        let attrs = try fileManager.attributesOfItem(atPath: source.path)
        var dates: [FileAttributeKey: Any] = [:]
        if let created = attrs[.creationDate] { dates[.creationDate] = created }
        if let modified = attrs[.modificationDate] { dates[.modificationDate] = modified }
        if !dates.isEmpty {
            try fileManager.setAttributes(dates, ofItemAtPath: destination.path)
        }
    }

    public enum CopyError: LocalizedError {
        case cannotOpenSource(String)
        case cannotCreateDestination(String)
        case copyItemFailed(source: String, destination: String, reason: String)
        case readFailed(String)
        case writeFailed(String)
        case verificationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .cannotOpenSource(let p): return "Nie można otworzyć pliku źródłowego: \(p)"
            case .cannotCreateDestination(let p): return "Nie można utworzyć folderu docelowego: \(p)"
            case .copyItemFailed(_, let d, let reason): return "Błąd zapisu pliku \(d): \(reason)"
            case .readFailed(let p): return "Błąd odczytu pliku: \(p)"
            case .writeFailed(let p): return "Błąd zapisu pliku: \(p)"
            case .verificationFailed(let p): return "Kopia różni się od oryginału (błąd weryfikacji SHA-256): \(p)"
            }
        }
    }
}
