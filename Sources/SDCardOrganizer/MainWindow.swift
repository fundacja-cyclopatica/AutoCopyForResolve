import SwiftUI
import SDCardOrganizerCore

/// Główne okno aplikacji — macOS Studio Dark Glass UI.
struct MainWindow: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isConfirmingHistoryClear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                // Przyciemnienie tła — kliknięcie obok panelu go zamyka
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { closeSettingsPanel() }
                    .transition(.opacity)
                    .zIndex(99)

                StudioSettingsModalView(
                    model: model,
                    onClose: { closeSettingsPanel() }
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
        .frame(minWidth: 960, minHeight: 620)
        // Interfejs jest projektowany pod ciemny motyw — systemowe alerty i menu też ciemne.
        .preferredColorScheme(.dark)
        // „Ogranicz ruch” w ustawieniach dostępności wyłącza animacje sprężynowe.
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
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
                .keyboardShortcut("1", modifiers: .command)

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
                .keyboardShortcut("2", modifiers: .command)
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
                .keyboardShortcut("r", modifiers: .command)
                .help("Przeskanuj ponownie wszystkie karty (⌘R)")

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
                .keyboardShortcut(",", modifiers: .command)
                .help("Ustawienia (⌘,)")
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
            // Tytuł, wersja i ścieżka, do której trafi materiał
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(StudioTheme.accentCyan)
                        .frame(width: 8, height: 8)
                        .shadow(color: StudioTheme.accentCyan, radius: 5)

                    Text("SD Card Organizer")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)

                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("v\(version)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(StudioTheme.accentCyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(StudioTheme.accentCyan.opacity(0.10))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(StudioTheme.accentCyan.opacity(0.35), lineWidth: 1))
                    }
                }

                if let preview = model.destinationPreviewPath {
                    let addsToExisting = FileManager.default.fileExists(atPath: preview)
                    let prefix = addsToExisting ? "Dogrywanie do" : "Nowy projekt:"
                    Text("\(prefix) \(preview)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(addsToExisting ? StudioTheme.accentAmber : Color.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(addsToExisting
                              ? "Folder już istnieje — pliki zgrane wcześniej zostaną pominięte jako duplikaty."
                              : "Materiał trafi do nowego folderu projektu.")
                } else {
                    Text("Zgrywaj materiały z wielu kamer i twórz zintegrowany projekt DaVinci Resolve")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gray.opacity(0.85))
                }
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

                    TextField("np. Wesele Ani", text: $model.projectName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 160)

                    // Lista projektów istniejących na dysku — dogrywanie kolejnych kart
                    Menu {
                        if model.existingProjects.isEmpty {
                            Text("Brak projektów na dysku docelowym")
                        } else {
                            Section("Dograj do istniejącego projektu") {
                                ForEach(model.existingProjects) { project in
                                    Button(project.folderName) {
                                        model.selectExistingProject(project)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.gray)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(model.isGlobalCopying)
                    .help("Wybierz istniejący projekt, aby dograć do niego materiał")
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
                        .frame(maxWidth: 200, alignment: .leading)

                    if !model.settings.destinationRoot.isEmpty {
                        if !model.isDestinationAvailable {
                            Text("niedostępny")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(StudioTheme.accentRed)
                                .help("Folder docelowy nie istnieje — podłącz dysk albo wybierz inny folder.")
                        } else if let free = model.destinationFreeSpace {
                            let tooSmall = free < model.totalBytesToCopy
                            Text("wolne \(AppModel.formatBytes(free))")
                                .font(.system(size: 11, weight: tooSmall ? .semibold : .regular, design: .monospaced))
                                .foregroundStyle(tooSmall ? StudioTheme.accentRed : Color.gray)
                                .help(tooSmall ? "Wybrane materiały mogą się nie zmieścić na dysku docelowym." : "Wolne miejsce na dysku docelowym")
                        }
                    }

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
        GeometryReader { geometry in
            let showsEmptySlot = model.cardConfigs.count < AppModel.maxCards
            let columnWidth = Self.columnWidth(
                availableWidth: geometry.size.width,
                columns: model.cardConfigs.count + (showsEmptySlot ? 1 : 0)
            )

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: Self.columnSpacing) {
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
                        .frame(width: columnWidth)
                    }

                    // Jeśli podłączono mniej niż 4 karty, wyświetl slot wolny
                    if showsEmptySlot {
                        EmptyCardSlotView(onChooseFolder: {
                            model.addManualFolder()
                        })
                        .frame(width: columnWidth)
                    }
                }
                .padding(Self.workspacePadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let columnSpacing: CGFloat = 14
    private static let workspacePadding: CGFloat = 16

    /// Kolumny wypełniają szerokość okna (260–420 pt każda); gdy się nie mieszczą,
    /// obszar przewija się poziomo.
    private static func columnWidth(availableWidth: CGFloat, columns: Int) -> CGFloat {
        let count = CGFloat(max(1, columns))
        let usable = availableWidth - 2 * workspacePadding - columnSpacing * (count - 1)
        return min(420, max(260, usable / count))
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

                Text(model.isGlobalCopying ? "ZGRYWANIE: \(Int(model.overallProgress * 100))%" : "GOTOWY")
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
                            Text(PolishPlural.cards(enabledCount))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white)
                            Text("•")
                                .foregroundStyle(Color.white.opacity(0.2))
                            Text(PolishPlural.files(totalFiles))
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

                        // Podpowiedź, czego brakuje do rozpoczęcia zgrywania
                        if let reason = model.copyBlockedReason {
                            Text(reason)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(StudioTheme.accentAmber)
                        }
                    }

                    // Główny przycisk akcji (Vibrant Studio Action Button)
                    Button {
                        model.startBatchCopy()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(model.totalFilesToCopy == 0 ? "Wybierz materiały" : "Zgraj (\(PolishPlural.files(model.totalFilesToCopy)))")
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
                    .disabled(model.isGlobalCopying || model.copyBlockedReason != nil)
                    .opacity((model.isGlobalCopying || model.copyBlockedReason != nil) ? 0.45 : 1.0)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(model.copyBlockedReason ?? "Rozpocznij zgrywanie (⌘↩)")
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
        // Gdy otwarty jest panel ustawień, Esc zamyka panel, a nie przerywa zgrywania.
        .keyboardShortcut(model.isSettingsPanelOpen ? nil : .cancelAction)
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
                    Button("Wyczyść historię…") {
                        isConfirmingHistoryClear = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .alert("Wyczyścić historię zgrywań?", isPresented: $isConfirmingHistoryClear) {
                Button("Wyczyść", role: .destructive) {
                    IngestHistory.clear()
                    model.history = []
                }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Usunięta zostanie tylko lista sesji. Zgrane pliki na dysku pozostają bez zmian.")
            }

            if model.history.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.gray.opacity(0.7))
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
                                    Label("skopiowano \(PolishPlural.files(record.filesCopied))", systemImage: "doc.fill")
                                        .foregroundStyle(StudioTheme.accentCyan)
                                    Label(AppModel.formatBytes(record.totalBytes), systemImage: "internaldrive")
                                        .foregroundStyle(StudioTheme.accentGreen)
                                    if record.filesSkipped > 0 {
                                        Label("pominięto \(record.filesSkipped)", systemImage: "arrow.uturn.right")
                                            .foregroundStyle(Color.gray)
                                    }
                                    if record.filesFailed > 0 {
                                        Label(PolishPlural.errors(record.filesFailed), systemImage: "exclamationmark.triangle.fill")
                                            .foregroundStyle(StudioTheme.accentRed)
                                    }
                                }
                                .font(.caption)

                                Text("Źródła: \(record.sourceVolumeName)")
                                    .font(.caption)
                                    .foregroundStyle(Color.gray)
                                    .lineLimit(1)

                                HStack {
                                    Text(record.destinationPath)
                                        .font(.caption)
                                        .foregroundStyle(Color.gray.opacity(0.8))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    let folderExists = FileManager.default.fileExists(atPath: record.destinationPath)
                                    Button("Pokaż w Finderze") {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.destinationPath)])
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(!folderExists)
                                    .help(folderExists ? "Otwórz folder projektu" : "Folder niedostępny — dysk może być odłączony")
                                }
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

    private func closeSettingsPanel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            model.isSettingsPanelOpen = false
        }
    }

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
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
