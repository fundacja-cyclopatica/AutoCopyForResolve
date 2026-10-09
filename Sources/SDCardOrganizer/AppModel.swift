import Foundation
import AppKit
import Combine
import UserNotifications
import SDCardOrganizerCore

/// Obserwowalny model stanu aplikacji — zarządza do 4 kartami SD, ustawieniami i zgrywaniem.
public final class AppModel: ObservableObject {
    public static let showMainWindowNotification = Notification.Name("SDCardOrganizer.showMainWindow")

    @Published public var settings: Settings {
        didSet { persistSettings() }
    }

    /// Konfiguracje podłączonych kart (maksymalnie 4 karty obok siebie)
    @Published public var cardConfigs: [CardIngestConfig] = []

    /// Globalna nazwa projektu
    @Published public var projectName: String = ""

    /// Stan globalny zgrywania
    @Published public var isGlobalCopying: Bool = false
    @Published public var overallProgress: Double = 0
    @Published public var statusMessage: String = ""
    @Published public var statusIsError: Bool = false

    /// Historia i nawigacja
    @Published public var history: [IngestRecord] = []
    @Published public var selectedTab: Int = 0

    /// Dialog zmiany nazwy karty
    @Published public var renamingCardURL: URL? = nil
    @Published public var renameInputText: String = ""

    /// Zarządzanie presetami kamer
    @Published public var newPresetInputText: String = ""
    @Published public var isShowingPresetSheet: Bool = false

    public let volumeMonitor = VolumeMonitor()

    private let settingsURL: URL
    private var cancellables = Set<AnyCancellable>()
    private var knownVolumeIDs = Set<String>()

    private let defaultLabels = ["Kamera A", "Kamera B", "Kamera C", "Dron"]

    public init(settingsURL: URL = Settings.defaultSettingsURL()) {
        self.settingsURL = settingsURL
        self.settings = (try? SettingsStore.load(from: settingsURL)) ?? Settings()
        self.history = IngestHistory.load()

        // Poproś o uprawnienia do powiadomień
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Reaguj na zmiany podłączonych kart
        volumeMonitor.$removableVolumes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volumes in
                self?.handleVolumesChanged(volumes)
            }
            .store(in: &cancellables)
    }

    private func persistSettings() {
        try? SettingsStore.save(settings, to: settingsURL)
    }

    // MARK: – Właściwości wyliczeniowe dla wszystkich kart

    /// Karty zaznaczone do zgrywania
    public var enabledCards: [CardIngestConfig] {
        cardConfigs.filter { $0.isEnabled }
    }

    /// Łączna liczba plików do zgrania ze wszystkich zaznaczonych kart
    public var totalFilesToCopy: Int {
        enabledCards.reduce(0) { $0 + $1.filteredFiles.count }
    }

    /// Łączny rozmiar w bajtach do zgrania ze wszystkich zaznaczonych kart
    public var totalBytesToCopy: Int64 {
        enabledCards.reduce(0) { $0 + $1.totalSelectedBytes }
    }

    // MARK: – Obsługa wykrywania kart

    private func handleVolumesChanged(_ volumes: [Volume]) {
        let currentIDs = Set(volumes.map(\.id))
        let newIDs = currentIDs.subtracting(knownVolumeIDs)
        knownVolumeIDs = currentIDs

        // Ograniczenie do maksymalnie 4 kart
        let limitedVolumes = Array(volumes.prefix(4))

        // Zachowaj istniejące konfiguracje dla wciąż podłączonych kart
        var newConfigs: [CardIngestConfig] = []

        for (index, volume) in limitedVolumes.enumerated() {
            if let existing = cardConfigs.first(where: { $0.volumeURL == volume.url }) {
                newConfigs.append(existing)
            } else {
                let defaultLabel = index < defaultLabels.count ? defaultLabels[index] : "Kamera \(index + 1)"
                let config = CardIngestConfig(
                    volumeURL: volume.url,
                    volumeName: volume.name,
                    totalCapacity: volume.totalCapacity,
                    availableCapacity: volume.availableCapacity,
                    cameraLabel: defaultLabel,
                    isEnabled: true
                )
                newConfigs.append(config)
            }
        }

        self.cardConfigs = newConfigs

        // Jeśli podłączono nową kartę -> powiadomienie, auto-skan i pop-up okna
        if let newID = newIDs.first, let newVol = volumes.first(where: { $0.id == newID }) {
            sendNotification(
                title: "Wykryto kartę SD",
                body: "Karta „\(newVol.name)” jest gotowa do zgrywania."
            )

            // Przeskanuj nowo podłączoną kartę
            scanCard(url: newVol.url)

            // Automatycznie otwórz i wysuń okno aplikacji na pierwszy plan (pop-up)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: AppModel.showMainWindowNotification, object: nil)
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeKey {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        } else {
            // Przeskanuj wszystkie karty, które nie mają jeszcze wyników
            for config in cardConfigs where config.scannedFiles.isEmpty && !config.isScanning {
                scanCard(url: config.volumeURL)
            }
        }
    }

    /// Wysyła powiadomienie systemowe macOS.
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: – Skanowanie kart

    public func scanCard(url: URL) {
        guard let index = cardConfigs.firstIndex(where: { $0.volumeURL == url }) else { return }
        cardConfigs[index].isScanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let scanner = MediaScanner(enabledExtensions: self.settings.enabledExtensions)
            let results = (try? scanner.scan(volumeRoot: url)) ?? []

            DispatchQueue.main.async {
                if let idx = self.cardConfigs.firstIndex(where: { $0.volumeURL == url }) {
                    self.cardConfigs[idx].isScanning = false
                    self.cardConfigs[idx].setScanResults(results)
                }
            }
        }
    }

    public func scanAllCards() {
        for config in cardConfigs {
            scanCard(url: config.volumeURL)
        }
    }

    // MARK: – Zarządzanie wolumenami (Wysuwanie i Zmiana nazwy)

    public func ejectCard(url: URL) {
        do {
            try VolumeManager.eject(url: url)
            volumeMonitor.refresh()
            setStatus("Karta została bezpiecznie wysunięta.", isError: false)
        } catch {
            setStatus("Błąd wysuwania karty: \(error.localizedDescription)", isError: true)
        }
    }

    public func renameCard(url: URL, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try VolumeManager.renameVolume(at: url, to: trimmed)
            volumeMonitor.refresh()
            setStatus("Zmieniono nazwę karty na „\(trimmed)”.", isError: false)
        } catch {
            setStatus("Błąd zmiany nazwy karty: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: – Zgrywanie materiałów z wielu kart

    public func startBatchCopy() {
        let cardsToIngest = enabledCards.filter { !$0.filteredFiles.isEmpty }

        guard !cardsToIngest.isEmpty else {
            setStatus("Brak wybranych materiałów do zgrania.", isError: true)
            return
        }

        guard !settings.destinationRoot.isEmpty else {
            setStatus("Nie wybrano dysku docelowego. Ustaw go w ustawieniach.", isError: true)
            return
        }

        let name = ProjectLayout.sanitize(projectName)
        guard !name.isEmpty else {
            setStatus("Podaj nazwę projektu.", isError: true)
            return
        }

        isGlobalCopying = true
        overallProgress = 0
        statusMessage = ""
        statusIsError = false

        let totalFilesAllCards = cardsToIngest.reduce(0) { $0 + $1.filteredFiles.count }
        var completedFilesAllCards = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let builder = ProjectBuilder(settings: self.settings)
                let layout = try builder.build(projectName: name)

                var totalCopiedOverall = 0
                var totalSkippedOverall = 0
                var totalFailedOverall = 0
                var totalBytesOverall: Int64 = 0

                for card in cardsToIngest {
                    guard let cardIdx = self.cardConfigs.firstIndex(where: { $0.volumeURL == card.volumeURL }) else { continue }

                    DispatchQueue.main.async {
                        self.cardConfigs[cardIdx].isCopying = true
                        self.cardConfigs[cardIdx].progress = 0
                        self.cardConfigs[cardIdx].currentFile = ""
                    }

                    let service = CopyService(verifyChecksums: self.settings.verifyChecksums)
                    service.onProgress = { [weak self] fraction, fileURL in
                        DispatchQueue.main.async {
                            guard let self, let idx = self.cardConfigs.firstIndex(where: { $0.volumeURL == card.volumeURL }) else { return }
                            self.cardConfigs[idx].progress = fraction
                            self.cardConfigs[idx].currentFile = fileURL.lastPathComponent
                        }
                    }

                    let report = try service.copy(
                        files: card.filteredFiles,
                        to: layout,
                        cameraLabel: card.cameraLabel
                    )

                    totalCopiedOverall += report.totalCopied
                    totalSkippedOverall += report.totalSkipped
                    totalFailedOverall += report.totalFailed
                    totalBytesOverall += report.totalBytesCopied
                    completedFilesAllCards += card.filteredFiles.count

                    let overallFraction = totalFilesAllCards > 0 ? Double(completedFilesAllCards) / Double(totalFilesAllCards) : 1.0

                    DispatchQueue.main.async {
                        if let idx = self.cardConfigs.firstIndex(where: { $0.volumeURL == card.volumeURL }) {
                            self.cardConfigs[idx].isCopying = false
                            self.cardConfigs[idx].progress = 1.0
                            self.cardConfigs[idx].lastReport = report
                        }
                        self.overallProgress = overallFraction
                    }
                }

                // Zapisz wpis w historii dla sesji zgrywania
                let sourceSummary = cardsToIngest.map { "\($0.cameraLabel.isEmpty ? $0.volumeName : $0.cameraLabel) (\($0.volumeName))" }.joined(separator: ", ")
                let record = IngestRecord(
                    projectName: name,
                    sourceVolumeName: sourceSummary,
                    destinationPath: layout.root.path,
                    filesCopied: totalCopiedOverall,
                    filesSkipped: totalSkippedOverall,
                    filesFailed: totalFailedOverall,
                    totalBytes: totalBytesOverall
                )
                IngestHistory.append(record)

                // Uruchom aplikacje docelowe (Resolve / Lightroom)
                if self.settings.openInDaVinciResolve {
                    self.launchDaVinciResolve(layout: layout)
                }
                if self.settings.openInLightroom {
                    self.launchLightroom(layout: layout)
                }

                DispatchQueue.main.async {
                    self.isGlobalCopying = false
                    self.overallProgress = 1.0
                    self.history = IngestHistory.load()
                    self.setStatus(
                        "Zgrano \(totalCopiedOverall) plików (\(AppModel.formatBytes(totalBytesOverall))) z \(cardsToIngest.count) kart.",
                        isError: totalFailedOverall > 0
                    )
                    self.sendNotification(
                        title: "Zgrywanie zakończone pomyślnie",
                        body: "Projekt „\(name)”: zgrano \(totalCopiedOverall) plików z \(cardsToIngest.count) kart."
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGlobalCopying = false
                    self.setStatus("Błąd zgrywania: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    // MARK: – Otwieranie DaVinci Resolve i Lightroom

    private func launchDaVinciResolve(layout: ProjectLayout) {
        let drpFile = layout.drpFileURL()
        if FileManager.default.fileExists(atPath: drpFile.path) && (try? drpFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 {
            NSWorkspace.shared.open(drpFile)
        } else {
            // Otwórz samą aplikację DaVinci Resolve
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "DaVinci Resolve"]
            try? process.run()
        }
    }

    private func launchLightroom(layout: ProjectLayout) {
        let photoFolder = layout.photoDir
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Spróbuj otworzyć folder ze zdjęciami w Adobe Lightroom
        process.arguments = ["-a", "Adobe Lightroom", photoFolder.path]
        try? process.run()
    }

    // MARK: – Zarządzanie presetami podpisów kamer

    public func addCameraPreset(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.cameraPresets.contains(trimmed) else { return }
        settings.cameraPresets.append(trimmed)
    }

    public func removeCameraPreset(at index: Int) {
        guard settings.cameraPresets.indices.contains(index) else { return }
        settings.cameraPresets.remove(at: index)
    }

    public func updateCameraPreset(at index: Int, with name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, settings.cameraPresets.indices.contains(index) else { return }
        settings.cameraPresets[index] = trimmed
    }

    /// Formatuje rozmiar w bajtach na czytelny tekst.
    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
