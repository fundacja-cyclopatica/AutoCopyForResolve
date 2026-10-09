import Foundation

/// Stan i konfiguracja pojedynczej karty SD podłączonej do Maca.
public struct CardIngestConfig: Identifiable, Equatable {
    public let id: String // URL path
    public var volumeName: String
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

    /// Filtry typów mediów dla danej karty
    public var includeVideos: Bool
    public var includePhotos: Bool
    public var includeAudio: Bool

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
        isEnabled: Bool = true,
        includeVideos: Bool = true,
        includePhotos: Bool = true,
        includeAudio: Bool = true
    ) {
        self.id = volumeURL.path
        self.volumeURL = volumeURL
        self.volumeName = volumeName
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.cameraLabel = cameraLabel
        self.isEnabled = isEnabled
        self.includeVideos = includeVideos
        self.includePhotos = includePhotos
        self.includeAudio = includeAudio
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

    /// Pliki pasujące do wybranych dni oraz zaznaczonych typów (filmy/zdjęcia/audio)
    public var filteredFiles: [MediaFile] {
        let dayFiltered: [MediaFile]
        if selectedDays.isEmpty {
            dayFiltered = scannedFiles
        } else {
            dayFiltered = scannedFiles.filter { selectedDays.contains($0.dayString) }
        }

        return dayFiltered.filter { file in
            switch file.category {
            case .video: return includeVideos
            case .photo: return includePhotos
            case .audio: return includeAudio
            }
        }
    }

    /// Łączny rozmiar wybranych plików
    public var totalSelectedBytes: Int64 {
        filteredFiles.reduce(0) { $0 + $1.size }
    }

    /// Łączny rozmiar wideo na karcie
    public var videoBytes: Int64 {
        scannedFiles.filter { $0.category == .video }.reduce(0) { $0 + $1.size }
    }

    /// Łączny rozmiar zdjęć na karcie
    public var photoBytes: Int64 {
        scannedFiles.filter { $0.category == .photo }.reduce(0) { $0 + $1.size }
    }

    /// Łączny rozmiar audio na karcie
    public var audioBytes: Int64 {
        scannedFiles.filter { $0.category == .audio }.reduce(0) { $0 + $1.size }
    }

    public var totalVideoCount: Int {
        scannedFiles.filter { $0.category == .video }.count
    }

    public var totalPhotoCount: Int {
        scannedFiles.filter { $0.category == .photo }.count
    }

    public var totalAudioCount: Int {
        scannedFiles.filter { $0.category == .audio }.count
    }

    /// Procent wolnego miejsca (0-100)
    public var freePercent: Int {
        guard let total = totalCapacity, let avail = availableCapacity, total > 0 else { return 50 }
        return max(0, min(100, Int((Double(avail) / Double(total)) * 100)))
    }

    /// Proporcja zajętości przez wideo (0.0 - 1.0)
    public var videoPercent: Double {
        guard let total = totalCapacity, total > 0 else { return 0.2 }
        return max(0.02, min(0.9, Double(videoBytes) / Double(total)))
    }

    /// Proporcja zajętości przez zdjęcia (0.0 - 1.0)
    public var photoPercent: Double {
        guard let total = totalCapacity, total > 0 else { return 0.05 }
        return max(0.01, min(0.9, Double(photoBytes) / Double(total)))
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
