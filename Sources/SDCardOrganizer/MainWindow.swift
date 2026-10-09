import SwiftUI
import SDCardOrganizerCore

/// Główne okno aplikacji — wybór karty, nazwa projektu, skanowanie i zgrywanie.
struct MainWindow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            ingestTab
                .tabItem { Label("Zgraj", systemImage: "square.and.arrow.down") }
                .tag(0)
            historyTab
                .tabItem { Label("Historia", systemImage: "clock") }
                .tag(1)
        }
        .padding(16)
    }

    // MARK: – Tab: Zgrywanie

    private var ingestTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            cardSection

            if !model.scanResults.isEmpty {
                scanResultsSection
            }

            projectSection

            actionSection

            if model.isCopying {
                progressSection
            }

            if let report = model.lastReport {
                reportSection(report)
            }

            statusText

            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("SD Card Organizer").font(.title.bold())
                Text("Zgraj materiały z karty SD i przygotuj projekt DaVinci Resolve")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Ustawienia…") {
                openSettings()
            }
        }
    }

    private var cardSection: some View {
        GroupBox("Karta SD") {
            VStack(alignment: .leading, spacing: 8) {
                if model.volumeMonitor.removableVolumes.isEmpty {
                    HStack {
                        Image(systemName: "sdcard")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Nie wykryto karty SD. Włóż kartę do czytnika.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else {
                    Picker("Karta:", selection: $model.selectedVolume) {
                        ForEach(model.volumeMonitor.removableVolumes) { volume in
                            Text(volumeDisplayName(volume)).tag(Volume?.some(volume))
                        }
                    }
                    if let vol = model.selectedVolume, let avail = vol.availableCapacity, let total = vol.totalCapacity {
                        HStack(spacing: 12) {
                            ProgressView(value: Double(total - avail), total: Double(total))
                                .frame(width: 100)
                            Text("\(AppModel.formatBytes(Int64(avail))) wolne z \(AppModel.formatBytes(Int64(total)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button {
                        model.scanSelectedVolume()
                    } label: {
                        if model.isScanning {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text("Skanowanie…")
                            }
                        } else {
                            Label("Skanuj kartę", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(model.selectedVolume == nil || model.isScanning)

                    Button {
                        model.volumeMonitor.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Odśwież listę kart")
                }
            }
        }
    }

    private var scanResultsSection: some View {
        GroupBox("Zawartość karty") {
            VStack(alignment: .leading, spacing: 4) {
                let videos = model.scanResults.filter { $0.category == .video }
                let audios = model.scanResults.filter { $0.category == .audio }
                let photos = model.scanResults.filter { $0.category == .photo }

                HStack(spacing: 16) {
                    Label("\(videos.count) wideo", systemImage: "film")
                    Label("\(audios.count) audio", systemImage: "waveform")
                    Label("\(photos.count) zdjęć", systemImage: "photo")
                }
                .font(.callout)

                if model.scanResults.count <= 20 {
                    ForEach(model.scanResults) { file in
                        HStack {
                            Image(systemName: iconName(for: file.category))
                                .foregroundStyle(iconColor(for: file.category))
                                .frame(width: 16)
                            Text(file.url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("(\(model.scanResults.count) plików łącznie)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var projectSection: some View {
        GroupBox("Projekt") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Nazwa projektu", text: $model.projectName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Dysk docelowy:")
                    if model.settings.destinationRoot.isEmpty {
                        Text("(nie ustawiono)")
                            .foregroundStyle(.red)
                        Button("Wybierz…") { chooseDestinationQuick() }
                            .controlSize(.small)
                    } else {
                        Text(model.settings.destinationRoot)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            chooseDestinationQuick()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .controlSize(.small)
                        .help("Zmień dysk docelowy")
                    }
                }
            }
        }
    }

    private var actionSection: some View {
        Button {
            model.startCopy()
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.down.fill")
                Text("Zgraj")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isCopying || model.selectedVolume == nil || model.projectName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var progressSection: some View {
        GroupBox("Zgrywanie") {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: model.progress)
                HStack {
                    Text(model.currentFile.isEmpty ? "Przygotowywanie…" : model.currentFile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(Int(model.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reportSection(_ report: CopyReport) -> some View {
        GroupBox("Wynik") {
            HStack(spacing: 16) {
                Label("\(report.totalCopied) skopiowanych", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("\(report.totalSkipped) pominiętych", systemImage: "arrow.uturn.right.circle")
                    .foregroundStyle(.orange)
                if report.totalFailed > 0 {
                    Label("\(report.totalFailed) błędów", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                Spacer()
                Text(AppModel.formatBytes(report.totalBytesCopied))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: some View {
        Group {
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.callout)
                    .foregroundStyle(model.statusIsError ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: – Tab: Historia

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Historia zgrywań").font(.title2.bold())

            if model.history.isEmpty {
                Spacer()
                Text("Brak wpisów w historii.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(model.history) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.projectName).font(.headline)
                            Spacer()
                            Text(record.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            Label("\(record.filesCopied)", systemImage: "doc.fill")
                            Label(AppModel.formatBytes(record.totalBytes), systemImage: "internaldrive")
                            Text("z: \(record.sourceVolumeName)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        Text(record.destinationPath)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: – Pomoc

    private func volumeDisplayName(_ volume: Volume) -> String {
        if let total = volume.totalCapacity {
            return "\(volume.name) (\(AppModel.formatBytes(Int64(total))))"
        }
        return volume.name
    }

    private func iconName(for category: MediaCategory) -> String {
        switch category {
        case .video: return "film"
        case .audio: return "waveform"
        case .photo: return "photo"
        }
    }

    private func iconColor(for category: MediaCategory) -> Color {
        switch category {
        case .video: return .blue
        case .audio: return .green
        case .photo: return .orange
        }
    }

    private func chooseDestinationQuick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Wybierz dysk/folder docelowy"
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.destinationRoot = url.path
        }
    }

    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
