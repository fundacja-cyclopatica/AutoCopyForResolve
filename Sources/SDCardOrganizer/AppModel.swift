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

    /// Stan bocznego panelu ustawień w oknie
    @Published public var isSettingsPanelOpen: Bool = false

    public let volumeMonitor = VolumeMonitor()

    private let settingsURL: URL
    private var cancellables = Set<AnyCancellable>()
    private var knownVolumeIDs = Set<String>()
    private var hasHandledInitialVolumes = false

    /// Maksymalna liczba źródeł (kart i ręcznie dodanych folderów) wyświetlanych obok siebie.
    public static let maxCards = 4

    private let defaultLabels = ["Kamera A", "Kamera B", "Kamera C", "Dron"]

    /// Powiadomienia systemowe działają tylko w aplikacji z pakietem `.app` — przy uruchomieniu
    /// gołej binarki (`swift run`) `UNUserNotificationCenter.current()` kończy proces wyjątkiem.
    private static var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    public init(settingsURL: URL = Settings.defaultSettingsURL()) {
        self.settingsURL = settingsURL
        self.settings = (try? SettingsStore.load(from: settingsURL)) ?? Settings()
        self.history = IngestHistory.load()

        // Poproś o uprawnienia do powiadomień
        if Self.notificationsAvailable {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

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

    public var hasVideos: Bool {
        enabledCards.contains { card in card.filteredFiles.contains { $0.category == .video } }
    }

    public var hasOnlyPhotos: Bool {
        let hasP = enabledCards.contains { card in card.filteredFiles.contains { $0.category == .photo } }
        return hasP && !hasVideos
    }

    /// Szacowany czas transferu przy prędkości magistrali
    public var estimatedTransferInfo: String {
        guard totalBytesToCopy > 0 else { return "Gotowy" }
        let assumedSpeed: Double = 350 * 1024 * 1024
        let seconds = max(1, Int(Double(totalBytesToCopy) / assumedSpeed))
        if seconds < 60 {
            return "~\(seconds)s (~350 MB/s)"
        } else {
            let mins = seconds / 60
            let remSecs = seconds % 60
            return "~\(mins)m \(remSecs)s (~350 MB/s)"
        }
    }

    /// Ręczny wybór folderu lub podłączonego czytnika do slotu
    public func addManualFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Wybierz folder lub podłączoną kartę pamięci"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if cardConfigs.contains(where: { $0.volumeURL.standardizedFileURL == url.standardizedFileURL }) {
            setStatus("Ten folder jest już na liście źródeł.", isError: false)
            return
        }
        guard cardConfigs.count < Self.maxCards else {
            setStatus("Można zgrywać jednocześnie maksymalnie \(Self.maxCards) źródła.", isError: true)
            return
        }

        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let config = CardIngestConfig(
            volumeURL: url,
            volumeName: url.lastPathComponent,
            totalCapacity: values?.volumeTotalCapacity,
            availableCapacity: values?.volumeAvailableCapacity,
            cameraLabel: defaultLabel(for: cardConfigs.count),
            isEnabled: true,
            isManual: true
        )
        cardConfigs.append(config)
        scanCard(url: url)
    }

    private func defaultLabel(for index: Int) -> String {
        index < defaultLabels.count ? defaultLabels[index] : "Kamera \(index + 1)"
    }

    /// Modyfikuje konfigurację karty o podanym `id`. Jeśli karty nie ma już na liście
    /// (np. została wysunięta), nic nie robi. Wywoływać wyłącznie na wątku głównym —
    /// karty identyfikujemy po `id`, nigdy po indeksie, bo lista może się zmienić w każdej chwili.
    private func updateCard(id: String, _ change: (inout CardIngestConfig) -> Void) {
        guard let index = cardConfigs.firstIndex(where: { $0.id == id }) else { return }
        change(&cardConfigs[index])
    }

    // MARK: – Obsługa wykrywania kart

    private func handleVolumesChanged(_ volumes: [Volume]) {
        let currentIDs = Set(volumes.map(\.id))
        let newIDs = currentIDs.subtracting(knownVolumeIDs)
        knownVolumeIDs = currentIDs
        let isInitialLoad = !hasHandledInitialVolumes
        hasHandledInitialVolumes = true

        // Zachowaj istniejące konfiguracje dla wciąż podłączonych kart (maksymalnie 4 źródła)
        var newConfigs: [CardIngestConfig] = []

        for volume in volumes.prefix(Self.maxCards) {
            if let existing = cardConfigs.first(where: { $0.volumeURL == volume.url && !$0.isManual }) {
                newConfigs.append(existing)
            } else {
                let config = CardIngestConfig(
                    volumeURL: volume.url,
                    volumeName: volume.name,
                    totalCapacity: volume.totalCapacity,
                    availableCapacity: volume.availableCapacity,
                    cameraLabel: defaultLabel(for: newConfigs.count),
                    isEnabled: true
                )
                newConfigs.append(config)
            }
        }

        // Ręcznie dodane foldery zostają na liście, dopóki istnieją na dysku.
        for manual in cardConfigs where manual.isManual {
            guard newConfigs.count < Self.maxCards,
                  !newConfigs.contains(where: { $0.volumeURL == manual.volumeURL }),
                  FileManager.default.fileExists(atPath: manual.volumeURL.path) else { continue }
            newConfigs.append(manual)
        }

        self.cardConfigs = newConfigs

        // Przeskanuj nowo podłączone karty oraz te, które nie mają jeszcze wyników
        for config in cardConfigs where !config.isScanning
            && (newIDs.contains(config.id) || config.scannedFiles.isEmpty) {
            scanCard(url: config.volumeURL)
        }

        // Powiadomienie i pop-up okna tylko dla kart włożonych po uruchomieniu aplikacji
        let insertedVolumes = volumes.filter { newIDs.contains($0.id) }
        guard !isInitialLoad, !insertedVolumes.isEmpty else { return }

        let names = insertedVolumes.map { "„\($0.name)”" }.joined(separator: ", ")
        sendNotification(
            title: insertedVolumes.count == 1 ? "Wykryto kartę SD" : "Wykryto karty SD",
            body: insertedVolumes.count == 1
                ? "Karta \(names) jest gotowa do zgrywania."
                : "Karty \(names) są gotowe do zgrywania."
        )

        // Automatycznie otwórz i wysuń okno aplikacji na pierwszy plan (pop-up)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AppModel.showMainWindowNotification, object: nil)
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    /// Wysyła powiadomienie systemowe macOS.
    private func sendNotification(title: String, body: String) {
        guard Self.notificationsAvailable else { return }
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
        let cardID = cardConfigs[index].id
        let extensions = settings.enabledExtensions

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scanner = MediaScanner(enabledExtensions: extensions)
            let results = (try? scanner.scan(volumeRoot: url)) ?? []

            DispatchQueue.main.async {
                self?.updateCard(id: cardID) { card in
                    card.isScanning = false
                    card.setScanResults(results)
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
        guard !isGlobalCopying else {
            setStatus("Nie można wysunąć karty w trakcie zgrywania.", isError: true)
            return
        }
        // Ręcznie dodany folder nie jest nośnikiem — „wysunięcie” usuwa go tylko z listy.
        if cardConfigs.contains(where: { $0.volumeURL == url && $0.isManual }) {
            cardConfigs.removeAll { $0.volumeURL == url }
            return
        }
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
        guard !isGlobalCopying else {
            setStatus("Nie można zmienić nazwy karty w trakcie zgrywania.", isError: true)
            return
        }
        // diskutil zmieniłby nazwę całego wolumenu, na którym leży ręcznie dodany folder.
        guard !cardConfigs.contains(where: { $0.volumeURL == url && $0.isManual }) else { return }
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
        let settings = self.settings

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let builder = ProjectBuilder(settings: settings)
                let layout = try builder.build(projectName: name)

                var totalCopiedOverall = 0
                var totalSkippedOverall = 0
                var totalFailedOverall = 0
                var totalVerifiedOverall = 0
                var totalBytesOverall: Int64 = 0
                var allFailures: [FailedCopy] = []

                for card in cardsToIngest {
                    DispatchQueue.main.async {
                        self.updateCard(id: card.id) {
                            $0.isCopying = true
                            $0.progress = 0
                            $0.currentFile = ""
                            $0.lastReport = nil
                        }
                    }

                    let service = CopyService(
                        verifyChecksums: settings.verifyChecksums,
                        verifyCopies: settings.verifyCopies
                    )
                    service.onProgress = { [weak self] fraction, fileURL in
                        DispatchQueue.main.async {
                            self?.updateCard(id: card.id) {
                                $0.progress = fraction
                                $0.currentFile = fileURL.lastPathComponent
                            }
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
                    totalVerifiedOverall += report.totalVerified
                    totalBytesOverall += report.totalBytesCopied
                    allFailures += report.failed
                    completedFilesAllCards += card.filteredFiles.count

                    let overallFraction = totalFilesAllCards > 0 ? Double(completedFilesAllCards) / Double(totalFilesAllCards) : 1.0

                    DispatchQueue.main.async {
                        self.updateCard(id: card.id) {
                            $0.isCopying = false
                            $0.progress = 1.0
                            $0.lastReport = report
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
                if settings.openInDaVinciResolve {
                    self.launchDaVinciResolve(layout: layout)
                }
                if settings.openInLightroom {
                    self.launchLightroom(layout: layout)
                }

                var summary = "Zgrano \(totalCopiedOverall) plików (\(AppModel.formatBytes(totalBytesOverall))) z \(cardsToIngest.count) kart."
                if settings.verifyCopies && totalCopiedOverall > 0 {
                    summary += " Zweryfikowano: \(totalVerifiedOverall)."
                }
                if totalSkippedOverall > 0 {
                    summary += " Pominięto duplikaty: \(totalSkippedOverall)."
                }
                if let firstFailure = allFailures.first {
                    summary += " Błędy: \(totalFailedOverall) — m.in. \(firstFailure.url.lastPathComponent): \(firstFailure.error)"
                }

                DispatchQueue.main.async {
                    self.isGlobalCopying = false
                    self.overallProgress = 1.0
                    self.history = IngestHistory.load()
                    self.setStatus(summary, isError: totalFailedOverall > 0)
                    if totalFailedOverall > 0 {
                        self.sendNotification(
                            title: "Zgrywanie zakończone z błędami",
                            body: "Projekt „\(name)”: \(totalFailedOverall) plików nie zostało zgranych. Nie formatuj kart przed sprawdzeniem."
                        )
                    } else {
                        self.sendNotification(
                            title: "Zgrywanie zakończone pomyślnie",
                            body: "Projekt „\(name)”: zgrano \(totalCopiedOverall) plików z \(cardsToIngest.count) kart."
                        )
                    }
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
        guard FileManager.default.fileExists(atPath: photoFolder.path) else { return }

        // Wyszukaj zainstalowaną wersję Adobe Lightroom (Classic lub CC)
        let bundleCandidates = [
            "com.adobe.LightroomClassicCC7", // Adobe Lightroom Classic
            "com.adobe.lightroomCC",        // Adobe Lightroom (Cloud)
            "com.adobe.Lightroom6"          // Starsze wersje Lightroom
        ]

        var appURL: URL? = nil
        for bundleId in bundleCandidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                appURL = url
                break
            }
        }

        if let appURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([photoFolder], withApplicationAt: appURL, configuration: config, completionHandler: nil)
        } else {
            // Fallback: sprawdź typowe nazwy aplikacji przez polecenie open
            let appNames = [
                "Adobe Lightroom Classic",
                "Adobe Lightroom",
                "Lightroom Classic",
                "Lightroom"
            ]

            for appName in appNames {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", appName, photoFolder.path]
                if (try? process.run()) != nil {
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        break
                    }
                }
            }
        }
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
