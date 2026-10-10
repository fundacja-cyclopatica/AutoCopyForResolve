import Foundation

/// Zapisuje w folderze projektu raport zgrania: podsumowanie (plik `.txt`) oraz listę sum
/// SHA-256 w formacie `shasum -a 256 -c` (plik `.sha256`), dzięki której można później
/// sprawdzić, czy materiał na dysku nie uległ uszkodzeniu.
public enum IngestReportWriter {
    /// Fragment raportu dla jednej karty.
    public struct Section {
        public let title: String
        public let report: CopyReport

        public init(title: String, report: CopyReport) {
            self.title = title
            self.report = report
        }
    }

    /// Zapisane pliki raportu.
    public struct WrittenFiles: Equatable {
        public let summary: URL
        /// `nil`, gdy nie ma sum kontrolnych (weryfikacja wyłączona albo nic nie skopiowano).
        public let checksums: URL?
    }

    /// Zapisuje raport w `projectRoot`. Sumy kontrolne obejmują tylko pliki leżące w tym
    /// folderze (osobny raport powstaje w kopii zapasowej).
    @discardableResult
    public static func write(
        projectRoot: URL,
        projectName: String,
        sections: [Section],
        wasCancelled: Bool,
        date: Date = Date()
    ) throws -> WrittenFiles {
        let stamp = Self.stamp(date)
        let checksumLines = checksumLines(in: projectRoot, sections: sections)

        var checksumsURL: URL?
        if !checksumLines.isEmpty {
            let url = projectRoot.appendingPathComponent("Sumy_kontrolne_\(stamp).sha256")
            try (checksumLines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            checksumsURL = url
        }

        let summaryURL = projectRoot.appendingPathComponent("Raport_zgrania_\(stamp).txt")
        let text = summaryText(
            projectName: projectName,
            sections: sections,
            wasCancelled: wasCancelled,
            date: date,
            checksumsFileName: checksumsURL?.lastPathComponent
        )
        try text.write(to: summaryURL, atomically: true, encoding: .utf8)
        return WrittenFiles(summary: summaryURL, checksums: checksumsURL)
    }

    /// Linie `<sha256>  <ścieżka względna>` dla plików w `root`, posortowane po ścieżce.
    static func checksumLines(in root: URL, sections: [Section]) -> [String] {
        let rootPath = root.standardizedFileURL.path + "/"
        var lines: [(path: String, hash: String)] = []
        for section in sections {
            for (url, hash) in section.report.checksums {
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(rootPath) else { continue }
                lines.append((String(path.dropFirst(rootPath.count)), hash))
            }
        }
        return lines.sorted { $0.path < $1.path }.map { "\($0.hash)  \($0.path)" }
    }

    static func summaryText(
        projectName: String,
        sections: [Section],
        wasCancelled: Bool,
        date: Date,
        checksumsFileName: String?
    ) -> String {
        let failures = sections.reduce(0) { $0 + $1.report.totalFailed }
        let status: String
        if wasCancelled {
            status = "przerwane przez użytkownika"
        } else if failures > 0 {
            status = "zakończone z błędami (\(PolishPlural.errors(failures)))"
        } else {
            status = "zakończone pomyślnie"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var lines = [
            "Raport zgrania — SD Card Organizer",
            "Projekt: \(projectName)",
            "Data: \(dateFormatter.string(from: date))",
            "Status: \(status)",
            ""
        ]

        for section in sections {
            let report = section.report
            lines.append("[\(section.title)]")
            var counts = [
                "skopiowano \(PolishPlural.files(report.totalCopied))",
                "pominięto (już zgrane) \(report.totalSkipped)",
                "zweryfikowano SHA-256 \(report.totalVerified)"
            ]
            if !report.backupCopied.isEmpty || !report.backupSkipped.isEmpty {
                counts.append("kopia zapasowa \(report.backupCopied.count) (+\(report.backupSkipped.count) już obecnych)")
            }
            if !report.sidecarsCopied.isEmpty {
                counts.append("pliki towarzyszące \(report.sidecarsCopied.count)")
            }
            counts.append("błędy \(report.totalFailed)")
            lines.append(counts.joined(separator: ", "))
            for failure in report.failed {
                lines.append("  BŁĄD: \(failure.url.lastPathComponent): \(failure.error)")
            }
            lines.append("")
        }

        if let checksumsFileName {
            lines.append("Sumy kontrolne: \(checksumsFileName)")
            lines.append("Sprawdzenie w Terminalu (w folderze projektu): shasum -a 256 -c \"\(checksumsFileName)\"")
        } else {
            lines.append("Sumy kontrolne: brak (weryfikacja SHA-256 była wyłączona).")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
