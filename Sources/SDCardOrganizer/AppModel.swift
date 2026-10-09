import Foundation
import AppKit
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

    public let volumeMonitor = VolumeMonitor()

    private let settingsURL: URL

    public init(settingsURL: URL = Settings.defaultSettingsURL()) {
        self.settingsURL = settingsURL
        self.settings = (try? SettingsStore.load(from: settingsURL)) ?? Settings()
    }

    private func persistSettings() {
        try? SettingsStore.save(settings, to: settingsURL)
    }

    /// Skanuje wybrany nośnik w poszukiwaniu pasujących plików.
    public func scanSelectedVolume() {
        guard let volume = selectedVolume else {
            setStatus("Nie wybrano karty SD.", isError: true)
            return
        }
        isScanning = true
        statusMessage = ""
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let scanner = MediaScanner(enabledExtensions: self.settings.enabledExtensions)
            let results = (try? scanner.scan(volumeRoot: volume.url)) ?? []
            DispatchQueue.main.async {
                self.scanResults = results
                self.isScanning = false
                self.setStatus("Znaleziono \(results.count) plików do zgrywania.", isError: false)
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
                let report = try service.copy(files: files, to: layout)

                DispatchQueue.main.async {
                    self.isCopying = false
                    self.progress = 1
                    self.lastReport = report
                    self.setStatus(
                        "Zgrano \(report.totalCopied) plików, pominięto \(report.totalSkipped) duplikatów, błędy: \(report.totalFailed).",
                        isError: report.totalFailed > 0
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

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
