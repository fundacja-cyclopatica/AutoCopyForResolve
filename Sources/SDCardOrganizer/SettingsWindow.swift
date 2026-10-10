import SwiftUI
import UniformTypeIdentifiers
import SDCardOrganizerCore

/// Okno ustawień i historii zgrań w stylu wysuwanego panelu (`Design/menu_bar_widget`).
/// Otwierane ikoną ustawień lub historii w panelu oraz z menu pod prawym klikiem ikony.
struct SettingsWindow: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(PanelTheme.border).frame(width: 1)
            Group {
                switch model.selectedTab {
                case .settings:
                    SettingsPane(model: model)
                case .history:
                    HistoryPane(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(
            LinearGradient(
                colors: [PanelTheme.backgroundTop, PanelTheme.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .preferredColorScheme(.dark)
        .onAppear {
            // Pozwala panelowi i menu otworzyć okno ponownie po jego zamknięciu.
            model.openSettingsWindowAction = { [openWindow] in
                openWindow(id: AppModel.settingsWindowID)
            }
        }
        // SwiftUI otwiera okno samo przy starcie aplikacji — chowamy je, bo główną formą
        // pracy jest panel z paska menu.
        .background(WindowAccessor { window in
            guard model.hidesSettingsWindowAtLaunch else { return }
            model.hidesSettingsWindowAtLaunch = false
            DispatchQueue.main.async {
                window.close()
            }
        })
    }

    // MARK: – Pasek boczny

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(PanelTheme.accent)
                    .frame(width: 9, height: 9)
                    .shadow(color: PanelTheme.accent.opacity(0.6), radius: 6)
                Text("SD Card Organizer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Wersja \(version)")
                    .font(.system(size: 11))
                    .foregroundStyle(PanelTheme.textSecondary)
                    .padding(.leading, 17)
            }

            Spacer().frame(height: 14)

            sidebarItem("Ustawienia", icon: "gearshape", tab: .settings, shortcut: "1")
            sidebarItem("Historia zgrań", icon: "clock.arrow.circlepath", tab: .history, shortcut: "2", badge: model.history.count)

            Spacer()

            Button {
                model.showPanelAction?()
            } label: {
                Label("Pokaż panel kart", systemImage: "sdcard")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelSecondaryButtonStyle())
            .help("Wysuń panel z kartami z paska menu")
        }
        .padding(16)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.25))
    }

    private func sidebarItem(_ title: String, icon: String, tab: AppModel.SettingsTab, shortcut: Character, badge: Int = 0) -> some View {
        let isSelected = model.selectedTab == tab
        return Button {
            model.selectedTab = tab
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? PanelTheme.accent : PanelTheme.textSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.75))
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PanelTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(PanelTheme.chip)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? PanelTheme.selectedButton : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? PanelTheme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
    }
}

// MARK: – Zakładka: Ustawienia

private struct SettingsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                paneTitle("Ustawienia", subtitle: "Zmiany zapisują się automatycznie.")

                destinationSection
                backupSection
                afterCopySection
                cameraPresetsSection
                fileTypesSection
                daVinciProjectSection
                safetySection
                menuBarIconSection
            }
            .padding(24)
        }
    }

    // MARK: Dysk docelowy

    private var destinationSection: some View {
        SettingsSection(title: "Dysk docelowy", icon: "externaldrive") {
            HStack(spacing: 8) {
                TextField("Ścieżka folderu docelowego", text: $model.settings.destinationRoot)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .panelInputStyle()
                Button("Wybierz…") { chooseDestination() }
                    .buttonStyle(PanelSecondaryButtonStyle())
            }
            HStack(spacing: 6) {
                if model.settings.destinationRoot.isEmpty {
                    Text("Nie wybrano dysku docelowego.")
                        .foregroundStyle(PanelTheme.accent)
                } else if !model.isDestinationAvailable {
                    Text("Dysk jest niedostępny — podłącz go albo wybierz inny folder.")
                        .foregroundStyle(PanelTheme.danger)
                } else if let free = model.destinationFreeSpace {
                    Text("Wolne miejsce: \(AppModel.formatBytes(free))")
                        .foregroundStyle(PanelTheme.textSecondary)
                }
                Spacer()
            }
            .font(.system(size: 11))
            SettingsNote("Materiał trafia do podfolderu <data>_<nazwa projektu> na tym dysku.")
        }
    }

    // MARK: Kopia zapasowa

    private var backupSection: some View {
        SettingsSection(title: "Kopia zapasowa", icon: "externaldrive.badge.checkmark") {
            SettingsNote("Każdy plik trafia równocześnie na drugi dysk (ta sama struktura projektu, osobna weryfikacja). Karta jest czytana tylko raz — kopia powstaje z pliku zapisanego na dysku docelowym.")
            HStack(spacing: 8) {
                TextField("Folder kopii zapasowej (puste — wyłączona)", text: $model.settings.backupDestinationRoot)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .panelInputStyle()
                Button("Wybierz…") { chooseBackupDestination() }
                    .buttonStyle(PanelSecondaryButtonStyle())
                if !model.settings.backupDestinationRoot.isEmpty {
                    Button("Wyłącz") { model.settings.backupDestinationRoot = "" }
                        .buttonStyle(PanelSecondaryButtonStyle())
                }
            }
            if !model.settings.backupDestinationRoot.isEmpty {
                HStack {
                    if !model.isBackupAvailable {
                        Text("Dysk kopii zapasowej jest niedostępny — zgrywanie poczeka, aż go podłączysz albo wyłączysz kopię.")
                            .foregroundStyle(PanelTheme.danger)
                    } else if let free = model.backupFreeSpace {
                        Text("Wolne miejsce: \(AppModel.formatBytes(free))")
                            .foregroundStyle(PanelTheme.textSecondary)
                    }
                    Spacer()
                }
                .font(.system(size: 11))
            }
        }
    }

    // MARK: Po zgraniu

    private var afterCopySection: some View {
        SettingsSection(title: "Po zgraniu", icon: "arrow.up.forward.app") {
            SettingsSwitchRow(
                title: "Otwórz projekt w DaVinci Resolve",
                description: "Otwiera plik .drp projektu (albo samą aplikację, gdy brak szablonu).",
                accent: PanelTheme.davinciAccent,
                isOn: $model.settings.openInDaVinciResolve
            )
            SettingsSwitchRow(
                title: "Otwórz folder zdjęć w Adobe Lightroom",
                description: "Przekazuje folder Zdjęcia do Lightroom Classic lub Lightroom.",
                accent: PanelTheme.lightroomAccent,
                isOn: $model.settings.openInLightroom
            )
            SettingsSwitchRow(
                title: "Wysuń karty po udanym zgraniu",
                description: "Tylko gdy wszystkie pliki zgrały się bez błędów i zgrywanie nie zostało anulowane.",
                accent: PanelTheme.accent,
                isOn: $model.settings.ejectCardsAfterIngest
            )
            SettingsSwitchRow(
                title: "Zapisuj raport zgrania z sumami kontrolnymi",
                description: "W folderze projektu powstaje Raport_zgrania_….txt i Sumy_kontrolne_….sha256 (sprawdzenie: shasum -a 256 -c).",
                accent: PanelTheme.accent,
                isOn: $model.settings.writeIngestReport
            )
        }
    }

    // MARK: Presety kamer

    private var cameraPresetsSection: some View {
        SettingsSection(title: "Podpisy kamer", icon: "tag") {
            SettingsNote("Podpis kamery jest nazwą podfolderu w projekcie (np. Video/Kamera A). Presety pojawiają się w menu podpisu na karcie.")

            HStack(spacing: 8) {
                TextField("Nowy podpis (np. Sony FX3)", text: $model.newPresetInputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .panelInputStyle()
                    .onSubmit(addPreset)
                Button("Dodaj", action: addPreset)
                    .buttonStyle(PanelSecondaryButtonStyle())
                    .disabled(model.newPresetInputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(model.settings.cameraPresets.enumerated()), id: \.offset) { index, preset in
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(PanelTheme.accent)
                        Text(preset)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button {
                            model.removeCameraPreset(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(PanelTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Usuń preset „\(preset)”")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PanelTheme.chip)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
                }
            }

            Button("Przywróć domyślne podpisy") {
                model.settings.cameraPresets = Settings.defaultCameraPresets
            }
            .buttonStyle(PanelSecondaryButtonStyle())
        }
    }

    private func addPreset() {
        model.addCameraPreset(model.newPresetInputText)
        model.newPresetInputText = ""
    }

    // MARK: Typy plików

    private var fileTypesSection: some View {
        SettingsSection(title: "Typy plików", icon: "doc.on.doc") {
            HStack(spacing: 8) {
                Button("Zaznacz wszystkie") {
                    model.settings.enabledExtensions = MediaFormats.allExtensions
                }
                Button("Odznacz wszystkie") {
                    model.settings.enabledExtensions = []
                }
                Spacer()
                Button("Przywróć domyślne") {
                    model.settings.enabledExtensions = Settings.defaultExtensions
                }
            }
            .buttonStyle(PanelSecondaryButtonStyle())

            ForEach(MediaFormats.groups, id: \.title) { group in
                let enabledCount = group.formats.filter { model.settings.enabledExtensions.contains($0.ext) }.count
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(group.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(enabledCount) z \(group.formats.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(PanelTheme.textSecondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 6)], alignment: .leading, spacing: 4) {
                        ForEach(group.formats, id: \.ext) { format in
                            Toggle(format.label, isOn: extensionBinding(format.ext))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 12))
                                .tint(PanelTheme.accent)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PanelTheme.cardInner)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            SettingsSwitchRow(
                title: "Zgrywaj pliki towarzyszące",
                description: "Metadane Sony (C0001M01.XML), telemetria DJI (.SRT) i ustawienia RAW (.XMP) trafiają obok materiału.",
                accent: PanelTheme.accent,
                isOn: $model.settings.copySidecarFiles
            )

            SettingsNote("Po zmianie typów plików karty są skanowane ponownie. Miniatury kamer (np. Sony THMBNL) są zawsze pomijane.")
        }
    }

    private func extensionBinding(_ ext: String) -> Binding<Bool> {
        Binding(
            get: { model.settings.enabledExtensions.contains(ext) },
            set: { enabled in
                if enabled {
                    model.settings.enabledExtensions.insert(ext)
                } else {
                    model.settings.enabledExtensions.remove(ext)
                }
            }
        )
    }

    // MARK: Projekt DaVinci Resolve

    private var daVinciProjectSection: some View {
        SettingsSection(title: "Projekt DaVinci Resolve", icon: "film") {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    SettingsLabel("Rozdzielczość")
                    TextField("np. 1920x1080", text: $model.settings.resolution)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .panelInputStyle()
                        .frame(width: 160)
                }
                VStack(alignment: .leading, spacing: 5) {
                    SettingsLabel("Liczba klatek")
                    Stepper(value: $model.settings.frameRate, in: 23.976...120, step: 1) {
                        Text("\(String(format: "%.0f", model.settings.frameRate)) fps")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                SettingsLabel("Szablon projektu .drp (opcjonalny)")
                HStack(spacing: 8) {
                    TextField("Wzorcowy plik .drp", text: drpTemplateBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .panelInputStyle()
                    Button("Wybierz…") { chooseTemplate() }
                        .buttonStyle(PanelSecondaryButtonStyle())
                }
            }

            SettingsNote("Wyeksportuj raz pusty projekt z DaVinci Resolve (File → Export Project) i wskaż go jako szablon. Bez szablonu powstaje folder projektu i manifest JSON.")
        }
    }

    private var drpTemplateBinding: Binding<String> {
        Binding(
            get: { model.settings.drpTemplatePath ?? "" },
            set: { model.settings.drpTemplatePath = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: Bezpieczeństwo

    private var safetySection: some View {
        SettingsSection(title: "Weryfikacja", icon: "checkmark.shield") {
            SettingsSwitchRow(
                title: "Weryfikuj każdą kopię sumą kontrolną SHA-256",
                description: "Zalecane. Zapisany plik jest ponownie odczytywany z dysku i porównywany z kartą.",
                accent: PanelTheme.accent,
                isOn: $model.settings.verifyCopies
            )
            SettingsSwitchRow(
                title: "Porównuj sumy kontrolne przy wykrywaniu duplikatów",
                description: "Wolniejsze. Bez tej opcji duplikat rozpoznawany jest po rozmiarze i dacie pliku.",
                accent: PanelTheme.accent,
                isOn: $model.settings.verifyChecksums
            )
        }
    }

    // MARK: Ikona w pasku menu

    private var menuBarIconSection: some View {
        SettingsSection(title: "Ikona w pasku menu", icon: "menubar.rectangle") {
            HStack(spacing: 8) {
                ForEach(MenuBarIconStyle.allCases, id: \.self) { style in
                    iconStyleOption(style)
                }
            }

            if model.settings.menuBarIconStyle == .custom || model.settings.customMenuBarIconPath != nil {
                HStack(spacing: 10) {
                    if let path = model.settings.customMenuBarIconPath, let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image)
                            .resizable()
                            .renderingMode(model.settings.customMenuBarIconIsTemplate ? .template : .original)
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(PanelTheme.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("Nie wgrano jeszcze własnej ikony.")
                            .font(.system(size: 11))
                            .foregroundStyle(PanelTheme.accent)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Button("Wgraj własną ikonę…") { chooseCustomIcon() }
                    .buttonStyle(PanelSecondaryButtonStyle())
                if model.settings.customMenuBarIconPath != nil {
                    Button("Usuń własną ikonę") { model.removeCustomMenuBarIcon() }
                        .buttonStyle(PanelSecondaryButtonStyle())
                }
                Spacer()
            }

            if model.settings.customMenuBarIconPath != nil {
                SettingsSwitchRow(
                    title: "Dopasuj kolor własnej ikony do paska menu",
                    description: "Ikona jest rysowana jako kształt: biała na ciemnym pasku, czarna na jasnym. Wyłącz, aby zachować jej oryginalne kolory.",
                    accent: PanelTheme.accent,
                    isOn: $model.settings.customMenuBarIconIsTemplate
                )
            }

            SettingsNote("Najlepiej PNG lub PDF z przezroczystym tłem, ok. 36×36 px (lub wektor). Ikona zostanie przeskalowana do wysokości paska menu.")
        }
    }

    private func iconStyleOption(_ style: MenuBarIconStyle) -> some View {
        let isSelected = model.settings.menuBarIconStyle == style
        let isUnavailable = style == .custom && model.settings.customMenuBarIconPath == nil
        return Button {
            if isUnavailable {
                chooseCustomIcon()
            } else {
                model.settings.menuBarIconStyle = style
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    iconPreview(style, onDarkBar: true)
                    iconPreview(style, onDarkBar: false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(Self.title(of: style))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : PanelTheme.textSecondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? PanelTheme.selectedButton : PanelTheme.cardInner)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? PanelTheme.accent.opacity(0.6) : PanelTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(Self.help(of: style))
    }

    /// Podgląd ikony na ciemnym i jasnym pasku menu.
    @ViewBuilder
    private func iconPreview(_ style: MenuBarIconStyle, onDarkBar: Bool) -> some View {
        let automaticColor: Color = onDarkBar ? .white : .black
        let color: Color = {
            switch style {
            case .automatic, .custom: return automaticColor
            case .white: return .white
            case .black: return .black
            case .accent: return PanelTheme.accent
            }
        }()
        Group {
            if style == .custom, let path = model.settings.customMenuBarIconPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(model.settings.customMenuBarIconIsTemplate ? .template : .original)
                    .scaledToFit()
                    .foregroundStyle(color)
            } else if style == .custom {
                Image(systemName: "plus")
                    .foregroundStyle(automaticColor.opacity(0.6))
            } else {
                Image(systemName: "sdcard.fill")
                    .foregroundStyle(color)
            }
        }
        .font(.system(size: 13))
        .frame(width: 16, height: 16)
        .frame(width: 34, height: 26)
        .background(onDarkBar ? Color(white: 0.12) : Color(white: 0.92))
    }

    private static func title(of style: MenuBarIconStyle) -> String {
        switch style {
        case .automatic: return "Automatyczna"
        case .white: return "Biała"
        case .black: return "Czarna"
        case .accent: return "Akcent"
        case .custom: return "Własna"
        }
    }

    private static func help(of style: MenuBarIconStyle) -> String {
        switch style {
        case .automatic: return "Biała na ciemnym pasku menu, czarna na jasnym (zalecane)"
        case .white: return "Zawsze biała"
        case .black: return "Zawsze czarna"
        case .accent: return "Musztardowa, gdy są podłączone karty; w przeciwnym razie automatyczna"
        case .custom: return "Własny obraz wgrany z dysku"
        }
    }

    private func chooseCustomIcon() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .pdf, .svg, .tiff, .jpeg, .heic, .icns]
        panel.message = "Wybierz obraz ikony do paska menu (PNG, PDF, SVG…)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.importCustomMenuBarIcon(from: url)
        } catch {
            model.setStatus(error.localizedDescription, isError: true)
            let alert = NSAlert()
            alert.messageText = "Nie udało się wgrać ikony"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: Okna wyboru

    private func chooseBackupDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Wybierz dysk/folder kopii zapasowej"
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.backupDestinationRoot = url.path
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Wybierz dysk/folder docelowy"
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.destinationRoot = url.path
        }
    }

    private func chooseTemplate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "drp") ?? .data]
        panel.message = "Wybierz wzorcowy plik .drp"
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.drpTemplatePath = url.path
        }
    }
}

// MARK: – Zakładka: Historia

private struct HistoryPane: View {
    @ObservedObject var model: AppModel
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                paneTitle(
                    "Historia zgrań",
                    subtitle: model.history.isEmpty
                        ? "Brak zapisanych sesji."
                        : PolishPlural.format(model.history.count, one: "zapisana sesja", few: "zapisane sesje", many: "zapisanych sesji")
                )
                Spacer()
                if !model.history.isEmpty {
                    Button("Wyczyść historię…") { isConfirmingClear = true }
                        .buttonStyle(PanelSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            if model.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(PanelTheme.textMuted)
                    Text("Tu pojawią się sesje zgrywania z panelu.")
                        .font(.system(size: 13))
                        .foregroundStyle(PanelTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.history) { record in
                            HistoryRow(record: record)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .alert("Wyczyścić historię zgrań?", isPresented: $isConfirmingClear) {
            Button("Wyczyść", role: .destructive) {
                IngestHistory.clear()
                model.history = []
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Usunięta zostanie tylko lista sesji. Zgrane pliki na dysku pozostają bez zmian.")
        }
    }
}

private struct HistoryRow: View {
    let record: IngestRecord

    var body: some View {
        let folderExists = FileManager.default.fileExists(atPath: record.destinationPath)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(record.filesFailed > 0 ? PanelTheme.danger : PanelTheme.success)
                    .frame(width: 7, height: 7)
                Text(record.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(Self.formatDate(record.date))
                    .font(.system(size: 11))
                    .foregroundStyle(PanelTheme.textSecondary)
            }

            HStack(spacing: 6) {
                statChip("doc.fill", "skopiowano \(PolishPlural.files(record.filesCopied))", color: .white)
                statChip("internaldrive", AppModel.formatBytes(record.totalBytes), color: PanelTheme.accent)
                if record.filesSkipped > 0 {
                    statChip("arrow.uturn.right", "pominięto \(record.filesSkipped)", color: PanelTheme.textSecondary)
                }
                if record.filesFailed > 0 {
                    statChip("exclamationmark.triangle.fill", PolishPlural.errors(record.filesFailed), color: PanelTheme.danger)
                }
            }

            Text("Źródła: \(record.sourceVolumeName)")
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.textSecondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(record.destinationPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Pokaż w Finderze") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.destinationPath)])
                }
                .buttonStyle(PanelSecondaryButtonStyle())
                .disabled(!folderExists)
                .help(folderExists ? "Otwórz folder projektu" : "Folder niedostępny — dysk może być odłączony")
            }
        }
        .padding(14)
        .background(PanelTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PanelTheme.border, lineWidth: 1))
    }

    private func statChip(_ icon: String, _ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(PanelTheme.chip)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
    }

    private static func formatDate(_ date: Date) -> String {
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Dzisiaj, \(time.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Wczoraj, \(time.string(from: date))"
        }
        let full = DateFormatter()
        full.dateFormat = "dd.MM.yyyy, HH:mm"
        return full.string(from: date)
    }
}

// MARK: – Elementy wspólne

private func paneTitle(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
        Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(PanelTheme.textSecondary)
    }
}

/// Karta sekcji ustawień w stylu panelu.
private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PanelTheme.accent)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(PanelTheme.textSecondary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PanelTheme.border, lineWidth: 1))
    }
}

/// Wiersz z przełącznikiem — po włączeniu podświetlony kolorem `accent`.
private struct SettingsSwitchRow: View {
    let title: String
    let description: String
    let accent: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.8))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(PanelTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack {
                PanelTheme.cardInner
                if isOn {
                    LinearGradient(colors: [accent.opacity(0.14), accent.opacity(0.03)], startPoint: .leading, endPoint: .trailing)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isOn ? accent.opacity(0.45) : PanelTheme.border, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

private struct SettingsLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(PanelTheme.textSecondary)
    }
}

private struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(PanelTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Przycisk drugorzędny w stylu panelu (grafitowe tło, cienka ramka).
struct PanelSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? Color.white.opacity(0.9) : PanelTheme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? PanelTheme.selectedButton : PanelTheme.chip)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
    }
}

private extension View {
    /// Pole tekstowe w stylu panelu.
    func panelInputStyle() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(PanelTheme.cardInner)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
    }
}

// MARK: – Dostęp do NSWindow

/// Przekazuje okno, w którym znalazł się widok (jednorazowo po dołączeniu do okna).
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        WindowObservingView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowObservingView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow(window)
            }
        }
    }
}
