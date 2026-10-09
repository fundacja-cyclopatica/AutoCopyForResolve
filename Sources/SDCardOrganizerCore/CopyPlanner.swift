import Foundation

/// Wynik decyzji, co zrobić z pojedynczym plikiem źródłowym.
public enum CopyDecision: Equatable {
    /// Plik jest duplikatem istniejącego — pomiń.
    case skipDuplicate
    /// Plik ma kolidującą nazwę (inna zawartość) — kopiuj pod unikalną nazwą.
    case copy(URL)
    /// Plik nie istnieje w miejscu docelowym — kopiuj pod oryginalną nazwą.
    case copyAsIs(URL)
}

/// Planuje zgrywanie plików z karty: decyduje o duplikatach i kolizjach nazw.
public struct CopyPlanner {
    /// Porównuje plik źródłowy z plikiem docelowym i zwraca decyzję.
    ///
    /// - Jeżeli plik docelowy nie istnieje -> `.copyAsIs`.
    /// - Jeżeli plik docelowy istnieje i ma identyczny rozmiar (oraz opcjonalnie checksum)
    ///   -> `.skipDuplicate`.
    /// - W przeciwnym razie (taka sama nazwa, inna zawartość) -> `.copy` pod unikalną nazwą.
    public static func decision(
        source: URL,
        destinationDirectory: URL,
        verifyChecksums: Bool,
        existingNames: Set<String>
    ) -> CopyDecision {
        let directDestination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default

        guard fm.fileExists(atPath: directDestination.path) else {
            return .copyAsIs(directDestination)
        }

        if isSameContent(source: source, destination: directDestination, verifyChecksums: verifyChecksums) {
            return .skipDuplicate
        }

        let unique = UniqueNamer.uniqueURL(for: source, in: destinationDirectory, existingNames: existingNames)
        return .copy(unique)
    }

    /// Porównuje dwa pliki: najpierw rozmiar, opcjonalnie checksum SHA-256.
    static func isSameContent(source: URL, destination: URL, verifyChecksums: Bool) -> Bool {
        let fm = FileManager.default
        let sAttrs = try? fm.attributesOfItem(atPath: source.path)
        let dAttrs = try? fm.attributesOfItem(atPath: destination.path)

        guard let sSize = sAttrs?[.size] as? Int64,
              let dSize = dAttrs?[.size] as? Int64,
              sSize == dSize else {
            return false
        }

        if verifyChecksums {
            guard let sHash = Self.checksum(of: source),
                  let dHash = Self.checksum(of: destination) else {
                return false
            }
            return sHash == dHash
        }
        return true
    }

    /// Oblicza checksum SHA-256 pliku (strumieniowo, bez ładowania całości do pamięci).
    public static func checksum(of url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256Hasher()
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read < 0 { return nil }
            if read == 0 { break }
            hasher.update(buffer[0..<read])
        }
        return hasher.finalize()
    }
}
