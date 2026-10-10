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

/// Bezpieczna wątkowo flaga anulowania zgrywania — ustawiana z interfejsu,
/// sprawdzana przez `CopyService` między plikami i w trakcie kopiowania każdego pliku.
public final class CancellationToken {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Postęp zgrywania jednej partii plików (jednej karty).
public struct CopyProgress {
    /// Bajty plików już obsłużonych (skopiowanych, pominiętych lub nieudanych)
    /// powiększone o skopiowaną część bieżącego pliku.
    public let processedBytes: Int64
    /// Bajty faktycznie przeniesione z karty (bez pominiętych duplikatów) — do liczenia prędkości.
    public let transferredBytes: Int64
    public let totalBytes: Int64
    public let filesDone: Int
    public let totalFiles: Int
    public let currentFile: URL

    /// Postęp 0.0...1.0 liczony w bajtach (gdy rozmiary są nieznane — w plikach).
    public var fraction: Double {
        if totalBytes > 0 {
            return min(1, Double(processedBytes) / Double(totalBytes))
        }
        return totalFiles > 0 ? Double(filesDone) / Double(totalFiles) : 1
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
    /// Zgrywanie przerwane przez użytkownika — pozostałe pliki nie były przetwarzane.
    public var wasCancelled = false
    /// Sumy SHA-256 zapisanych plików (gdy weryfikacja jest włączona) — do raportu zgrania.
    public var checksums: [URL: String] = [:]
    /// Pliki zapisane w drugim miejscu docelowym (kopia zapasowa).
    public var backupCopied: [URL] = []
    /// Pliki, które były już w kopii zapasowej.
    public var backupSkipped: [URL] = []
    /// Skopiowane pliki towarzyszące (Sony XML, DJI SRT, XMP) — na dysku docelowym i w kopii.
    public var sidecarsCopied: [URL] = []

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
    public let cancellation: CancellationToken
    /// Czy razem z materiałem zgrywać pliki towarzyszące (XML, SRT, XMP).
    public let copySidecars: Bool
    private let fileManager = FileManager.default
    private static let bufferSize = 8 * 1024 * 1024

    /// Wywoływane po każdym pliku oraz w trakcie kopiowania dużych plików (co blok 8 MB).
    /// Wywołania przychodzą z wątku, na którym działa `copy` — nie z wątku głównego.
    public var onProgress: ((CopyProgress) -> Void)?

    public init(
        verifyChecksums: Bool,
        verifyCopies: Bool = false,
        copySidecars: Bool = false,
        cancellation: CancellationToken = CancellationToken()
    ) {
        self.verifyChecksums = verifyChecksums
        self.verifyCopies = verifyCopies
        self.copySidecars = copySidecars
        self.cancellation = cancellation
    }

    /// Kopiuje pliki do struktury projektu (z opcjonalnym podfolderem kamery) i zwraca raport.
    ///
    /// Błąd pojedynczego pliku nie przerywa zgrywania — trafia do `CopyReport.failed`,
    /// a kopiowanie przechodzi do kolejnego pliku. Wyjątek rzucany jest tylko wtedy,
    /// gdy nie da się utworzyć katalogów docelowych. Po anulowaniu (`cancellation`) bieżący
    /// plik jest porzucany bez śladu, a raport ma ustawione `wasCancelled`.
    ///
    /// Z `backupLayout` każdy plik trafia też do drugiego miejsca (kopia zapasowa o tej samej
    /// strukturze). Kopia powstaje ze świeżo zapisanego pliku na dysku docelowym, więc karta
    /// jest czytana tylko raz; błąd kopii zapasowej trafia do `failed` z dopiskiem.
    public func copy(
        files: [MediaFile],
        to layout: ProjectLayout,
        cameraLabel: String? = nil,
        backupLayout: ProjectLayout? = nil
    ) throws -> CopyReport {
        var report = CopyReport()
        let total = files.count
        let destinationCount: Int64 = backupLayout == nil ? 1 : 2
        let totalBytes = files.reduce(Int64(0)) { $0 + $1.size } * destinationCount
        var done = 0
        var processedBytes: Int64 = 0
        var transferredBytes: Int64 = 0
        var sourceDirectoryListings: [URL: [String]] = [:]

        func emitProgress(_ file: URL, currentFileBytes: Int64 = 0) {
            onProgress?(CopyProgress(
                processedBytes: processedBytes + currentFileBytes,
                transferredBytes: transferredBytes + currentFileBytes,
                totalBytes: totalBytes,
                filesDone: done,
                totalFiles: total,
                currentFile: file
            ))
        }

        // Zapewnij istnienie katalogów docelowych; zbiór nazw już zajętych w każdym
        // katalogu służy do wykrywania kolizji.
        var existingNamesByCategory = try prepareTargets(in: layout, cameraLabel: cameraLabel)
        var backupNamesByCategory = try backupLayout.map { try prepareTargets(in: $0, cameraLabel: cameraLabel) } ?? [:]

        fileLoop: for file in files {
            if cancellation.isCancelled {
                report.wasCancelled = true
                break
            }

            let destDir = layout.targetDirectory(for: file.category, cameraLabel: cameraLabel)
            let decision = CopyPlanner.decision(
                source: file.url,
                destinationDirectory: destDir,
                verifyChecksums: verifyChecksums,
                existingNames: existingNamesByCategory[file.category] ?? []
            )

            // Plik zapisany teraz na dysku docelowym — źródło kopii zapasowej.
            var freshPrimaryCopy: URL?
            var primaryFailed = false

            switch decision {
            case .skipDuplicate:
                report.skipped.append(file.url)
            case .copyAsIs(let dest), .copy(let dest):
                do {
                    let result = try copyFile(from: file.url, to: dest) { copiedSoFar in
                        emitProgress(file.url, currentFileBytes: copiedSoFar)
                    }
                    report.copied.append(dest)
                    report.totalBytesCopied += result.bytes
                    transferredBytes += result.bytes
                    if let checksum = result.checksum {
                        report.verified.append(dest)
                        report.checksums[dest] = checksum
                    }
                    existingNamesByCategory[file.category, default: []].insert(dest.lastPathComponent)
                    freshPrimaryCopy = dest
                    if copySidecars {
                        copySidecarFiles(of: file.url, nextTo: dest, listings: &sourceDirectoryListings, report: &report)
                    }
                } catch CopyError.cancelled {
                    report.wasCancelled = true
                    break fileLoop
                } catch {
                    primaryFailed = true
                    report.failed.append(FailedCopy(url: file.url, error: error.localizedDescription))
                }
            }
            processedBytes += file.size

            if let backupLayout {
                if !primaryFailed {
                    let backupDir = backupLayout.targetDirectory(for: file.category, cameraLabel: cameraLabel)
                    let backupDecision = CopyPlanner.decision(
                        source: file.url,
                        destinationDirectory: backupDir,
                        verifyChecksums: verifyChecksums,
                        existingNames: backupNamesByCategory[file.category] ?? []
                    )
                    switch backupDecision {
                    case .skipDuplicate:
                        report.backupSkipped.append(file.url)
                    case .copyAsIs(let dest), .copy(let dest):
                        do {
                            let result = try copyFile(from: freshPrimaryCopy ?? file.url, to: dest) { copiedSoFar in
                                emitProgress(file.url, currentFileBytes: copiedSoFar)
                            }
                            report.backupCopied.append(dest)
                            transferredBytes += result.bytes
                            if let checksum = result.checksum {
                                report.checksums[dest] = checksum
                            }
                            backupNamesByCategory[file.category, default: []].insert(dest.lastPathComponent)
                            if copySidecars {
                                copySidecarFiles(of: file.url, nextTo: dest, listings: &sourceDirectoryListings, report: &report)
                            }
                        } catch CopyError.cancelled {
                            report.wasCancelled = true
                            break fileLoop
                        } catch {
                            report.failed.append(FailedCopy(
                                url: file.url,
                                error: "Kopia zapasowa: \(error.localizedDescription)"
                            ))
                        }
                    }
                }
                processedBytes += file.size
            }

            done += 1
            emitProgress(file.url)
        }
        return report
    }

    /// Tworzy katalogi projektu i kamery; zwraca nazwy plików już obecnych w katalogach kamery.
    private func prepareTargets(in layout: ProjectLayout, cameraLabel: String?) throws -> [MediaCategory: Set<String>] {
        try fileManager.createDirectory(at: layout.videoDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.audioDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.photoDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: layout.daVinciDir, withIntermediateDirectories: true)

        var names: [MediaCategory: Set<String>] = [:]
        for category in MediaCategory.allCases {
            let target = layout.targetDirectory(for: category, cameraLabel: cameraLabel)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            names[category] = Set(initialNames(of: target))
        }
        return names
    }

    // MARK: – Pliki towarzyszące

    /// Rozszerzenia plików towarzyszących materiałowi (metadane, telemetria, ustawienia RAW).
    public static let sidecarExtensions: Set<String> = ["xml", "srt", "xmp"]

    /// Pliki towarzyszące materiału z tego samego katalogu: o tej samej nazwie (DJI `.SRT`,
    /// `.XMP`) albo z sufiksem Sony `M01` (`C0001.MP4` → `C0001M01.XML`).
    static func sidecarFiles(of media: URL, directoryListing: [String]) -> [URL] {
        let directory = media.deletingLastPathComponent()
        let stem = media.deletingPathExtension().lastPathComponent
        return directoryListing.compactMap { name -> URL? in
            let url = directory.appendingPathComponent(name)
            guard sidecarExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let candidateStem = url.deletingPathExtension().lastPathComponent
            guard candidateStem.hasPrefix(stem) else { return nil }
            let suffix = candidateStem.dropFirst(stem.count)
            let isSonySuffix = suffix.count == 3 && suffix.first == "M" && suffix.dropFirst().allSatisfy(\.isNumber)
            return suffix.isEmpty || isSonySuffix ? url : nil
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Kopiuje pliki towarzyszące obok zapisanego materiału. Nazwa podąża za nazwą materiału
    /// (np. `C0001_1.MP4` → `C0001_1M01.XML`). Istniejące pliki nie są nadpisywane; błędy
    /// plików towarzyszących nie są krytyczne i nie blokują zgrywania.
    private func copySidecarFiles(
        of media: URL,
        nextTo mediaDestination: URL,
        listings: inout [URL: [String]],
        report: inout CopyReport
    ) {
        let sourceDirectory = media.deletingLastPathComponent()
        if listings[sourceDirectory] == nil {
            listings[sourceDirectory] = (try? fileManager.contentsOfDirectory(atPath: sourceDirectory.path)) ?? []
        }
        let sourceStem = media.deletingPathExtension().lastPathComponent
        let destinationStem = mediaDestination.deletingPathExtension().lastPathComponent
        let destinationDirectory = mediaDestination.deletingLastPathComponent()

        for sidecar in Self.sidecarFiles(of: media, directoryListing: listings[sourceDirectory] ?? []) {
            let suffix = sidecar.deletingPathExtension().lastPathComponent.dropFirst(sourceStem.count)
            let name = "\(destinationStem)\(suffix).\(sidecar.pathExtension)"
            let target = destinationDirectory.appendingPathComponent(name)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            if (try? fileManager.copyItem(at: sidecar, to: target)) != nil {
                report.sidecarsCopied.append(target)
            }
        }
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
    private struct CopiedFile {
        let bytes: Int64
        /// SHA-256 kopii (potwierdzona zgodność z oryginałem), gdy weryfikacja jest włączona.
        let checksum: String?
    }

    private func copyFile(from source: URL, to destination: URL, onChunk: (Int64) -> Void) throws -> CopiedFile {
        // Upewnij się, że katalog docelowy istnieje
        let parentDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let partial = parentDir.appendingPathComponent(".\(destination.lastPathComponent).part")
        // Pozostałość po wcześniej przerwanym kopiowaniu.
        try? fileManager.removeItem(at: partial)

        let sourceHash: String?
        do {
            sourceHash = try streamCopy(from: source, to: partial, computeHash: verifyCopies, onChunk: onChunk)
            if let sourceHash {
                let copyHash = try Self.checksum(of: partial, bypassingCache: true)
                guard sourceHash == copyHash else {
                    throw CopyError.verificationFailed(source.path)
                }
            }
            try copyTimestamps(from: source, to: partial)
            try fileManager.moveItem(at: partial, to: destination)
        } catch let error as CopyError {
            try? fileManager.removeItem(at: partial)
            throw error
        } catch {
            try? fileManager.removeItem(at: partial)
            throw CopyError.copyItemFailed(source: source.path, destination: destination.path, reason: error.localizedDescription)
        }

        let attrs = try? fileManager.attributesOfItem(atPath: destination.path)
        return CopiedFile(bytes: (attrs?[.size] as? Int64) ?? 0, checksum: sourceHash)
    }

    /// Kopiuje plik strumieniowo blokami, raportując postęp i sprawdzając anulowanie.
    /// Z `computeHash` jednocześnie liczy SHA-256 odczytanych danych (karta jest czytana
    /// tylko raz) i zwraca checksum oryginału.
    private func streamCopy(
        from source: URL,
        to destination: URL,
        computeHash: Bool,
        onChunk: (Int64) -> Void
    ) throws -> String? {
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw CopyError.cannotCreateDestination(destination.path)
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        if computeHash {
            // Zapis z pominięciem pamięci podręcznej, aby weryfikacja czytała dane z dysku.
            Self.disableCache(for: output)
        }

        var hasher: SHA256Hasher? = computeHash ? SHA256Hasher() : nil
        var written: Int64 = 0
        while let chunk = try autoreleasepool(invoking: { try input.read(upToCount: Self.bufferSize) }),
              !chunk.isEmpty {
            if cancellation.isCancelled {
                throw CopyError.cancelled
            }
            hasher?.update(chunk)
            try output.write(contentsOf: chunk)
            written += Int64(chunk.count)
            onChunk(written)
        }
        try output.synchronize()
        return hasher?.finalize()
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
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .cannotOpenSource(let p): return "Nie można otworzyć pliku źródłowego: \(p)"
            case .cannotCreateDestination(let p): return "Nie można utworzyć folderu docelowego: \(p)"
            case .copyItemFailed(_, let d, let reason): return "Błąd zapisu pliku \(d): \(reason)"
            case .readFailed(let p): return "Błąd odczytu pliku: \(p)"
            case .writeFailed(let p): return "Błąd zapisu pliku: \(p)"
            case .verificationFailed(let p): return "Kopia różni się od oryginału (błąd weryfikacji SHA-256): \(p)"
            case .cancelled: return "Zgrywanie anulowane."
            }
        }
    }
}
