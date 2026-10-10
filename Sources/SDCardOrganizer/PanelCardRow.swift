import SwiftUI
import SDCardOrganizerCore

/// Wiersz karty w wysuwanym panelu: nazwa i podpis kamery, wolne miejsce, zakres dni,
/// typy materiałów i podsumowanie wyboru (rozwijane do listy dni).
struct PanelCardRow: View {
    @Binding var config: CardIngestConfig
    let cameraPresets: [String]
    /// Trwa zgrywanie — wybór materiałów, wysuwanie i podpis są zablokowane.
    let isLocked: Bool
    @Binding var isExpanded: Bool
    let onEject: () -> Void
    let onRescan: () -> Void

    @State private var isEditingLabel = false
    @State private var labelDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow

            if config.isScanning {
                scanningRow
            } else if config.scannedFiles.isEmpty {
                emptyRow
            } else {
                Rectangle().fill(PanelTheme.border).frame(height: 1)
                rangeRow
                    .disabled(isLocked)
                if config.isCopying {
                    progressRow
                } else {
                    selectionSummary
                }
            }

            if !config.isCopying, let report = config.lastReport, report.totalFailed > 0 {
                failuresRow(report)
            }
        }
        .padding(14)
        .background(PanelTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PanelTheme.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 4)
        .opacity(config.isEnabled ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.2), value: config.isEnabled)
    }

    // MARK: – Nagłówek karty

    private var topRow: some View {
        HStack(spacing: 10) {
            Image(systemName: config.isManual ? "folder" : "sdcard")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: 32, height: 32)
                .background(PanelTheme.tile)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))

            HStack(spacing: 8) {
                Text(config.volumeName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                labelChip
            }

            Spacer(minLength: 6)

            if let total = config.totalCapacity, let available = config.availableCapacity, total > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    (Text("Wolne: ").foregroundColor(PanelTheme.textSecondary)
                        + Text(AppModel.formatBytes(Int64(available))).foregroundColor(.white)
                        + Text(" / \(AppModel.formatBytes(Int64(total)))").foregroundColor(PanelTheme.textSecondary))
                        .font(.system(size: 10))
                        .lineLimit(1)
                    usageBar(used: 1 - Double(available) / Double(total))
                }
            }

            Toggle("", isOn: $config.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(PanelTheme.accent)
                .disabled(isLocked)
                .help(config.isEnabled ? "Karta uwzględniona w zgrywaniu" : "Karta pomijana przy zgrywaniu")

            Button(action: onEject) {
                Image(systemName: config.isManual ? "xmark" : "eject")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PanelTheme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLocked)
            .help(config.isManual ? "Usuń folder z listy" : "Wysuń bezpiecznie \(config.volumeName)")
        }
    }

    /// Pasek zajętości karty (część zajęta na musztardowo).
    private func usageBar(used: Double) -> some View {
        let width: CGFloat = 96
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(PanelTheme.cardInner)
                .overlay(Capsule().stroke(PanelTheme.border, lineWidth: 1))
            Capsule()
                .fill(PanelTheme.accent)
                .frame(width: max(4, width * CGFloat(min(1, max(0, used)))))
                .shadow(color: PanelTheme.accent.opacity(0.5), radius: 5)
        }
        .frame(width: width, height: 6)
    }

    /// Podpis kamery: menu z presetami albo pole do wpisania własnej nazwy.
    @ViewBuilder
    private var labelChip: some View {
        if isEditingLabel {
            TextField("Podpis kamery", text: $labelDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 120)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(PanelTheme.cardInner)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(PanelTheme.accent.opacity(0.6), lineWidth: 1))
                .onSubmit {
                    let trimmed = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { config.cameraLabel = trimmed }
                    isEditingLabel = false
                }
        } else {
            Menu {
                ForEach(cameraPresets, id: \.self) { preset in
                    Button(preset) { config.cameraLabel = preset }
                }
                Divider()
                Button("Własny podpis…") {
                    labelDraft = config.cameraLabel
                    isEditingLabel = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(config.cameraLabel.isEmpty ? "Bez podpisu" : config.cameraLabel)
                    Image(systemName: "square.and.pencil")
                }
                .font(.system(size: 10.5, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(PanelTheme.chip)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(PanelTheme.borderStrong, lineWidth: 1))
            .disabled(isLocked)
            .help("Podpis kamery — nazwa podfolderu w projekcie")
        }
    }

    // MARK: – Zakres i typy materiałów

    private var rangeRow: some View {
        // Gdy pełne etykiety się nie mieszczą, używamy krótszych.
        ViewThatFits(in: .horizontal) {
            rangeRowContent(compact: false)
            rangeRowContent(compact: true)
        }
    }

    private func rangeRowContent(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Text("Zakres:")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(PanelTheme.textSecondary)

            if let latest = config.availableDays.first {
                rangeButton(
                    compact ? "Najnowszy" : "Najnowszy (\(latest.dayString))",
                    isSelected: config.isLatestDayOnlySelected
                ) {
                    config.selectLatestDay()
                }
            }

            let dayCount = config.availableDays.count
            rangeButton(
                dayCount > 1
                    ? (compact ? "Wszystkie (\(dayCount))" : "Wszystkie (\(PolishPlural.format(dayCount, one: "dzień", few: "dni", many: "dni")))")
                    : "Wszystkie dni",
                isSelected: dayCount > 1 && config.areAllDaysSelected
            ) {
                config.selectAllDays()
            }

            Spacer(minLength: 6)

            if config.totalVideoCount > 0 {
                mediaBadge(icon: "video", text: "\(config.totalVideoCount) wideo", isOn: $config.includeVideos)
            }
            if config.totalPhotoCount > 0 {
                mediaBadge(icon: "photo", text: PolishPlural.photos(config.totalPhotoCount), isOn: $config.includePhotos)
            }
            if config.totalAudioCount > 0 {
                mediaBadge(icon: "waveform", text: "\(config.totalAudioCount) audio", isOn: $config.includeAudio)
            }
        }
    }

    private func rangeButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : PanelTheme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? PanelTheme.selectedButton : Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? PanelTheme.selectedBorder : Color.white.opacity(0.05), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// Plakietka typu materiału — kliknięcie włącza/wyłącza zgrywanie tego typu.
    private func mediaBadge(icon: String, text: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(text)
                    .strikethrough(!isOn.wrappedValue)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(isOn.wrappedValue ? Color.white.opacity(0.9) : PanelTheme.textMuted)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isOn.wrappedValue ? PanelTheme.chip : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(PanelTheme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(isOn.wrappedValue ? "Kliknij, aby pominąć: \(text)" : "Kliknij, aby zgrać: \(text)")
    }

    // MARK: – Podsumowanie wyboru i lista dni

    private var selectionTitle: String {
        switch config.selectedDays.count {
        case 0: return "Nic nie wybrano"
        case 1: return config.selectedDays.first ?? ""
        default: return PolishPlural.format(config.selectedDays.count, one: "dzień", few: "dni", many: "dni")
        }
    }

    private var selectionSummary: some View {
        let canExpand = config.availableDays.count > 1
        return VStack(spacing: 0) {
            Button {
                guard canExpand else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectionTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(config.selectedDays.isEmpty ? PanelTheme.accent : .white)
                    Text("•").foregroundStyle(PanelTheme.textMuted)
                    Text(PolishPlural.files(config.filteredFiles.count))
                        .font(.system(size: 11))
                        .foregroundStyle(PanelTheme.textSecondary)
                    Spacer()
                    Text(AppModel.formatBytes(config.totalSelectedBytes))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    if canExpand {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PanelTheme.textSecondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(canExpand ? "Pokaż / ukryj listę dni nagrań" : "")

            if isExpanded && canExpand {
                VStack(spacing: 2) {
                    ForEach(config.availableDays) { day in
                        dayRow(day)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
                .disabled(isLocked)
                .transition(.opacity)
            }
        }
        .background(PanelTheme.cardInner)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(PanelTheme.border, lineWidth: 1))
    }

    private func dayRow(_ day: DaySummary) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { config.selectedDays.contains(day.dayString) },
                set: { _ in config.toggleDay(day.dayString) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .controlSize(.small)

            Text(day.dayString)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
            if day.displayText != day.dayString && !day.displayText.contains(".") {
                Text(day.displayText)
                    .font(.system(size: 10))
                    .foregroundStyle(PanelTheme.textSecondary)
            }
            Spacer()
            Text(PolishPlural.files(day.fileCount))
                .font(.system(size: 10))
                .foregroundStyle(PanelTheme.textSecondary)
            Text(AppModel.formatBytes(day.totalBytes))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    // MARK: – Stany specjalne

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(value: config.progress)
                .tint(PanelTheme.accent)
            HStack {
                Text(config.currentFile.isEmpty ? "Zgrywanie…" : config.currentFile)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(PanelTheme.textSecondary)
                Spacer()
                Text("\(Int(config.progress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.accent)
            }
            .font(.system(size: 10))
        }
        .padding(10)
        .background(PanelTheme.cardInner)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var scanningRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Skanowanie karty…")
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.textSecondary)
        }
    }

    private var emptyRow: some View {
        HStack {
            Text("Brak pasujących plików na karcie.")
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.textSecondary)
            Spacer()
            Button("Skanuj ponownie", action: onRescan)
                .controlSize(.small)
                .disabled(isLocked)
        }
    }

    private func failuresRow(_ report: CopyReport) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PanelTheme.danger)
            Text("Nie zgrano: \(PolishPlural.files(report.totalFailed))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PanelTheme.danger)
            Spacer()
        }
        .font(.system(size: 11))
        .help(report.failed.map { "\($0.url.lastPathComponent): \($0.error)" }.joined(separator: "\n"))
    }
}
