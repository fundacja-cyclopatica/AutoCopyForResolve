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
    /// Porównuje plik źródłowy z plikami w katalogu docelowym i zwraca decyzję.
    ///
    /// - Jeżeli w katalogu jest już kopia tego pliku — pod oryginalną nazwą albo pod nazwą
    ///   z sufiksem (`nazwa_1.ext`, `nazwa_2.ext`…) nadaną przy wcześniejszej kolizji —
    ///   -> `.skipDuplicate`.
    /// - Jeżeli plik o oryginalnej nazwie nie istnieje -> `.copyAsIs`.
    /// - W przeciwnym razie (taka sama nazwa, inna zawartość) -> `.copy` pod unikalną nazwą.
    public static func decision(
        source: URL,
        destinationDirectory: URL,
        verifyChecksums: Bool,
        existingNames: Set<String>
    ) -> CopyDecision {
        let directDestination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default

        func exists(_ name: String) -> Bool {
            existingNames.contains(name)
                || fm.fileExists(atPath: destinationDirectory.appendingPathComponent(name).path)
        }

        let directExists = exists(source.lastPathComponent)
        if directExists,
           isSameContent(source: source, destination: directDestination, verifyChecksums: verifyChecksums) {
            return .skipDuplicate
        }

        // Kopie z sufiksem są nadawane kolejno (UniqueNamer), więc sprawdzamy je do pierwszej luki.
        var index = 1
        while true {
            let name = UniqueNamer.suffixedName(for: source, index: index)
            guard exists(name) else { break }
            let candidate = destinationDirectory.appendingPathComponent(name)
            if isSameContent(source: source, destination: candidate, verifyChecksums: verifyChecksums) {
                return .skipDuplicate
            }
            index += 1
        }

        guard directExists else {
            return .copyAsIs(directDestination)
        }

        let unique = UniqueNamer.uniqueURL(for: source, in: destinationDirectory, existingNames: existingNames)
        return .copy(unique)
    }

    /// Porównuje dwa pliki.
    ///
    /// Z włączonymi sumami kontrolnymi rozstrzyga SHA-256. Bez nich sam rozmiar nie wystarcza
    /// (przy kodekach o stałym bitrate — BRAW, ProRes, WAV — różne ujęcia tej samej długości
    /// mają identyczny rozmiar), więc porównywana jest też data modyfikacji, którą kopiowanie
    /// zachowuje. Tolerancja 2 s wynika z dokładności dat w systemie plików FAT32.
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

        guard let sDate = sAttrs?[.modificationDate] as? Date,
              let dDate = dAttrs?[.modificationDate] as? Date else {
            return false
        }
        return abs(sDate.timeIntervalSince(dDate)) <= 2
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
