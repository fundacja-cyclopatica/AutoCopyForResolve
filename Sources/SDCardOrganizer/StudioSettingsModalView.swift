import SwiftUI
import UniformTypeIdentifiers
import SDCardOrganizerCore

/// Pływające studio okno ustawień (Floating Studio Settings Panel).
/// Zawiera wszystkie ustawienia aplikacji w jednym, scrollowanym panelu.
struct StudioSettingsModalView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Specular border
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.3), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            // Pasek tytułowy okna ustawień
            HStack(spacing: 8) {
                Button {
                    onClose()
                } label: {
                    Circle()
                        .fill(Color(red: 255/255, green: 95/255, blue: 86/255))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color(red: 224/255, green: 68/255, blue: 62/255).opacity(0.6), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gray)
                    Text("SD Card Organizer Settings")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.gray.opacity(0.9))
                }

                Spacer()

                // Pusta przestrzeń dla symetrii (usunięty przycisk rozwijania do drugiego okna)
                Color.clear.frame(width: 20, height: 20)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))

            Divider().overlay(Color.white.opacity(0.08))

            // Zawartość ustawień (wszystkie sekcje w jednym scrollowanym panelu)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    destinationSection
                    autoLaunchSection
                    cameraPresetsSection
                    fileTypesSection
                    daVinciProjectSection
                    advancedSection
                }
                .padding(14)
            }
        }
        .frame(width: 430)
        .frame(maxHeight: 620)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 22/255, green: 26/255, blue: 36/255).opacity(0.98))
                .shadow(color: Color.black.opacity(0.9), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: – Nagłówek sekcji

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Color.gray.opacity(0.8))
    }

    // MARK: – Sekcja: Dysk docelowy

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Dysk docelowy")

            HStack(spacing: 6) {
                TextField("Ścieżka folderu docelowego", text: $model.settings.destinationRoot)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))

                Button {
                    chooseDestination()
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.10))
                        .foregroundStyle(Color.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Wybierz dysk/folder docelowy")
            }

            Text("Materiały będą zgrywane do podfolderu <data>_<nazwa projektu> na tym dysku.")
                .font(.system(size: 9))
                .foregroundStyle(Color.gray.opacity(0.7))
                .lineSpacing(2)
        }
    }

    // MARK: – Sekcja: Automatyczne otwieranie aplikacji po zgraniu

    private var autoLaunchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Automatyczne otwieranie aplikacji po zgraniu")

            // DaVinci Resolve Toggle
            HStack {
                HStack(spacing: 8) {
                    Text("Dv")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .frame(width: 22, height: 22)
                        .background(
                            LinearGradient(
                                colors: [Color.red, Color.orange, Color.blue],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )
                        )
                        .cornerRadius(5)
                        .shadow(radius: 2)

                    Text("Otwórz projekt w DaVinci Resolve")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                }

                Spacer()

                Toggle("", isOn: $model.settings.openInDaVinciResolve)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(Color.orange)
            }
            .padding(8)
            .background(Color.black.opacity(0.35))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))

            // Adobe Lightroom Toggle
            HStack {
                HStack(spacing: 8) {
                    Text("Lr")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 49/255, green: 168/255, blue: 255/255))
                        .frame(width: 22, height: 22)
                        .background(Color(red: 0/255, green: 29/255, blue: 52/255))
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(red: 49/255, green: 168/255, blue: 255/255).opacity(0.5), lineWidth: 1))
                        .shadow(radius: 2)

                    Text("Otwórz folder zdjęć w Adobe Lightroom")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                }

                Spacer()

                Toggle("", isOn: $model.settings.openInLightroom)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(StudioTheme.accentBlue)
            }
            .padding(8)
            .background(Color.black.opacity(0.35))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))

            Text("Możesz również włączyć te opcje jednorazowo bezpośrednio przy przycisku zgrywania na dolnym pasku.")
                .font(.system(size: 9))
                .foregroundStyle(Color.gray.opacity(0.7))
                .lineSpacing(2)
        }
    }

    // MARK: – Sekcja: Presety podpisów kamer

    private var cameraPresetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Presety podpisów kamer („chmurki”)")

            // Dodawanie
            HStack(spacing: 6) {
                TextField("Nowa etykieta (np. Sony FX3)", text: $model.newPresetInputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))

                Button {
                    model.addCameraPreset(model.newPresetInputText)
                    model.newPresetInputText = ""
                } label: {
                    Text("Dodaj")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(Color.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(model.newPresetInputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Lista presetów
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(model.settings.cameraPresets.enumerated()), id: \.offset) { index, preset in
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(StudioTheme.accentCyan)
                                Text(preset)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.9))
                            }

                            Spacer()

                            Button {
                                model.removeCameraPreset(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Usuń preset")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.05), lineWidth: 1))
                    }
                }
            }
            .frame(maxHeight: 90)

            Button("Przywróć domyślne presety") {
                model.settings.cameraPresets = Settings.defaultCameraPresets
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: – Sekcja: Typy plików

    private var fileTypesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Typy plików")

            HStack {
                Button("Zaznacz wszystkie") { selectAll(true) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Odznacz wszystkie") { selectAll(false) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button("Przywróć domyślne") {
                    model.settings.enabledExtensions = Settings.defaultExtensions
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(MediaFormats.groups, id: \.title) { group in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(group.formats, id: \.ext) { item in
                            Toggle(item.label, isOn: binding(for: item.ext))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.top, 4)
                } label: {
                    Text(group.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: – Sekcja: Projekt DaVinci Resolve

    private var daVinciProjectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Projekt DaVinci Resolve")

            VStack(alignment: .leading, spacing: 4) {
                Text("Rozdzielczość")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.gray)
                TextField("np. 1920x1080", text: $model.settings.resolution)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }

            Stepper(value: $model.settings.frameRate, in: 23.976...120, step: 1) {
                Text("Liczba klatek: \(frameRateText) fps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Ścieżka szablonu .drp (opcjonalna)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.gray)
                HStack(spacing: 6) {
                    TextField("Wzorcowy plik .drp", text: drpTemplateBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))

                    Button {
                        chooseTemplate()
                    } label: {
                        Text("Wybierz…")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.10))
                            .foregroundStyle(Color.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Podaj wzorcowy plik .drp wyeksportowany z DaVinci Resolve. Jeśli go nie podasz, utworzymy folder projektu i manifest JSON.")
                .font(.system(size: 9))
                .foregroundStyle(Color.gray.opacity(0.7))
                .lineSpacing(2)
        }
    }

    // MARK: – Sekcja: Zaawansowane

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Zaawansowane")

            Toggle(isOn: $model.settings.verifyCopies) {
                Text("Weryfikuj każdą kopię sumą kontrolną SHA-256 (zalecane)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .toggleStyle(.checkbox)
            .tint(StudioTheme.accentCyan)

            Toggle(isOn: $model.settings.verifyChecksums) {
                Text("Weryfikuj checksum (SHA-256) przy wykrywaniu duplikatów")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .toggleStyle(.checkbox)
            .tint(StudioTheme.accentCyan)
        }
    }

    // MARK: – Pomoc

    private var frameRateText: String {
        String(format: "%.0f", model.settings.frameRate)
    }

    private func binding(for ext: String) -> Binding<Bool> {
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

    private var drpTemplateBinding: Binding<String> {
        Binding(
            get: { model.settings.drpTemplatePath ?? "" },
            set: { model.settings.drpTemplatePath = $0.isEmpty ? nil : $0 }
        )
    }

    private func selectAll(_ select: Bool) {
        model.settings.enabledExtensions = select ? MediaFormats.allExtensions : []
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
