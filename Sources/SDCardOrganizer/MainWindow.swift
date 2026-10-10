import SwiftUI
import SDCardOrganizerCore

/// Główne okno aplikacji — macOS Studio Dark Glass UI.
struct MainWindow: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Główna zawartość okna w stylu Studio
            VStack(spacing: 0) {
                // Górny pasek tytułowy z przełącznikiem zakładek i akcjami
                studioTitleBar

                // Pasek konfiguracji projektu i dysku docelowego
                if model.selectedTab == 0 {
                    topConfigurationBar
                }

                // Zawartość wybranej zakładki
                if model.selectedTab == 0 {
                    mainIngestWorkspace
                } else {
                    historyWorkspace
                }

                // Dolny pasek akcji (Global Action Bar)
                if model.selectedTab == 0 {
                    globalActionBar
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 24/255, green: 28/255, blue: 38/255),
                        Color(red: 10/255, green: 12/255, blue: 16/255)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Pływające okno ustawień (Floating Studio Settings Panel)
            if model.isSettingsPanelOpen {
                StudioSettingsModalView(
                    model: model,
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            model.isSettingsPanelOpen = false
                        }
                    }
                )
                .padding(.top, 46)
                .padding(.trailing, 16)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity)
                ))
                .zIndex(100)
            }
        }
        .frame(minWidth: 1060, minHeight: 680)
        .onAppear {
            // Pozwala paskowi menu otworzyć okno ponownie po jego zamknięciu.
            model.openMainWindowAction = { [openWindow] in
                openWindow(id: AppModel.mainWindowID)
            }
        }
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
        .sheet(item: $model.lastSession) { session in
            IngestSummaryView(
                session: session,
                onRevealInFinder: { model.revealInFinder(session) },
                onEjectCards: {
                    model.ejectCards(of: session)
                    model.lastSession = nil
                },
                onClose: { model.lastSession = nil }
            )
        }
    }

    // MARK: – Pasek tytułowy (Studio Titlebar)

    private var studioTitleBar: some View {
        HStack(spacing: 0) {
            // Lewa strona (miejsce na przyciski okna)
            HStack(spacing: 6) {
                // Zachowaj naturalny odstęp od lewej krawędzi
                Spacer().frame(width: 8)
            }
            .frame(width: 140, alignment: .leading)

            Spacer()

            // Środek: Segmented Pro Controller Tabs
            HStack(spacing: 2) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        model.selectedTab = 0
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(StudioTheme.accentCyan)
                            .frame(width: 6, height: 6)
                            .shadow(color: StudioTheme.accentCyan, radius: 3)
                        Text("Zgraj materiały")
                            .font(.system(size: 11, weight: model.selectedTab == 0 ? .semibold : .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(model.selectedTab == 0 ? Color.white.opacity(0.12) : Color.clear)
                    .foregroundStyle(model.selectedTab == 0 ? Color.white : Color.gray)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        model.selectedTab = 1
                    }
                } label: {
                    Text("Historia")
                        .font(.system(size: 11, weight: model.selectedTab == 1 ? .semibold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(model.selectedTab == 1 ? Color.white.opacity(0.12) : Color.clear)
                        .foregroundStyle(model.selectedTab == 1 ? Color.white : Color.gray)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(2)
            .background(Color.black.opacity(0.55))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 1))

            Spacer()

            // Prawa strona: Akcje Skanuj karty i Ustawienia
            HStack(spacing: 8) {
                Button {
                    model.scanAllCards()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(StudioTheme.accentCyan)
                        Text("Skanuj karty")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.gray.opacity(0.9))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(model.isGlobalCopying)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.isSettingsPanelOpen.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                            .foregroundStyle(model.isSettingsPanelOpen ? StudioTheme.accentCyan : Color.gray)
                        Text("Ustawienia")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(model.isSettingsPanelOpen ? Color.white : Color.gray.opacity(0.9))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(model.isSettingsPanelOpen ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.isSettingsPanelOpen ? StudioTheme.accentCyan.opacity(0.5) : Color.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 220, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(height: 38)
        .background(Color.black.opacity(0.40))
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.white.opacity(0.08))
        }
    }

    // MARK: – Górny pasek konfiguracji (TopBarConfig)

    private var topConfigurationBar: some View {
        HStack(alignment: .center, spacing: 14) {
            // Tytuł, LED dot i badge STUDIO 2.4
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(StudioTheme.accentCyan)
                        .frame(width: 8, height: 8)
                        .shadow(color: StudioTheme.accentCyan, radius: 5)

                    Text("SD Card Organizer")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text("STUDIO 2.4")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(StudioTheme.accentCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(StudioTheme.accentCyan.opacity(0.10))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(StudioTheme.accentCyan.opacity(0.35), lineWidth: 1))
                }

                Text("Zgrywaj materiały z wielu kamer i twórz zintegrowany projekt DaVinci Resolve")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gray.opacity(0.85))
            }

            Spacer(minLength: 16)

            // Projekt i Dysk docelowy
            HStack(spacing: 8) {
                // Nazwa projektu
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StudioTheme.accentCyan)

                    Text("Projekt:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.gray)

                    TextField("np. Foty", text: $model.projectName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 100)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.60))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.10), lineWidth: 1))

                // Dysk docelowy
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StudioTheme.accentGreen)

                    Text("Dysk docelowy:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.gray)

                    Text(model.settings.destinationRoot.isEmpty ? "Wybierz dysk…" : model.settings.destinationRoot)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(model.settings.destinationRoot.isEmpty ? Color.red.opacity(0.9) : Color.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 240, alignment: .leading)

                    Button {
                        chooseDestinationQuick()
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Zmień dysk docelowy")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.60))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.25))
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.white.opacity(0.08))
        }
    }

    // MARK: – Główna strefa kart (MainCardsGrid - do 4 kolumn)

    private var mainIngestWorkspace: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 14) {
                // Wyświetl podłączone karty (do 4)
                // Karty identyfikowane po id (nie po indeksie) — wysunięcie karty nie
                // unieważnia bindingów pozostałych kolumn.
                ForEach(Array(model.cardConfigs.enumerated()), id: \.element.id) { index, config in
                    CardColumnView(
                        config: cardBinding(for: config),
                        cardIndex: index,
                        cameraPresets: model.settings.cameraPresets,
                        isLocked: model.isGlobalCopying,
                        onRescan: {
                            model.scanCard(url: config.volumeURL)
                        },
                        onEject: {
                            model.ejectCard(url: config.volumeURL)
                        },
                        onPromptRename: {
                            model.renameInputText = config.volumeName
                            model.renamingCardURL = config.volumeURL
                        },
                        onOpenSettings: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                model.isSettingsPanelOpen = true
                            }
                        }
                    )
                }

                // Jeśli podłączono mniej niż 4 karty, wyświetl slot wolny
                if model.cardConfigs.count < AppModel.maxCards {
                    EmptyCardSlotView(onChooseFolder: {
                        model.addManualFolder()
                    })
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Dolny pasek akcji (GlobalActionBar)

    private var globalActionBar: some View {
        VStack(spacing: 8) {
            // Status Feedback Banner (Audio/Video Engine Status Look)
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.statusIsError ? StudioTheme.accentRed : StudioTheme.accentGreen)
                        .frame(width: 7, height: 7)
                        .shadow(color: model.statusIsError ? StudioTheme.accentRed : StudioTheme.accentGreen, radius: 4)

                    Text(model.statusMessage.isEmpty ? (model.isGlobalCopying ? "Zgrywanie materiałów w toku…" : "Gotowy do zrzutu materiałów z podłączonych kamer") : model.statusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.statusIsError ? StudioTheme.accentRed : StudioTheme.accentGreen.opacity(0.95))
                }

                Spacer()

                Text(model.isGlobalCopying ? "KOPIOWANIE: \(Int(model.overallProgress * 100))%" : "KONTROLER I/O: GOTOWY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.statusIsError ? StudioTheme.accentRed : StudioTheme.accentGreen.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((model.statusIsError ? StudioTheme.accentRed : StudioTheme.accentGreen).opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke((model.statusIsError ? StudioTheme.accentRed : StudioTheme.accentGreen).opacity(0.25), lineWidth: 1)
            )

            // Pasek operacyjny
            HStack(alignment: .center, spacing: 14) {
                // Post-Action Toggle Buttons (DaVinci Resolve / Lightroom)
                HStack(spacing: 8) {
                    // DaVinci Resolve Button
                    LaunchToggleButton(
                        label: "Otwórz w DaVinci Resolve",
                        iconText: "Dv",
                        iconGradient: LinearGradient(
                            colors: [Color(red: 234/255, green: 56/255, blue: 77/255), Color(red: 142/255, green: 14/255, blue: 0/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        iconTextColor: Color.white,
                        isOn: $model.settings.openInDaVinciResolve,
                        themeColor: StudioTheme.accentCyan
                    )

                    // Lightroom Button
                    LaunchToggleButton(
                        label: "Otwórz zdjęcia w Lightroom",
                        iconText: "Lr",
                        iconGradient: LinearGradient(
                            colors: [Color(red: 0/255, green: 29/255, blue: 52/255), Color(red: 0/255, green: 29/255, blue: 52/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        iconTextColor: Color(red: 49/255, green: 168/255, blue: 255/255),
                        isOn: $model.settings.openInLightroom,
                        themeColor: StudioTheme.accentBlue
                    )
                }

                Spacer()

                if let transfer = model.transfer {
                    // W trakcie zgrywania: postęp w bajtach, prędkość, czas do końca i anulowanie
                    transferProgressView(transfer)
                    cancelButton(transfer)
                } else {
                    // Statystyki transferu
                    VStack(alignment: .trailing, spacing: 1) {
                        let enabledCount = model.enabledCards.count
                        let totalFiles = model.totalFilesToCopy
                        let totalBytes = model.totalBytesToCopy

                        HStack(spacing: 4) {
                            Text("Wybrano:")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.gray)
                            Text("\(enabledCount) kart(y)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white)
                            Text("•")
                                .foregroundStyle(Color.white.opacity(0.2))
                            Text("\(totalFiles) plików")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white)
                        }

                        HStack(spacing: 5) {
                            Text("Łączny rozmiar: \(AppModel.formatBytes(totalBytes))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.gray.opacity(0.9))
                            Text("•")
                                .foregroundStyle(Color.white.opacity(0.2))
                            Text("Czas: \(model.estimatedTransferInfo)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(StudioTheme.accentCyan)
                        }
                    }

                    // Główny przycisk akcji (Vibrant Studio Action Button)
                    Button {
                        model.startBatchCopy()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(model.totalFilesToCopy == 0 ? "Wybierz materiały" : "Zgraj (\(model.totalFilesToCopy) plików)")
                                .font(.system(size: 13, weight: .bold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0/255, green: 210/255, blue: 255/255),
                                    Color(red: 10/255, green: 132/255, blue: 255/255),
                                    Color(red: 0/255, green: 102/255, blue: 255/255)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(Color(red: 5/255, green: 19/255, blue: 41/255))
                        .cornerRadius(9)
                        .shadow(color: StudioTheme.accentCyan.opacity(0.45), radius: 10, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isGlobalCopying || model.enabledCards.isEmpty || model.totalFilesToCopy == 0 || model.projectName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity((model.isGlobalCopying || model.enabledCards.isEmpty || model.totalFilesToCopy == 0 || model.projectName.trimmingCharacters(in: .whitespaces).isEmpty) ? 0.45 : 1.0)
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.50))
        .overlay(alignment: .top) {
            Divider().overlay(Color.white.opacity(0.08))
        }
    }

    // MARK: – Postęp zgrywania

    private func transferProgressView(_ transfer: TransferStatus) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            ProgressView(value: transfer.fraction)
                .tint(StudioTheme.accentCyan)
                .frame(width: 300)

            HStack(spacing: 5) {
                Text("\(AppModel.formatBytes(transfer.processedBytes)) z \(AppModel.formatBytes(transfer.totalBytes))")
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("•")
                    .foregroundStyle(Color.white.opacity(0.2))
                Text(transfer.bytesPerSecond.map { "\(AppModel.formatBytes(Int64($0)))/s" } ?? "mierzę prędkość…")
                    .foregroundStyle(StudioTheme.accentCyan)
                Text("•")
                    .foregroundStyle(Color.white.opacity(0.2))
                Text(transfer.secondsRemaining.map { "zostało ~\(AppModel.formatDuration($0))" } ?? "szacuję czas…")
                    .foregroundStyle(Color.gray)
            }
            .font(.system(size: 11, design: .monospaced))
        }
    }

    private func cancelButton(_ transfer: TransferStatus) -> some View {
        Button {
            model.cancelCopy()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: transfer.isCancelling ? "hourglass" : "xmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(transfer.isCancelling ? "Anulowanie…" : "Anuluj")
                    .font(.system(size: 13, weight: .bold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(StudioTheme.accentRed.opacity(transfer.isCancelling ? 0.10 : 0.18))
            .foregroundStyle(StudioTheme.accentRed)
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(StudioTheme.accentRed.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(transfer.isCancelling)
        .keyboardShortcut(.cancelAction)
        .help("Przerwij zgrywanie (Esc). Pliki już skopiowane zostaną w projekcie.")
    }

    // MARK: – Zakładka Historia

    private var historyWorkspace: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Historia sesji zgrywań")
                    .font(.title2.bold())
                    .foregroundStyle(Color.white)
                Spacer()
                if !model.history.isEmpty {
                    Button("Wyczyść historię") {
                        IngestHistory.clear()
                        model.history = []
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if model.history.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.gray.opacity(0.5))
                    Text("Brak zapisanych sesji zgrywania.")
                        .font(.headline)
                        .foregroundStyle(Color.gray)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.history) { record in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(record.projectName)
                                        .font(.headline)
                                        .foregroundStyle(Color.white)
                                    Spacer()
                                    Text(formatHistoryDate(record.date))
                                        .font(.caption)
                                        .foregroundStyle(Color.gray)
                                }
                                HStack(spacing: 14) {
                                    Label("\(record.filesCopied) skopiowanych", systemImage: "doc.fill")
                                        .foregroundStyle(StudioTheme.accentCyan)
                                    Label(AppModel.formatBytes(record.totalBytes), systemImage: "internaldrive")
                                        .foregroundStyle(StudioTheme.accentGreen)
                                    Text("źródła: \(record.sourceVolumeName)")
                                        .foregroundStyle(Color.gray)
                                }
                                .font(.caption)

                                Text(record.destinationPath)
                                    .font(.caption2)
                                    .foregroundStyle(Color.gray.opacity(0.6))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(12)
                            .background(StudioTheme.cardBg)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07), lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Narzędzia pomocnicze

    /// Binding do karty wyszukiwanej po `id`. Gdy karta zniknie z listy, odczyt zwraca
    /// ostatni znany stan, a zapis jest ignorowany (zamiast crasha „Index out of range”).
    private func cardBinding(for config: CardIngestConfig) -> Binding<CardIngestConfig> {
        Binding(
            get: { model.cardConfigs.first(where: { $0.id == config.id }) ?? config },
            set: { newValue in
                guard let index = model.cardConfigs.firstIndex(where: { $0.id == config.id }) else { return }
                model.cardConfigs[index] = newValue
            }
        )
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

    private func formatHistoryDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        if calendar.isDateInToday(date) {
            return "Dzisiaj, \(timeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Wczoraj, \(timeFormatter.string(from: date))"
        } else {
            let df = DateFormatter()
            df.dateFormat = "dd.MM.yyyy, HH:mm"
            return df.string(from: date)
        }
    }
}

// MARK: – Launch Toggle Button (zamiast checkboxa)

/// Przycisk toggle z łuną (glow) dla akcji po zgraniu (DaVinci Resolve / Lightroom).
private struct LaunchToggleButton: View {
    let label: String
    let iconText: String
    let iconGradient: LinearGradient
    let iconTextColor: Color
    @Binding var isOn: Bool
    let themeColor: Color

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(iconText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(iconTextColor)
                    .frame(width: 17, height: 17)
                    .background(iconGradient)
                    .cornerRadius(4)

                Text(label)
                    .font(.system(size: 11, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? Color.white : Color.gray.opacity(0.75))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? themeColor.opacity(0.25) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isOn ? themeColor.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1.5)
                    )
            )
            .shadow(color: isOn ? themeColor.opacity(0.5) : .clear, radius: isOn ? 8 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isOn)
    }
}
