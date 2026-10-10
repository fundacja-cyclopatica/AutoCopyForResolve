import Foundation
import SDCardOrganizerCore

/// Bieżący stan zgrywania wyświetlany w dolnym pasku okna.
public struct TransferStatus: Equatable {
    public var processedBytes: Int64
    public var totalBytes: Int64
    /// `nil`, dopóki pomiar prędkości nie jest jeszcze wiarygodny.
    public var bytesPerSecond: Double?
    public var secondsRemaining: Double?
    /// Użytkownik kliknął „Anuluj” — czekamy na przerwanie bieżącego pliku.
    public var isCancelling: Bool = false

    public var fraction: Double {
        totalBytes > 0 ? min(1, Double(processedBytes) / Double(totalBytes)) : 0
    }
}

/// Podsumowanie zakończonej (lub przerwanej) sesji zgrywania, pokazywane w arkuszu.
public struct IngestSessionSummary: Identifiable {
    public struct CardResult: Identifiable {
        public let id: String
        public let title: String
        public let isManual: Bool
        public let report: CopyReport
    }

    public let id = UUID()
    public let projectName: String
    public let destination: URL
    public let cards: [CardResult]
    public let duration: TimeInterval
    public let wasCancelled: Bool
    public let verificationEnabled: Bool
    /// Folder projektu w kopii zapasowej (gdy była włączona).
    public let backupDestination: URL?

    public var totalCopied: Int { cards.reduce(0) { $0 + $1.report.totalCopied } }
    public var totalSkipped: Int { cards.reduce(0) { $0 + $1.report.totalSkipped } }
    public var totalVerified: Int { cards.reduce(0) { $0 + $1.report.totalVerified } }
    public var totalBytes: Int64 { cards.reduce(0) { $0 + $1.report.totalBytesCopied } }
    public var failures: [FailedCopy] { cards.flatMap(\.report.failed) }
    public var totalBackupCopied: Int { cards.reduce(0) { $0 + $1.report.backupCopied.count } }
    public var totalSidecars: Int { cards.reduce(0) { $0 + $1.report.sidecarsCopied.count } }

    /// Średnia prędkość całej sesji (z weryfikacją włącznie).
    public var averageBytesPerSecond: Double? {
        guard duration > 0, totalBytes > 0 else { return nil }
        return Double(totalBytes) / duration
    }

    /// Karty można bezpiecznie wysunąć tylko po pełnym zgraniu bez błędów.
    public var isSafeToEject: Bool {
        !wasCancelled && failures.isEmpty
    }
}
