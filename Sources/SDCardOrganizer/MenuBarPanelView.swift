import SwiftUI
import SDCardOrganizerCore

/// Zawartość wysuwanego panelu z paska menu (projekt `Design/menu_bar_widget`).
struct MenuBarPanelView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    /// Naturalna wysokość treści — kontroler dopasowuje do niej wysokość okna.
    let onHeightChange: (CGFloat) -> Void
    /// Uruchamia akcję z oknem systemowym (wybór folderu, alert) ponad panelem.
    let performModal: (() -> Void) -> Void

    @State private var headerHeight: CGFloat = 0
    @State private var cardsHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0
    @State private var expandedCardIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .reportHeight { headerHeight = $0; publishTotalHeight() }

            // Karty: naturalna wysokość, a gdy panel nie mieści się na ekranie — przewijanie
            ScrollView(.vertical, showsIndicators: true) {
                cardsList
                    .reportHeight { cardsHeight = $0; publishTotalHeight() }
            }
            .frame(maxHeight: cardsHeight)

            bottomSections
                .fixedSize(horizontal: false, vertical: true)
                .reportHeight { bottomHeight = $0; publishTotalHeight() }
        }
        .frame(width: PanelTheme.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: [PanelTheme.backgroundTop, PanelTheme.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PanelTheme.border, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }

    private func publishTotalHeight() {
        onHeightChange(headerHeight + cardsHeight + bottomHeight)
    }

    // MARK: – Nagłówek

    private var statusText: String {
        if model.isGlobalCopying { return "Zgrywanie \(Int(model.overallProgress * 100))%" }
        if model.cardConfigs.isEmpty { return "Brak kart" }
        if model.cardConfigs.contains(where: \.isScanning) { return "Skanowanie…" }
        return model.totalFilesToCopy > 0 ? "Gotowe do zgrania" : "Nic do zgrania"
    }

    private var statusColor: Color {
        model.cardConfigs.isEmpty ? PanelTheme.textMuted : PanelTheme.accent
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: statusColor.opacity(0.6), radius: 6)
                    (Text("Karty pamięci: ").foregroundColor(.white)
                        + Text(statusText).foregroundColor(statusColor).bold())
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("SD Card Organizer")
                        .foregroundStyle(PanelTheme.textSecondary)
                    if !model.cardConfigs.isEmpty {
                        Text("•").foregroundStyle(PanelTheme.textMuted)
                        Text(PolishPlural.format(
                            model.cardConfigs.count,
                            one: "podłączony nośnik", few: "podłączone nośniki", many: "podłączonych nośników"
                        ))
                        .foregroundStyle(Color.white.opacity(0.85))
                        Text("•").foregroundStyle(PanelTheme.textMuted)
                        Text(PolishPlural.format(
                            model.totalFilesToCopy,
                            one: "nowe ujęcie", few: "nowe ujęcia", many: "nowych ujęć"
                        ))
                        .foregroundStyle(Color.white)
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Otwiera pełne okno aplikacji (historia, szczegółowe ustawienia)
            Button {
                onClose()
                model.showMainWindow()
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .background(PanelTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Otwórz pełne okno aplikacji")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PanelTheme.border).frame(height: 1)
        }
    }

    // MARK: – Karty

    private var cardsList: some View {
        VStack(spacing: 12) {
            if model.cardConfigs.isEmpty {
                emptyState
                    .transition(.opacity)
            }
            ForEach(Array(model.cardConfigs.enumerated()), id: \.element.id) { _, config in
                PanelCardRow(
                    config: cardBinding(for: config),
                    cameraPresets: model.settings.cameraPresets,
                    isLocked: model.isGlobalCopying,
                    isExpanded: Binding(
                        get: { expandedCardIDs.contains(config.id) },
                        set: { expanded in
                            if expanded { expandedCardIDs.insert(config.id) } else { expandedCardIDs.remove(config.id) }
                        }
                    ),
                    onEject: { model.ejectCard(url: config.volumeURL) },
                    onRescan: { model.scanCard(url: config.volumeURL) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            if !model.cardConfigs.isEmpty && model.cardConfigs.count < AppModel.maxCards {
                Button {
                    performModal { model.addManualFolder() }
                } label: {
                    Label("Dodaj folder ze źródłem…", systemImage: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PanelTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(model.isGlobalCopying)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.cardConfigs.map(\.id))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sdcard")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(PanelTheme.textMuted)
            Text("Włóż kartę SD do czytnika")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Panel rozszerzy się automatycznie o każdą podłączoną kartę.")
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Wybierz folder ręcznie…") {
                performModal { model.addManualFolder() }
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(PanelTheme.card.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(PanelTheme.borderStrong)
        )
    }

    /// Binding do karty po `id` — bezpieczny przy wysunięciu karty w trakcie wyświetlania.
    private func cardBinding(for config: CardIngestConfig) -> Binding<CardIngestConfig> {
        Binding(
            get: { model.cardConfigs.first(where: { $0.id == config.id }) ?? config },
            set: { newValue in
                guard let index = model.cardConfigs.firstIndex(where: { $0.id == config.id }) else { return }
                model.cardConfigs[index] = newValue
            }
        )
    }

    // MARK: – Część dolna (dysk, aplikacje, podsumowanie, stopka)

    private var bottomSections: some View {
        VStack(spacing: 0) {
            destinationBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            launchToggles
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.25))
                .overlay(alignment: .top) { Rectangle().fill(PanelTheme.border).frame(height: 1) }

            if let session = model.lastSession, !model.isGlobalCopying {
                PanelSessionResult(
                    session: session,
                    onReveal: { model.revealInFinder(session) },
                    onEject: {
                        model.ejectCards(of: session)
                        model.lastSession = nil
                    },
                    onDismiss: { model.lastSession = nil }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            summaryAndAction
                .padding(16)
                .background(
                    LinearGradient(colors: [.clear, Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                )
                .overlay(alignment: .top) { Rectangle().fill(PanelTheme.border).frame(height: 1) }

            footer
        }
    }

    private var destinationBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                performModal { chooseDestination() }
            } label: {
                Image(systemName: "externaldrive")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(PanelTheme.tile)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(model.isGlobalCopying)
            .help("Zmień dysk docelowy")

            VStack(alignment: .leading, spacing: 4) {
                Text(model.settings.destinationRoot.isEmpty
                     ? "Dysk docelowy: wybierz folder…"
                     : "Dysk docelowy: \(model.destinationVolumeName ?? URL(fileURLWithPath: model.settings.destinationRoot).lastPathComponent)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.settings.destinationRoot.isEmpty ? PanelTheme.accent : .white)
                    .lineLimit(1)

                // Nazwa projektu z listą projektów istniejących na dysku
                HStack(spacing: 6) {
                    TextField("Nazwa projektu (np. Wesele Ani)", text: $model.projectName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PanelTheme.cardInner)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
                        .disabled(model.isGlobalCopying)

                    Menu {
                        if model.existingProjects.isEmpty {
                            Text("Brak projektów na dysku docelowym")
                        } else {
                            Section("Dograj do istniejącego projektu") {
                                ForEach(model.existingProjects) { project in
                                    Button(project.folderName) { model.selectExistingProject(project) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PanelTheme.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(model.isGlobalCopying)
                    .help("Wybierz istniejący projekt")
                }

                if let preview = model.destinationPreviewPath {
                    Text(preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(FileManager.default.fileExists(atPath: preview) ? PanelTheme.accent : PanelTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(FileManager.default.fileExists(atPath: preview)
                              ? "Dogrywanie do istniejącego folderu projektu"
                              : "Nowy folder projektu")
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Wolne")
                    .font(.system(size: 10))
                    .foregroundStyle(PanelTheme.textSecondary)
                if model.settings.destinationRoot.isEmpty {
                    Text("—").font(.system(size: 12, weight: .semibold))
                } else if !model.isDestinationAvailable {
                    Text("niedostępny")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PanelTheme.danger)
                } else if let free = model.destinationFreeSpace {
                    Text(AppModel.formatBytes(free))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(free < model.totalBytesToCopy ? PanelTheme.danger : .white)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(PanelTheme.destination)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PanelTheme.border, lineWidth: 1))
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

    private var launchToggles: some View {
        HStack(spacing: 8) {
            PanelAppToggle(
                title: "Otwórz DaVinci",
                badge: { davinciBadge },
                isOn: $model.settings.openInDaVinciResolve
            )
            PanelAppToggle(
                title: "Otwórz Lightroom",
                badge: {
                    Text("LrC")
                        .font(.system(size: 9.5, weight: .black))
                        .foregroundStyle(.white)
                },
                isOn: $model.settings.openInLightroom
            )
        }
    }

    private var davinciBadge: some View {
        ZStack {
            Circle().fill(Color(white: 0.83)).frame(width: 5, height: 5).offset(y: -3.5)
            Circle().fill(Color(white: 0.63)).frame(width: 5, height: 5).offset(x: -3.5, y: 2.5)
            Circle().fill(Color(white: 0.45)).frame(width: 5, height: 5).offset(x: 3.5, y: 2.5)
        }
    }

    private var summaryAndAction: some View {
        HStack(alignment: .center, spacing: 12) {
            if let transfer = model.transfer {
                // W trakcie zgrywania: postęp, prędkość i czas do końca
                VStack(alignment: .leading, spacing: 5) {
                    Text("ZGRYWANIE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(PanelTheme.textSecondary)
                    ProgressView(value: transfer.fraction)
                        .tint(PanelTheme.accent)
                    HStack(spacing: 5) {
                        Text("\(AppModel.formatBytes(transfer.processedBytes)) z \(AppModel.formatBytes(transfer.totalBytes))")
                        Text("•").foregroundStyle(PanelTheme.textMuted)
                        Text(transfer.bytesPerSecond.map { "\(AppModel.formatBytes(Int64($0)))/s" } ?? "mierzę…")
                            .foregroundStyle(PanelTheme.accent)
                        Text("•").foregroundStyle(PanelTheme.textMuted)
                        Text(transfer.secondsRemaining.map { "~\(AppModel.formatDuration($0))" } ?? "szacuję…")
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
                }

                Spacer(minLength: 8)

                Button {
                    model.cancelCopy()
                } label: {
                    Label(transfer.isCancelling ? "Anulowanie…" : "Anuluj", systemImage: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .foregroundStyle(PanelTheme.danger)
                        .background(PanelTheme.danger.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(PanelTheme.danger.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(transfer.isCancelling)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PODSUMOWANIE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(PanelTheme.textSecondary)
                    HStack(spacing: 6) {
                        Text(PolishPlural.cards(model.enabledCards.count)).bold()
                        Text("•").foregroundStyle(PanelTheme.textMuted)
                        Text(PolishPlural.files(model.totalFilesToCopy))
                        Text("•").foregroundStyle(PanelTheme.textMuted)
                        Text(AppModel.formatBytes(model.totalBytesToCopy))
                            .bold()
                            .foregroundStyle(PanelTheme.accent)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                    if let reason = model.copyBlockedReason {
                        Text(reason)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PanelTheme.accent.opacity(0.9))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                let isBlocked = model.copyBlockedReason != nil
                Button {
                    // Ostrzeżenie o miejscu (NSAlert) musi pojawić się nad panelem.
                    performModal { model.startBatchCopy() }
                } label: {
                    Label("Szybki zrzut (\(AppModel.formatBytes(model.totalBytesToCopy)))", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color(red: 12/255, green: 13/255, blue: 14/255))
                        .background(PanelTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: PanelTheme.accent.opacity(isBlocked ? 0 : 0.45), radius: 10)
                }
                .buttonStyle(.plain)
                .disabled(isBlocked)
                .opacity(isBlocked ? 0.45 : 1)
                .keyboardShortcut(.return, modifiers: .command)
                .help(model.copyBlockedReason ?? "Zgraj wybrane materiały (⌘↩)")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                onClose()
                model.showMainWindow()
            } label: {
                Label("Pełne okno", systemImage: "macwindow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PanelTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Historia, szczegółowe ustawienia i widok kolumn")

            Spacer()

            footerIconButton("arrow.counterclockwise", help: "Przeskanuj karty ponownie (⌘R)") {
                model.scanAllCards()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isGlobalCopying)

            footerIconButton("gearshape", help: "Ustawienia programu") {
                onClose()
                model.showMainWindow(openingSettings: true)
            }

            Button("Zamknij") {
                onClose()
            }
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
            .help("Schowaj panel (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(PanelTheme.border).frame(height: 1) }
    }

    private func footerIconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PanelTheme.textSecondary)
                .frame(width: 26, height: 26)
                .background(PanelTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: – Przełącznik aplikacji docelowej (DaVinci / Lightroom)

private struct PanelAppToggle<Badge: View>: View {
    let title: String
    @ViewBuilder let badge: () -> Badge
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            badge()
                .frame(width: 24, height: 24)
                .background(PanelTheme.cardInner)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(PanelTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PanelTheme.border, lineWidth: 1))
    }
}

// MARK: – Wynik ostatniej sesji

private struct PanelSessionResult: View {
    let session: IngestSessionSummary
    let onReveal: () -> Void
    let onEject: () -> Void
    let onDismiss: () -> Void

    private var color: Color {
        if session.wasCancelled { return PanelTheme.accent }
        return session.failures.isEmpty ? PanelTheme.success : PanelTheme.danger
    }

    private var title: String {
        if session.wasCancelled { return "Zgrywanie anulowane" }
        return session.failures.isEmpty ? "Zgrano pomyślnie" : "Zgrano z błędami"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: session.failures.isEmpty && !session.wasCancelled
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PanelTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Ukryj wynik")
            }

            Text(resultLine)
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.textSecondary)

            if let failure = session.failures.first {
                Text("\(failure.url.lastPathComponent): \(failure.error)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PanelTheme.danger)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button("Pokaż w Finderze", action: onReveal)
                if session.cards.contains(where: { !$0.isManual }) {
                    Button("Wysuń karty", action: onEject)
                        .disabled(!session.isSafeToEject)
                        .help(session.isSafeToEject
                              ? "Bezpiecznie wysuń zgrane karty"
                              : "Nie wszystkie pliki zostały zgrane — nie wysuwaj kart przed sprawdzeniem")
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.35), lineWidth: 1))
    }

    private var resultLine: String {
        var parts = ["\(PolishPlural.files(session.totalCopied)) (\(AppModel.formatBytes(session.totalBytes)))"]
        if session.verificationEnabled && session.totalCopied > 0 {
            parts.append("zweryfikowano \(session.totalVerified)")
        }
        if session.totalSkipped > 0 {
            parts.append("pominięto \(session.totalSkipped)")
        }
        if !session.failures.isEmpty {
            parts.append(PolishPlural.errors(session.failures.count))
        }
        parts.append("w \(AppModel.formatDuration(session.duration))")
        return parts.joined(separator: " • ")
    }
}

// MARK: – Pomiar wysokości

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    /// Zgłasza wysokość widoku po każdej zmianie układu.
    func reportHeight(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(PanelHeightKey.self, perform: action)
    }
}
