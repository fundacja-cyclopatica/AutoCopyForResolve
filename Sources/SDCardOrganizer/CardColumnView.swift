import SwiftUI
import SDCardOrganizerCore

/// Komponent prezentujący pojedynczą kartę SD w układzie kolumnowym (Apple Design style).
struct CardColumnView: View {
    @Binding var config: CardIngestConfig
    let cardIndex: Int
    let cameraPresets: [String]
    let onRescan: () -> Void
    let onEject: () -> Void
    let onPromptRename: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Nagłówek karty (ikona, nazwa, wysunięcie, status włączenia)
            cardHeader

            Divider()

            // Podpis kamery / zastosowania
            cameraLabelSection

            Divider()

            // Wybór typów mediów (Filmy / Zdjęcia / Audio)
            mediaTypeSelectionSection

            Divider()

            // Wybór dni i zawartość
            daysSelectionSection

            Spacer(minLength: 0)

            // Pasek postępu kopiowania (jeśli aktywne)
            if config.isCopying {
                copyProgressSection
            }

            // Podsumowanie selekcji na dole kolumny
            cardFooter
        }
        .padding(14)
        .frame(minWidth: 260, maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(config.isEnabled ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: config.isEnabled ? 1.5 : 1)
        )
        .opacity(config.isEnabled ? 1.0 : 0.6)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: config.isEnabled)
    }

    // MARK: – Nagłówek

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(config.isEnabled ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "sdcard.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(config.isEnabled ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(config.volumeName)
                        .font(.headline)
                        .lineLimit(1)

                    Button {
                        onPromptRename()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Zmień nazwę karty w systemie")

                    if config.isScanning {
                        ProgressView().controlSize(.mini)
                    }
                }

                if let total = config.totalCapacity, let avail = config.availableCapacity {
                    Text("\(AppModel.formatBytes(Int64(avail))) wolne / \(AppModel.formatBytes(Int64(total)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Przycisk bezpiecznego wysunięcia karty
            Button {
                onEject()
            } label: {
                Image(systemName: "eject.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Wysuń bezpiecznie kartę z czytnika")

            // Przełącznik włączenia do sesji zgrywania
            Toggle("", isOn: $config.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(config.isEnabled ? "Karta włączona do zgrywania" : "Karta pomijana")
        }
    }

    // MARK: – Podpis kamery / zastosowania

    private var cameraLabelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Podpis kamery / kąt:", systemImage: "video.badge.waveform")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            TextField("np. Kamera A, Dron, Detal", text: $config.cameraLabel)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            // Szybkie presety podpisów ("chmurki")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(cameraPresets, id: \.self) { preset in
                        Button {
                            config.cameraLabel = preset
                        } label: {
                            Text(preset)
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(config.cameraLabel == preset ? .accentColor : nil)
                    }

                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Zarządzaj i edytuj presety kamer w ustawieniach")
                }
            }
        }
    }

    // MARK: – Wybór typów mediów (Filmy / Zdjęcia / Audio)

    private var mediaTypeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Typy materiałów:", systemImage: "checklist")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            let totalVideos = config.scannedFiles.filter { $0.category == .video }.count
            let totalPhotos = config.scannedFiles.filter { $0.category == .photo }.count
            let totalAudio = config.scannedFiles.filter { $0.category == .audio }.count

            HStack(spacing: 10) {
                Toggle(isOn: $config.includeVideos) {
                    HStack(spacing: 3) {
                        Image(systemName: "film")
                            .foregroundStyle(.blue)
                        Text("Filmy (\(totalVideos))")
                            .font(.caption2.bold())
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(totalVideos == 0)

                Toggle(isOn: $config.includePhotos) {
                    HStack(spacing: 3) {
                        Image(systemName: "photo")
                            .foregroundStyle(.orange)
                        Text("Zdjęcia (\(totalPhotos))")
                            .font(.caption2.bold())
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(totalPhotos == 0)

                if totalAudio > 0 {
                    Toggle(isOn: $config.includeAudio) {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform")
                                .foregroundStyle(.green)
                            Text("Audio (\(totalAudio))")
                                .font(.caption2.bold())
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    // MARK: – Wybór dni nagrań

    private var daysSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Zakres nagrań:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onRescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Przeskanuj ponownie tę kartę")
            }

            if config.isScanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Skanowanie zawartości…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if config.scannedFiles.isEmpty {
                Text("Brak pasujących plików wideo/zdjęć.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                // Szybkie przyciski wyboru dni
                if config.availableDays.count > 1 {
                    HStack(spacing: 4) {
                        if let latest = config.availableDays.first {
                            Button {
                                config.selectLatestDay()
                            } label: {
                                Text("Najnowszy")
                            }
                            .buttonStyle(.bordered)
                            .tint(config.selectedDays == [latest.dayString] ? .accentColor : nil)
                            .controlSize(.mini)
                        }

                        Button {
                            config.selectAllDays()
                        } label: {
                            Text("Wszystkie (\(config.availableDays.count))")
                        }
                        .buttonStyle(.bordered)
                        .tint(config.selectedDays.count == config.availableDays.count ? .accentColor : nil)
                        .controlSize(.mini)
                    }
                }

                // Lista dni z checkboxami
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(config.availableDays) { day in
                            Toggle(isOn: Binding(
                                get: { config.selectedDays.contains(day.dayString) },
                                set: { _ in config.toggleDay(day.dayString) }
                            )) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(day.dayString)
                                        .font(.caption.bold())
                                    Text("\(day.videoCount) wideo, \(day.photoCount) zdjęć • \(AppModel.formatBytes(day.totalBytes))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }

    // MARK: – Postęp kopiowania

    private var copyProgressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: config.progress)
            HStack {
                Text(config.currentFile.isEmpty ? "Kopiowanie…" : config.currentFile)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(config.progress * 100))%")
                    .font(.caption2.monospacedDigit())
            }
        }
        .padding(8)
        .background(Color(NSColor.quaternaryLabelColor).opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: – Stopka kolumny

    private var cardFooter: some View {
        HStack {
            let videos = config.filteredFiles.filter { $0.category == .video }.count
            let photos = config.filteredFiles.filter { $0.category == .photo }.count

            HStack(spacing: 8) {
                Label("\(videos)", systemImage: "film")
                Label("\(photos)", systemImage: "photo")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Spacer()

            Text(AppModel.formatBytes(config.totalSelectedBytes))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(config.filteredFiles.isEmpty ? .secondary : Color.primary)
        }
        .padding(.top, 4)
    }
}
