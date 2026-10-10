import Foundation
import AppKit
import Combine
import UserNotifications
import SDCardOrganizerCore

/// Obserwowalny model stanu aplikacji — zarządza do 4 kartami SD, ustawieniami i zgrywaniem.
public final class AppModel: ObservableObject {
    /// Identyfikator sceny okna ustawień i historii.
    public static let settingsWindowID = "settings"

    /// Zakładki okna ustawień.
    public enum SettingsTab: Hashable {
        case settings
        case history
    }

    @Published public var settings: Settings {
        didSet {
            persistSettings()
            // Nowe typy plików — wyniki skanowania kart są nieaktualne.
            if settings.enabledExtensions != oldValue.enabledExtensions, !isGlobalCopying {
                scanAllCards()
            }
            if settings.destinationRoot != oldValue.destinationRoot {
                refreshDestinationInfo()
            }
        }
    }

    /// Konfiguracje podłączonych kart (maksymalnie 4 karty obok siebie)
    @Published public var cardConfigs: [CardIngestConfig] = []

    /// Globalna nazwa projektu
    @Published public var projectName: String = "" {
        didSet {
            // Wpisanie nazwy ręcznie oznacza nowy projekt z dzisiejszą datą.
            if projectName != oldValue {
                projectDate = nil
            }
        }
    }

    /// Data istniejącego projektu wybranego z listy (dogrywanie do projektu z innego dnia);
    /// `nil` — projekt z dzisiejszą datą.
    @Published public private(set) var projectDate: Date?

    /// Projekty istniejące na dysku docelowym, od najnowszego.
    @Published public private(set) var existingProjects: [ExistingProject] = []

    /// Wolne miejsce na dysku docelowym; `nil`, gdy dysk jest niedostępny lub nie wybrany.
    @Published public private(set) var destinationFreeSpace: Int64?

    /// Czy wybrany folder docelowy istnieje (dysk jest podłączony).
    @Published public private(set) var isDestinationAvailable = false

    /// Stan globalny zgrywania
    @Published public var isGlobalCopying: Bool = false
    @Published public var overallProgress: Double = 0
    /// Bajty, prędkość i czas do końca trwającego zgrywania (`nil`, gdy nic się nie zgrywa).
    @Published public private(set) var transfer: TransferStatus?
    /// Podsumowanie ostatniej sesji — jego ustawienie pokazuje arkusz z wynikami.
    @Published public var lastSession: IngestSessionSummary?
    @Published public var statusMessage: String = ""
    @Published public var statusIsError: Bool = false

    /// Historia i zakładka okna ustawień
    @Published public var history: [IngestRecord] = []
    @Published public var selectedTab: SettingsTab = .settings

    /// Pole dodawania nowego presetu kamery w ustawieniach
    @Published public var newPresetInputText: String = ""

    public let volumeMonitor = VolumeMonitor()

    private let settingsURL: URL
    private var cancellables = Set<AnyCancellable>()
    private var knownVolumeIDs = Set<String>()
    private var hasHandledInitialVolumes = false
    /// Ostatnie zlecone skanowanie każdej karty — wynik starszego skanu jest odrzucany.
    private var scanTokens: [String: UUID] = [:]
    private var activeCancellation: CancellationToken?
    private static let lastTransferSpeedKey = "lastTransferBytesPerSecond"

    /// Otwiera okno ustawień. Ustawiane przez widok okna, bo akcja `openWindow` istnieje tylko
    /// w środowisku SwiftUI, a okno trzeba umieć otworzyć ponownie także po jego zamknięciu.
    public var openSettingsWindowAction: (() -> Void)?

    /// Pokazuje wysuwany panel z paska menu (ustawiane przez `MenuBarController`).
    public var showPanelAction: (() -> Void)?

    /// Czy okno ustawień ma się schować przy starcie aplikacji — SwiftUI otwiera je samo,
    /// a główną formą pracy jest panel z paska menu.
    public var hidesSettingsWindowAtLaunch = true

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
        refreshDestinationInfo()

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

    // MARK: – Projekt i dysk docelowy

    /// Odświeża listę projektów i wolne miejsce na dysku docelowym.
    public func refreshDestinationInfo() {
        let root = settings.destinationRoot
        var isDirectory: ObjCBool = false
        isDestinationAvailable = !root.isEmpty
            && FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory)
            && isDirectory.boolValue
        existingProjects = isDestinationAvailable ? ProjectCatalog.projects(in: root) : []

        if isDestinationAvailable {
            let values = try? URL(fileURLWithPath: root, isDirectory: true).resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey
            ])
            let important = values?.volumeAvailableCapacityForImportantUsage
            let plain = values?.volumeAvailableCapacity.map(Int64.init)
            destinationFreeSpace = (important != nil || plain != nil) ? max(important ?? 0, plain ?? 0) : nil
        } else {
            destinationFreeSpace = nil
        }
    }

    /// Nazwa wolumenu, na którym leży folder docelowy (np. „MONTAŻ SSD”).
    public var destinationVolumeName: String? {
        guard isDestinationAvailable else { return nil }
        return (try? URL(fileURLWithPath: settings.destinationRoot).resourceValues(forKeys: [.volumeNameKey]))?.volumeName
    }

    /// Dogrywanie do projektu, który już istnieje na dysku (także z innego dnia).
    public func selectExistingProject(_ project: ExistingProject) {
        projectName = project.name
        projectDate = project.date
    }

    /// Pełna ścieżka folderu, do którego trafi materiał, albo `nil`, gdy brak danych.
    public var destinationPreviewPath: String? {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !settings.destinationRoot.isEmpty, !name.isEmpty else { return nil }
        return ProjectLayout(
            destinationRoot: settings.destinationRoot,
            projectName: name,
            date: projectDate ?? Date()
        ).root.path
    }

    /// Dlaczego nie można teraz zacząć zgrywania (`nil` — można).
    public var copyBlockedReason: String? {
        if cardConfigs.isEmpty {
            return "Włóż kartę lub dodaj folder ze źródłem."
        }
        if enabledCards.isEmpty {
            return "Włącz co najmniej jedną kartę."
        }
        if enabledCards.contains(where: \.isScanning) {
            return "Trwa skanowanie kart…"
        }
        if totalFilesToCopy == 0 {
            return "Zaznacz dni i typy materiałów do zgrania."
        }
        if settings.destinationRoot.isEmpty {
            return "Wybierz dysk docelowy."
        }
        if !isDestinationAvailable {
            return "Dysk docelowy jest niedostępny — podłącz go."
        }
        if projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Wpisz nazwę projektu."
        }
        return nil
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

    /// Szacowany czas zgrywania na podstawie prędkości zmierzonej przy ostatnim zgraniu.
    /// Bez wcześniejszego pomiaru nie zgadujemy — prędkość kart różni się kilkukrotnie.
    public var estimatedTransferInfo: String {
        guard totalBytesToCopy > 0 else { return "—" }
        let speed = UserDefaults.standard.double(forKey: Self.lastTransferSpeedKey)
        guard speed > 0 else { return "zmierzę przy pierwszym zgraniu" }
        let seconds = Double(totalBytesToCopy) / speed
        return "~\(AppModel.formatDuration(seconds)) (ostatnio \(AppModel.formatBytes(Int64(speed)))/s)"
    }

    /// Czas w czytelnej postaci: „45 s”, „3 min 20 s”, „1 h 05 min”.
    public static func formatDuration(_ seconds: Double) -> String {
        let total = max(1, Int(seconds.rounded()))
        if total < 60 {
            return "\(total) s"
        }
        if total < 3600 {
            return "\(total / 60) min \(total % 60) s"
        }
        return String(format: "%d h %02d min", total / 3600, (total % 3600) / 60)
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
        // Dysk docelowy mógł zostać podłączony lub odłączony.
        refreshDestinationInfo()
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

        // Automatycznie wysuń panel z paska menu
        DispatchQueue.main.async {
            self.showPanelAction?()
        }
    }

    /// Pokazuje okno ustawień na wybranej zakładce — również wtedy, gdy zostało zamknięte.
    public func showSettingsWindow(tab: SettingsTab = .settings) {
        refreshDestinationInfo()
        history = IngestHistory.load()
        selectedTab = tab
        NSApp.activate(ignoringOtherApps: true)
        if let openSettingsWindow = openSettingsWindowAction {
            openSettingsWindow()
        } else {
            // Bez panelu z paska menu (który nie może stać się oknem głównym).
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
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
        let token = UUID()
        scanTokens[cardID] = token

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scanner = MediaScanner(enabledExtensions: extensions)
            let results = (try? scanner.scan(volumeRoot: url)) ?? []

            DispatchQueue.main.async {
                // W międzyczasie zlecono nowsze skanowanie tej karty — ten wynik jest nieaktualny.
                guard let self, self.scanTokens[cardID] == token else { return }
                self.scanTokens[cardID] = nil
                self.updateCard(id: cardID) { card in
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

        let destination = URL(fileURLWithPath: settings.destinationRoot, isDirectory: true)
        let filesToCopy = cardsToIngest.flatMap(\.filteredFiles)
        if let problem = preflightProblem(destination: destination, files: filesToCopy) {
            setStatus(problem, isError: true)
            return
        }
        guard confirmFreeSpace(destination: destination, requiredBytes: filesToCopy.reduce(0) { $0 + $1.size }) else {
            return
        }

        let totalBytesAllCards = filesToCopy.reduce(Int64(0)) { $0 + $1.size }
        let cancellation = CancellationToken()
        let settings = self.settings
        let projectDate = self.projectDate ?? Date()

        isGlobalCopying = true
        overallProgress = 0
        transfer = TransferStatus(processedBytes: 0, totalBytes: totalBytesAllCards)
        activeCancellation = cancellation
        lastSession = nil
        statusMessage = ""
        statusIsError = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            do {
                let builder = ProjectBuilder(settings: settings)
                let layout = try builder.build(projectName: name, date: projectDate)

                var results: [IngestSessionSummary.CardResult] = []
                var processedBefore: Int64 = 0
                var transferredBefore: Int64 = 0
                var meter = TransferRateMeter()
                var lastUIUpdate: TimeInterval = 0

                for card in cardsToIngest {
                    if cancellation.isCancelled { break }

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
                        verifyCopies: settings.verifyCopies,
                        cancellation: cancellation
                    )
                    service.onProgress = { [weak self] progress in
                        let now = ProcessInfo.processInfo.systemUptime
                        meter.add(totalBytes: transferredBefore + progress.transferredBytes, at: now)
                        // Odświeżanie interfejsu najwyżej 5 razy na sekundę.
                        guard now - lastUIUpdate >= 0.2 || progress.filesDone == progress.totalFiles else { return }
                        lastUIUpdate = now

                        let processed = processedBefore + progress.processedBytes
                        let status = TransferStatus(
                            processedBytes: processed,
                            totalBytes: totalBytesAllCards,
                            bytesPerSecond: meter.bytesPerSecond,
                            secondsRemaining: meter.secondsRemaining(forRemainingBytes: totalBytesAllCards - processed)
                        )
                        let cardFraction = progress.fraction
                        let fileName = progress.currentFile.lastPathComponent
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.updateCard(id: card.id) {
                                $0.progress = cardFraction
                                $0.currentFile = fileName
                            }
                            self.overallProgress = status.fraction
                            var updated = status
                            updated.isCancelling = self.transfer?.isCancelling ?? false
                            self.transfer = updated
                        }
                    }

                    let report = try service.copy(
                        files: card.filteredFiles,
                        to: layout,
                        cameraLabel: card.cameraLabel
                    )

                    processedBefore += card.totalSelectedBytes
                    transferredBefore += report.totalBytesCopied
                    results.append(IngestSessionSummary.CardResult(
                        id: card.id,
                        title: card.cameraLabel.isEmpty ? card.volumeName : "\(card.cameraLabel) (\(card.volumeName))",
                        isManual: card.isManual,
                        report: report
                    ))

                    DispatchQueue.main.async {
                        self.updateCard(id: card.id) {
                            $0.isCopying = false
                            $0.progress = report.wasCancelled ? $0.progress : 1.0
                            $0.lastReport = report
                        }
                    }

                    if report.wasCancelled { break }
                }

                let session = IngestSessionSummary(
                    projectName: name,
                    destination: layout.root,
                    cards: results,
                    duration: Date().timeIntervalSince(startedAt),
                    wasCancelled: cancellation.isCancelled,
                    verificationEnabled: settings.verifyCopies
                )
                self.finishBatch(session, settings: settings, layout: layout)
            } catch {
                DispatchQueue.main.async {
                    self.isGlobalCopying = false
                    self.transfer = nil
                    self.activeCancellation = nil
                    self.setStatus("Błąd zgrywania: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    /// Kończy sesję: historia, aplikacje docelowe, komunikat, powiadomienie i arkusz podsumowania.
    /// Wywoływane z wątku zgrywania.
    private func finishBatch(_ session: IngestSessionSummary, settings: Settings, layout: ProjectLayout) {
        let failedCount = session.failures.count
        let record = IngestRecord(
            projectName: session.projectName,
            sourceVolumeName: session.cards.map(\.title).joined(separator: ", "),
            destinationPath: layout.root.path,
            filesCopied: session.totalCopied,
            filesSkipped: session.totalSkipped,
            filesFailed: failedCount,
            totalBytes: session.totalBytes
        )
        IngestHistory.append(record)

        // Zapamiętaj zmierzoną prędkość do szacowania czasu następnych zgrań.
        if let speed = session.averageBytesPerSecond, session.duration >= 3 {
            UserDefaults.standard.set(speed, forKey: Self.lastTransferSpeedKey)
        }

        // Uruchom aplikacje docelowe (Resolve / Lightroom) — nie po anulowaniu
        if !session.wasCancelled {
            if settings.openInDaVinciResolve {
                launchDaVinciResolve(layout: layout)
            }
            if settings.openInLightroom {
                launchLightroom(layout: layout)
            }
        }

        var message = "Zgrano \(PolishPlural.files(session.totalCopied)) (\(AppModel.formatBytes(session.totalBytes))) "
            + "z \(PolishPlural.format(session.cards.count, one: "karty", few: "kart", many: "kart"))."
        if session.wasCancelled {
            message = "Zgrywanie anulowane. " + message
        }
        if session.verificationEnabled && session.totalCopied > 0 {
            message += " Zweryfikowano: \(session.totalVerified)."
        }
        if session.totalSkipped > 0 {
            message += " Pominięto duplikaty: \(session.totalSkipped)."
        }
        if let firstFailure = session.failures.first {
            message += " Błędy: \(failedCount) — m.in. \(firstFailure.url.lastPathComponent): \(firstFailure.error)"
        }

        DispatchQueue.main.async {
            self.isGlobalCopying = false
            self.overallProgress = session.wasCancelled ? self.overallProgress : 1.0
            self.transfer = nil
            self.activeCancellation = nil
            self.history = IngestHistory.load()
            self.setStatus(message, isError: failedCount > 0 || session.wasCancelled)
            self.lastSession = session
            self.refreshDestinationInfo()

            if session.wasCancelled {
                self.sendNotification(
                    title: "Zgrywanie anulowane",
                    body: "Projekt „\(session.projectName)”: zgrano \(PolishPlural.files(session.totalCopied)) przed przerwaniem."
                )
            } else if failedCount > 0 {
                self.sendNotification(
                    title: "Zgrywanie zakończone z błędami",
                    body: "Projekt „\(session.projectName)”: nie zgrano \(PolishPlural.files(failedCount)). Nie formatuj kart przed sprawdzeniem."
                )
            } else {
                self.sendNotification(
                    title: "Zgrywanie zakończone pomyślnie",
                    body: "Projekt „\(session.projectName)”: zgrano \(PolishPlural.files(session.totalCopied)) "
                        + "z \(PolishPlural.format(session.cards.count, one: "karty", few: "kart", many: "kart"))."
                )
            }
        }
    }

    /// Przerywa trwające zgrywanie. Bieżący plik jest porzucany (bez śladu w projekcie),
    /// pliki już skopiowane zostają.
    public func cancelCopy() {
        guard isGlobalCopying, let cancellation = activeCancellation else { return }
        cancellation.cancel()
        transfer?.isCancelling = true
        setStatus("Anulowanie… przerywam bieżący plik.", isError: false)
    }

    /// Wysuwa karty z zakończonej sesji (ręcznie dodane foldery są pomijane).
    public func ejectCards(of session: IngestSessionSummary) {
        for card in session.cards where !card.isManual {
            guard let config = cardConfigs.first(where: { $0.id == card.id }) else { continue }
            ejectCard(url: config.volumeURL)
        }
    }

    /// Pokazuje folder projektu w Finderze.
    public func revealInFinder(_ session: IngestSessionSummary) {
        NSWorkspace.shared.activateFileViewerSelecting([session.destination])
    }

    // MARK: – Sprawdzenie dysku docelowego przed zgrywaniem

    /// Zwraca opis problemu, przez który zgrywanie nie może się udać, albo `nil`.
    private func preflightProblem(destination: URL, files: [MediaFile]) -> String? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "Dysk docelowy „\(destination.path)” jest niedostępny. Sprawdź, czy jest podłączony."
        }
        guard fm.isWritableFile(atPath: destination.path) else {
            return "Brak uprawnień do zapisu na dysku docelowym „\(destination.path)”."
        }
        // FAT32 przyjmuje pliki do 4 GB — dłuższy klip i tak by się nie skopiował.
        if let maxFileSize = (try? destination.resourceValues(forKeys: [.volumeMaximumFileSizeKey]))?.volumeMaximumFileSize,
           let tooLarge = files.first(where: { $0.size > Int64(maxFileSize) }) {
            return "Dysk docelowy nie przyjmie pliku \(tooLarge.url.lastPathComponent) (\(AppModel.formatBytes(tooLarge.size))) — "
                + "limit systemu plików to \(AppModel.formatBytes(Int64(maxFileSize))). Użyj dysku sformatowanego jako APFS lub exFAT."
        }
        return nil
    }

    /// Gdy wybrane materiały mogą się nie zmieścić, pyta użytkownika, czy mimo to zgrywać.
    /// Nie blokuje twardo, bo pliki zgrane już wcześniej do projektu zostaną pominięte.
    private func confirmFreeSpace(destination: URL, requiredBytes: Int64) -> Bool {
        let values = try? destination.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey
        ])
        guard values?.volumeAvailableCapacityForImportantUsage != nil || values?.volumeAvailableCapacity != nil else {
            return true
        }
        let available = max(
            values?.volumeAvailableCapacityForImportantUsage ?? 0,
            Int64(values?.volumeAvailableCapacity ?? 0)
        )
        guard available < requiredBytes else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Na dysku docelowym może zabraknąć miejsca"
        alert.informativeText = "Wybrane materiały zajmują \(AppModel.formatBytes(requiredBytes)), "
            + "a wolne jest \(AppModel.formatBytes(available)). Pliki zgrane już wcześniej do tego projektu "
            + "zostaną pominięte, więc faktycznie może być potrzebne mniej miejsca."
        alert.addButton(withTitle: "Anuluj")
        alert.addButton(withTitle: "Zgraj mimo to")
        return alert.runModal() == .alertSecondButtonReturn
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
