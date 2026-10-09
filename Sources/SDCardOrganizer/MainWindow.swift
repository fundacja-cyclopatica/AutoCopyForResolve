import SwiftUI
import SDCardOrganizerCore

/// Główne okno aplikacji — wybór karty, nazwa projektu, skanowanie i zgrywanie.
struct MainWindow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            cardSection

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
        .padding(20)
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
            if model.volumeMonitor.removableVolumes.isEmpty {
                Text("Nie wykryto karty SD. Włóż kartę do czytnika.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Karta:", selection: $model.selectedVolume) {
                    ForEach(model.volumeMonitor.removableVolumes) { volume in
                        Text(volumeDisplayName(volume)).tag(Volume?.some(volume))
                    }
                }
            }
            Button {
                model.scanSelectedVolume()
            } label: {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Skanuj kartę")
                }
            }
            .disabled(model.selectedVolume == nil || model.isScanning)
        }
    }

    private var projectSection: some View {
        GroupBox("Projekt") {
            TextField("Nazwa projektu", text: $model.projectName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("Dysk docelowy:")
                Text(model.settings.destinationRoot.isEmpty ? "(nie ustawiono)" : model.settings.destinationRoot)
                    .foregroundStyle(model.settings.destinationRoot.isEmpty ? .red : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var actionSection: some View {
        Button {
            model.startCopy()
        } label: {
            Text("Zgraj")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isCopying || model.selectedVolume == nil)
    }

    private var progressSection: some View {
        GroupBox("Zgrywanie") {
            ProgressView(value: model.progress)
            Text(model.currentFile.isEmpty ? "Przygotowywanie…" : model.currentFile)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func reportSection(_ report: CopyReport) -> some View {
        GroupBox("Wynik") {
            HStack {
                Text("Zgrano: \(report.totalCopied)").foregroundStyle(.green)
                Text("Pominięto: \(report.totalSkipped)").foregroundStyle(.orange)
                Text("Błędy: \(report.totalFailed)").foregroundStyle(report.totalFailed > 0 ? .red : .secondary)
            }
        }
    }

    private var statusText: some View {
        Text(model.statusMessage)
            .font(.callout)
            .foregroundStyle(model.statusIsError ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func volumeDisplayName(_ volume: Volume) -> String {
        if let total = volume.totalCapacity {
            let gb = Double(total) / 1_000_000_000
            return "\(volume.name) (\(String(format: "%.1f", gb)) GB)"
        }
        return volume.name
    }

    private func openSettings() {
        // Otwiera okno ustawień (Settings scene).
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
