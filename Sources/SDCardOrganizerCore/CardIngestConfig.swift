import Foundation

/// Stan i konfiguracja pojedynczej karty SD podłączonej do Maca.
public struct CardIngestConfig: Identifiable, Equatable {
    public let id: String // URL path
    public let volumeName: String
    public let volumeURL: URL
    public let totalCapacity: Int?
    public let availableCapacity: Int?

    /// Nazwa kamery lub zastosowania (np. "Kamera A", "Kamera B", "Dron DJI", "Kask GoPro")
    public var cameraLabel: String

    /// Czy karta jest zaznaczona do zgrania
    public var isEnabled: Bool

    /// Zeskanowane pliki
    public var scannedFiles: [MediaFile]

    /// Dostępne dni nagrań
    public var availableDays: [DaySummary]

    /// Wybrane dni nagrań (jeśli puste, a availableDays niepuste -> brak wyboru)
    public var selectedDays: Set<String>

    /// Status operacji
    public var isScanning: Bool
    public var isCopying: Bool
    public var progress: Double
    public var currentFile: String
    public var lastReport: CopyReport?
    public var errorMessage: String?

    public init(
        volumeURL: URL,
        volumeName: String,
        totalCapacity: Int? = nil,
        availableCapacity: Int? = nil,
        cameraLabel: String = "",
        isEnabled: Bool = true
    ) {
        self.id = volumeURL.path
        self.volumeURL = volumeURL
        self.volumeName = volumeName
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.cameraLabel = cameraLabel
        self.isEnabled = isEnabled
        self.scannedFiles = []
        self.availableDays = []
        self.selectedDays = []
        self.isScanning = false
        self.isCopying = false
        self.progress = 0
        self.currentFile = ""
        self.lastReport = nil
        self.errorMessage = nil
    }

    /// Pliki pasujące do wybranych dni
    public var filteredFiles: [MediaFile] {
        if selectedDays.isEmpty {
            return scannedFiles
        }
        return scannedFiles.filter { selectedDays.contains($0.dayString) }
    }

    /// Łączny rozmiar wybranych plików
    public var totalSelectedBytes: Int64 {
        filteredFiles.reduce(0) { $0 + $1.size }
    }

    /// Szybki wybór najnowszego dnia
    public mutating func selectLatestDay() {
        if let latest = availableDays.first?.dayString {
            selectedDays = [latest]
        }
    }

    /// Zaznaczenie wszystkich dni
    public mutating func selectAllDays() {
        selectedDays = Set(availableDays.map(\.dayString))
    }

    /// Przełączenie konkretnego dnia
    public mutating func toggleDay(_ dayString: String) {
        if selectedDays.contains(dayString) {
            selectedDays.remove(dayString)
        } else {
            selectedDays.insert(dayString)
        }
    }

    /// Aktualizacja po zakończeniu skanowania
    public mutating func setScanResults(_ results: [MediaFile]) {
        self.scannedFiles = results
        let grouped = Dictionary(grouping: results, by: { $0.dayString })
        let days = grouped.map { DaySummary(dayString: $0.key, files: $0.value) }
            .sorted { $0.dayString > $1.dayString }
        self.availableDays = days
        // Domyślnie zaznaczamy najnowszy dzień
        if let latest = days.first?.dayString {
            self.selectedDays = [latest]
        } else {
            self.selectedDays = []
        }
    }
}
