import SwiftUI
import SDCardOrganizerCore

/// Komponent prezentujący pojedynczą kartę SD w układzie kolumnowym (macOS Studio Dark Glass).
struct CardColumnView: View {
    @Binding var config: CardIngestConfig
    let cardIndex: Int
    let cameraPresets: [String]
    let onRescan: () -> Void
    let onEject: () -> Void
    let onPromptRename: () -> Void
    let onOpenSettings: () -> Void

    private var themeColor: Color {
        StudioTheme.slotColor(for: cardIndex)
    }

    private var slotTag: String {
        StudioTheme.slotTag(for: cardIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Specular rim light na górze karty
            LinearGradient(
                colors: [.clear, themeColor.opacity(config.isEnabled ? 0.35 : 0.08), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, -14)

            // Nagłówek karty (ikona z diodą LED, nazwa, wysunięcie, włącznik)
            cardHeader

            // Pasek podziału danych (Wideo / Foto / Wolne)
            storageBreakdownBar

            Divider().overlay(Color.white.opacity(0.07))

            // Podpis kamery / kąt ze slotem technicznym i chmurkami
            cameraLabelSection

            // Filtry typów materiałów (Filmy / Zdjęcia)
            mediaTypeSection

            // Zakres nagrań (przełącznik Najnowszy/Wszystkie i lista dni)
            daysSelectionSection

            Spacer(minLength: 2)

            // Pasek postępu kopiowania na żywo (jeśli aktywne)
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
                .fill(StudioTheme.cardBg)
                .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    config.isEnabled ? themeColor.opacity(0.35) : Color.white.opacity(0.08),
                    lineWidth: config.isEnabled ? 1.5 : 1
                )
        )
        .opacity(config.isEnabled ? 1.0 : 0.6)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: config.isEnabled)
    }

    // MARK: – Nagłówek

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            // Ikona nośnika z aktywną diodą LED
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(themeColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(themeColor.opacity(0.35), lineWidth: 1)
                    )

                Image(systemName: "sdcard.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(themeColor)
                    .frame(width: 34, height: 34)

                // Dioda LED
                if config.isEnabled {
                    Circle()
                        .fill(themeColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: themeColor, radius: 4)
                        .offset(x: 2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(config.volumeName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Button {
                        onPromptRename()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Zmień nazwę karty w systemie")

                    if config.isScanning {
                        ProgressView().controlSize(.mini)
                    }
                }

                if let total = config.totalCapacity, let avail = config.availableCapacity {
                    Text("\(AppModel.formatBytes(Int64(avail))) wolne / \(AppModel.formatBytes(Int64(total)))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.gray.opacity(0.85))
                }
            }

            Spacer()

            // Przycisk bezpiecznego wysunięcia karty
            Button {
                onEject()
            } label: {
                Image(systemName: "eject.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gray.opacity(0.8))
            }
            .buttonStyle(.plain)
            .padding(4)
            .background(Color.white.opacity(0.04))
            .cornerRadius(5)
            .help("Wysuń bezpiecznie kartę z czytnika")

            // Przełącznik włączenia do sesji zgrywania
            Toggle("", isOn: $config.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(themeColor)
                .help(config.isEnabled ? "Karta włączona do zgrywania" : "Karta pomijana")
        }
    }

    // MARK: – Pasek podziału pamięci

    private var storageBreakdownBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                let vW = max(2, width * CGFloat(config.videoPercent))
                let pW = max(2, width * CGFloat(config.photoPercent))
                let freeW = max(0, width - vW - pW)

                HStack(spacing: 1) {
                    Rectangle()
                        .fill(themeColor)
                        .frame(width: vW)
                    Rectangle()
                        .fill(StudioTheme.accentAmber)
                        .frame(width: pW)
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: freeW)
                }
                .cornerRadius(3)
            }
            .frame(height: 5)

            HStack {
                Text("■ Wideo (\(AppModel.formatBytes(config.videoBytes)))")
                    .foregroundStyle(themeColor)
                Spacer()
                Text("■ Foto (\(AppModel.formatBytes(config.photoBytes)))")
                    .foregroundStyle(StudioTheme.accentAmber)
                Spacer()
                Text("Wolne \(config.freePercent)%")
                    .foregroundStyle(Color.gray.opacity(0.8))
            }
            .font(.system(size: 9, design: .monospaced))
        }
        .padding(.vertical, 2)
    }

    // MARK: – Podpis kamery / kąt

    private var cameraLabelSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Podpis kamery / kąt:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.gray)
                Spacer()
                Text(slotTag)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(themeColor.opacity(0.85))
            }

            TextField("np. Kamera A, Dron, Detal", text: $config.cameraLabel)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.55))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            // Szybkie presety podpisów ("chmurki")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(cameraPresets, id: \.self) { preset in
                        let isSelected = config.cameraLabel == preset
                        Button {
                            config.cameraLabel = preset
                        } label: {
                            Text(preset)
                                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(isSelected ? themeColor.opacity(0.22) : Color.white.opacity(0.04))
                                .foregroundStyle(isSelected ? themeColor : Color.gray.opacity(0.9))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isSelected ? themeColor.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.04))
                            .foregroundStyle(Color.gray)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Zarządzaj presetami kamer w ustawieniach")
                }
            }
        }
    }

    // MARK: – Typy materiałów

    private var mediaTypeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Typy materiałów:")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.gray)

            HStack(spacing: 12) {
                Toggle(isOn: $config.includeVideos) {
                    Text("Filmy (\(config.totalVideoCount))")
                        .font(.system(size: 11))
                        .foregroundStyle(config.totalVideoCount > 0 ? Color.gray.opacity(0.9) : Color.gray.opacity(0.5))
                }
                .toggleStyle(.checkbox)
                .tint(themeColor)
                .disabled(config.totalVideoCount == 0)

                Toggle(isOn: $config.includePhotos) {
                    Text("Zdjęcia (\(config.totalPhotoCount))")
                        .font(.system(size: 11))
                        .foregroundStyle(config.totalPhotoCount > 0 ? Color.gray.opacity(0.9) : Color.gray.opacity(0.5))
                }
                .toggleStyle(.checkbox)
                .tint(StudioTheme.accentAmber)
                .disabled(config.totalPhotoCount == 0)
            }
        }
        .padding(.top, 2)
    }

    // MARK: – Zakres nagrań (Daty)

    private var daysSelectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Zakres nagrań:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.gray)
                Spacer()
                Button {
                    onRescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)
                }
                .buttonStyle(.plain)
                .help("Przeskanuj ponownie tę kartę")
            }

            if config.isScanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Skanowanie…")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)
                }
                .padding(.vertical, 4)
            } else if config.scannedFiles.isEmpty {
                Text("Brak pasujących plików.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.gray.opacity(0.7))
                    .padding(.vertical, 2)
            } else {
                // Przełącznik: Najnowszy / Wszystkie
                if config.availableDays.count > 1 {
                    HStack(spacing: 0) {
                        let isSingle = config.selectedDays.count == 1 && config.selectedDays.contains(config.availableDays.first?.dayString ?? "")
                        Button {
                            config.selectLatestDay()
                        } label: {
                            Text("Najnowszy")
                                .font(.system(size: 10, weight: isSingle ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 3)
                                .background(isSingle ? Color.white.opacity(0.12) : Color.clear)
                                .foregroundStyle(isSingle ? Color.white : Color.gray)
                        }
                        .buttonStyle(.plain)

                        Button {
                            config.selectAllDays()
                        } label: {
                            Text("Wszystkie (\(config.availableDays.count))")
                                .font(.system(size: 10, weight: !isSingle ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 3)
                                .background(!isSingle ? Color.white.opacity(0.12) : Color.clear)
                                .foregroundStyle(!isSingle ? Color.white : Color.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }

                // Lista dni z checkboxami
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(config.availableDays) { day in
                            let isDaySelected = config.selectedDays.contains(day.dayString)

                            HStack(alignment: .top, spacing: 6) {
                                Toggle("", isOn: Binding(
                                    get: { config.selectedDays.contains(day.dayString) },
                                    set: { _ in config.toggleDay(day.dayString) }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .controlSize(.mini)
                                .tint(themeColor)
                                .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(day.dayString)
                                        .font(.system(size: 11, weight: isDaySelected ? .bold : .medium))
                                        .foregroundStyle(isDaySelected ? Color.white : Color.gray.opacity(0.8))

                                    Text("\(day.videoCount) wideo, \(day.photoCount) zdjęć • \(AppModel.formatBytes(day.totalBytes))")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(isDaySelected ? Color.gray.opacity(0.9) : Color.gray.opacity(0.5))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isDaySelected ? themeColor.opacity(0.10) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isDaySelected ? themeColor.opacity(0.28) : Color.clear, lineWidth: 1)
                            )
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
        }
        .padding(.top, 2)
    }

    // MARK: – Postęp kopiowania

    private var copyProgressSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: config.progress)
                .tint(themeColor)
            HStack {
                Text(config.currentFile.isEmpty ? "Zgrywanie…" : config.currentFile)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.gray)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(config.progress * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(themeColor)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.4))
        .cornerRadius(6)
    }

    // MARK: – Stopka kolumny

    private var cardFooter: some View {
        HStack {
            let videos = config.filteredFiles.filter { $0.category == .video }.count
            let photos = config.filteredFiles.filter { $0.category == .photo }.count

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "film")
                        .font(.system(size: 10))
                        .foregroundStyle(themeColor)
                    Text("\(videos)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.gray.opacity(0.9))
                }

                HStack(spacing: 3) {
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                        .foregroundStyle(StudioTheme.accentAmber)
                    Text("\(photos)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.gray.opacity(0.9))
                }
            }

            Spacer()

            Text(AppModel.formatBytes(config.totalSelectedBytes))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .padding(.top, 4)
        .overlay(alignment: .top) {
            Divider().overlay(Color.white.opacity(0.07))
        }
    }
}
