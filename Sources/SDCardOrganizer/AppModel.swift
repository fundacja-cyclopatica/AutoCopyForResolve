import Foundation
import AppKit
import Combine
import UserNotifications
import SDCardOrganizerCore

/// Obserwowalny model stanu aplikacji — łączy monitor wolumenów, ustawienia i zgrywanie.
public final class AppModel: ObservableObject {
    @Published public var settings: Settings {
        didSet { persistSettings() }
    }
    @Published public var selectedVolume: Volume?
    @Published public var projectName: String = ""
    @Published public var scanResults: [MediaFile] = []
    @Published public var isScanning: Bool = false
    @Published public var isCopying: Bool = false
    @Published public var progress: Double = 0
    @Published public var currentFile: String = ""
    @Published public var lastReport: CopyReport?
    @Published public var statusMessage: String = ""
    @Published public var statusIsError: Bool = false
    @Published public var history: [IngestRecord] = []
    @Published public var selectedTab: Int = 0

    public let volumeMonitor = VolumeMonitor()

    private let settingsURL: URL

    public init(settingsURL: URL = Settings.defaultSettingsURL()) {
        self.settingsURL = settingsURL
        self.settings = (try? SettingsStore.load(from: settingsURL)) ?? Settings()
        self.history = IngestHistory.load()

        // Poproś o uprawnienia do powiadomień
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Reaguj na nowe karty — powiadomienie systemowe + auto-skan.
        volumeMonitor.$removableVolumes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volumes in
                self?.handleVolumesChanged(volumes)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
    private var knownVolumeIDs = Set<String>()

    private func persistSettings() {
        try? SettingsStore.save(settings, to: settingsURL)
    }

    /// Reaguje na zamontowanie nowego nośnika.
    private func handleVolumesChanged(_ volumes: [Volume]) {
        let currentIDs = Set(volumes.map(\.id))
        let newIDs = currentIDs.subtracting(knownVolumeIDs)
        knownVolumeIDs = currentIDs

        guard let newID = newIDs.first,
              let newVolume = volumes.first(where: { $0.id == newID }) else { return }

        // Automatycznie wybierz nową kartę.
        selectedVolume = newVolume

        // Powiadomienie systemowe.
        sendNotification(
            title: "Wykryto kartę SD",
            body: "Karta \"\(newVolume.name)\" jest gotowa do zgrywania."
        )

        // Automatyczny skan.
        scanSelectedVolume()
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

    /// Skanuje wybrany nośnik w poszukiwaniu pasujących plików.
    public func scanSelectedVolume() {
        guard let volume = selectedVolume else {
            setStatus("Nie wybrano karty SD.", isError: true)
            return
        }
        isScanning = true
        scanResults = []
        statusMessage = ""
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let scanner = MediaScanner(enabledExtensions: self.settings.enabledExtensions)
            let results = (try? scanner.scan(volumeRoot: volume.url)) ?? []
            DispatchQueue.main.async {
                self.scanResults = results
                self.isScanning = false
                let videoCount = results.filter { $0.category == .video }.count
                let audioCount = results.filter { $0.category == .audio }.count
                let photoCount = results.filter { $0.category == .photo }.count
                self.setStatus(
                    "Znaleziono \(results.count) plików: \(videoCount) wideo, \(audioCount) audio, \(photoCount) zdjęć.",
                    isError: false
                )
            }
        }
    }

    /// Uruchamia zgrywanie: tworzy projekt i kopiuje pliki.
    public func startCopy() {
        guard let volume = selectedVolume else {
            setStatus("Nie wybrano karty SD.", isError: true)
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

        isCopying = true
        progress = 0
        currentFile = ""
        lastReport = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let builder = ProjectBuilder(settings: self.settings)
                let layout = try builder.build(projectName: name)

                let files: [MediaFile]
                if self.scanResults.isEmpty {
                    let scanner = MediaScanner(enabledExtensions: self.settings.enabledExtensions)
                    files = try scanner.scan(volumeRoot: volume.url)
                } else {
                    files = self.scanResults
                }

                let service = CopyService(verifyChecksums: self.settings.verifyChecksums)
                service.onProgress = { [weak self] fraction, url in
                    DispatchQueue.main.async {
                        self?.progress = fraction
                        self?.currentFile = url.lastPathComponent
                    }
                }
                let report = try service.copy(files: files, to: layout)

                // Zapisz do historii.
                let record = IngestRecord(
                    projectName: name,
                    sourceVolumeName: volume.name,
                    destinationPath: layout.root.path,
                    filesCopied: report.totalCopied,
                    filesSkipped: report.totalSkipped,
                    filesFailed: report.totalFailed,
                    totalBytes: report.totalBytesCopied
                )
                IngestHistory.append(record)

                DispatchQueue.main.async {
                    self.isCopying = false
                    self.progress = 1
                    self.lastReport = report
                    self.history = IngestHistory.load()
                    self.setStatus(
                        "Zgrano \(report.totalCopied) plików, pominięto \(report.totalSkipped) duplikatów, błędy: \(report.totalFailed).",
                        isError: report.totalFailed > 0
                    )
                    self.sendNotification(
                        title: "Zgrywanie zakończone",
                        body: "Projekt \"\(name)\": \(report.totalCopied) plików skopiowanych."
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.isCopying = false
                    self.setStatus("Błąd zgrywania: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    /// Formatuje rozmiar w bajtach na czytelny tekst.
    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
