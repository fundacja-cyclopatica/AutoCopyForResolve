import SwiftUI
import SDCardOrganizerCore

/// Główne okno aplikacji — widok kolumnowy dla kart SD (Apple Design).
struct MainWindow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            ingestTab
                .tabItem { Label("Zgraj materiały", systemImage: "square.and.arrow.down") }
                .tag(0)
            historyTab
                .tabItem { Label("Historia", systemImage: "clock") }
                .tag(1)
        }
        .padding(16)
        .alert("Zmień nazwę karty", isPresented: Binding(
            get: { model.renamingCardURL != nil },
            set: { if !$0 { model.renamingCardURL = nil } }
        )) {
            TextField("Nowa nazwa karty", text: $model.renameInputText)
            Button("Zmień nazwę") {
                if let url = model.renamingCardURL {
                    model.renameCard(url: url, newName: model.renameInputText)
                }
                model.renamingCardURL = nil
            }
            Button("Anuluj", role: .cancel) {
                model.renamingCardURL = nil
            }
        } message: {
            Text("Wprowadź nową nazwę dla podłączonej karty w systemie macOS.")
        }
    }

    // MARK: – Tab: Zgrywanie z wielu kart

    private var ingestTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            // Pasek konfiguracji projektu i dysku docelowego
            projectConfigBar

            Divider()

            // Główna strefa kart (kolumny obok siebie, do 4 kart)
            cardsContentArea

            Spacer(minLength: 4)

            // Pasek postępu globalnego (gdy zgrywanie w toku)
            if model.isGlobalCopying {
                globalProgressSection
            }

            // Komunikat statusu
            if !model.statusMessage.isEmpty {
                statusBanner
            }

            // Dolny pasek akcji z podsumowaniem i przyciskiem Zgraj
            bottomActionBar
        }
    }

    // MARK: – Nagłówek okna

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SD Card Organizer")
                    .font(.title2.bold())
                Text("Zgrywaj materiały z wielu kamer i twórz projekt DaVinci Resolve")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            HStack(spacing: 8) {
                Button {
                    model.scanAllCards()
                } label: {
                    Label("Skanuj karty", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(model.cardConfigs.isEmpty || model.isGlobalCopying)

                Button {
                    openSettings()
                } label: {
                    Label("Ustawienia", systemImage: "gear")
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: – Pasek projektu i dysku

    private var projectConfigBar: some View {
        HStack(spacing: 16) {
            // Nazwa projektu
            HStack(spacing: 8) {
                Label("Projekt:", systemImage: "folder.badge.plus")
                    .font(.subheadline.bold())
                TextField("np. Trek Domane x2, Wywiad A", text: $model.projectName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
            }
            .frame(maxWidth: 360)

            Divider().frame(height: 20)

            // Dysk docelowy
            HStack(spacing: 8) {
                Label("Dysk docelowy:", systemImage: "internaldrive")
                    .font(.subheadline.bold())

                if model.settings.destinationRoot.isEmpty {
                    Text("(nie wybrano dysku)")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Wybierz…") { chooseDestinationQuick() }
                        .controlSize(.small)
                } else {
                    Text(model.settings.destinationRoot)
                        .font(.caption)
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

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
    }

    // MARK: – Strefa kolumn kart

    @ViewBuilder
    private var cardsContentArea: some View {
        if model.cardConfigs.isEmpty {
            emptyStateView
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(model.cardConfigs.indices), id: \.self) { index in
                        CardColumnView(
                            config: $model.cardConfigs[index],
                            cardIndex: index,
                            cameraPresets: model.settings.cameraPresets,
                            onRescan: {
                                model.scanCard(url: model.cardConfigs[index].volumeURL)
                            },
                            onEject: {
                                model.ejectCard(url: model.cardConfigs[index].volumeURL)
                            },
                            onPromptRename: {
                                model.renameInputText = model.cardConfigs[index].volumeName
                                model.renamingCardURL = model.cardConfigs[index].volumeURL
                            },
                            onOpenSettings: {
                                openSettings()
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .frame(minHeight: 280)
        }
    }

    // MARK: – Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "sdcard")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }

            Text("Oczekiwanie na karty SD")
                .font(.title3.bold())

            Text("Włóż kartę SD lub micro SD do czytnika w MacBooku / Mac Studio.\nAplikacja automatycznie wykryje do 4 kart i utworzy osobną kolumnę dla każdej kamery.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            Button {
                model.volumeMonitor.refresh()
            } label: {
                Label("Odśwież wykrywanie kart", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(Color.secondary.opacity(0.2))
        )
    }

    // MARK: – Pasek postępu globalnego

    private var globalProgressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Zgrywanie materiałów w toku…")
                    .font(.caption.bold())
                Spacer()
                Text("\(Int(model.overallProgress * 100))%")
                    .font(.caption.monospacedDigit().bold())
            }
            ProgressView(value: model.overallProgress)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    // MARK: – Komunikat statusu

    private var statusBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: model.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(model.statusIsError ? .red : .green)
            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(model.statusIsError ? Color.red : Color.primary)
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(model.statusIsError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
        )
    }

    // MARK: – Dolny pasek akcji

    private var bottomActionBar: some View {
        VStack(spacing: 8) {
            // Opcje uruchamiania aplikacji po zgraniu
            HStack(spacing: 16) {
                let hasVideos = model.enabledCards.contains { card in card.filteredFiles.contains { $0.category == .video } }
                let hasPhotos = model.enabledCards.contains { card in card.filteredFiles.contains { $0.category == .photo } }

                Toggle(isOn: $model.settings.openInDaVinciResolve) {
                    Label("Otwórz w DaVinci Resolve", systemImage: "film.stack")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $model.settings.openInLightroom) {
                    HStack(spacing: 4) {
                        Label("Otwórz zdjęcia w Lightroom", systemImage: "camera.macro")
                        if !hasVideos && hasPhotos {
                            Text("(tylko zdjęcia)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }
                .toggleStyle(.checkbox)

                Spacer()
            }
            .padding(.horizontal, 2)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    let enabledCount = model.enabledCards.count
                    let totalFiles = model.totalFilesToCopy
                    let totalBytes = model.totalBytesToCopy

                    if enabledCount == 0 {
                        Text("Zaznacz przynajmniej jedną kartę")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Wybrano: \(enabledCount) \(enabledCount == 1 ? "kartę" : "kart(y)") • \(totalFiles) plików (\(AppModel.formatBytes(totalBytes)))")
                            .font(.subheadline.bold())
                    }
                }

                Spacer()

                Button {
                    model.startBatchCopy()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text(model.totalFilesToCopy == 0 ? "Wybierz materiały do zgrania" : "Zgraj (\(model.totalFilesToCopy) plików)")
                    }
                    .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isGlobalCopying || model.enabledCards.isEmpty || model.totalFilesToCopy == 0 || model.projectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 4)
    }

    // MARK: – Tab: Historia

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Historia sesji zgrywań").font(.title2.bold())
                Spacer()
                if !model.history.isEmpty {
                    Button("Wyczyść historię") {
                        IngestHistory.clear()
                        model.history = []
                    }
                    .controlSize(.small)
                }
            }

            if model.history.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Brak zapisanych sesji zgrywania.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
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
                            Label("\(record.filesCopied) skopiowanych", systemImage: "doc.fill")
                            Label(AppModel.formatBytes(record.totalBytes), systemImage: "internaldrive")
                            Text("źródła: \(record.sourceVolumeName)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        Text(record.destinationPath)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: – Pomoc

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
