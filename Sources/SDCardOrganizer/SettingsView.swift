import SwiftUI
import UniformTypeIdentifiers

/// Okno ustawień — dysk docelowy, typy plików, parametry projektu DaVinci Resolve.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    // Wszystkie znane rozszerzenia, pogrupowane wg kategorii.
    private static let allExtensions: [(category: String, items: [(ext: String, label: String)])] = [
        ("Wideo", [
            ("mov", "MOV"), ("mp4", "MP4"), ("mxf", "MXF"), ("braw", "BRAW"),
            ("r3d", "RED R3D"), ("m4v", "M4V"), ("avi", "AVI"), ("mkv", "MKV"),
            ("mts", "MTS/AVCHD"), ("m2ts", "M2TS")
        ]),
        ("Dźwięk", [
            ("wav", "WAV"), ("mp3", "MP3"), ("aac", "AAC"), ("aiff", "AIFF"),
            ("aif", "AIF"), ("m4a", "M4A"), ("flac", "FLAC")
        ]),
        ("Zdjęcia i RAW", [
            ("jpg", "JPG"), ("jpeg", "JPEG"), ("png", "PNG"), ("tiff", "TIFF"),
            ("heic", "HEIC"), ("dng", "DNG"), ("cr2", "Canon CR2"), ("cr3", "Canon CR3"),
            ("nef", "Nikon NEF"), ("arw", "Sony ARW"), ("rw2", "Panasonic RW2"),
            ("orf", "Olympus ORF"), ("raw", "RAW")
        ])
    ]

    var body: some View {
        Form {
            Section("Dysk docelowy") {
                HStack {
                    TextField("Ścieżka folderu docelowego", text: $model.settings.destinationRoot)
                        .textFieldStyle(.roundedBorder)
                    Button("Wybierz…") { chooseDestination() }
                }
                Text("Materiały będą zgrywane do podfolderu <data>_<nazwa projektu> na tym dysku.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Typy plików") {
                HStack {
                    Button("Zaznacz wszystkie") { selectAll(true) }
                    Button("Odznacz wszystkie") { selectAll(false) }
                }
                ForEach(Self.allExtensions, id: \.category) { group in
                    DisclosureGroup(group.category) {
                        ForEach(group.items, id: \.ext) { item in
                            Toggle(item.label, isOn: binding(for: item.ext))
                        }
                    }
                }
            }

            Section("Projekt DaVinci Resolve") {
                TextField("Rozdzielczość (np. 1920x1080)", text: $model.settings.resolution)
                Stepper(value: $model.settings.frameRate, in: 23.976...120, step: 1) {
                    Text("Liczba klatek: \(frameRateText) fps")
                }
                TextField("Ścieżka szablonu .drp (opcjonalna)", text: drpTemplateBinding)
                    .textFieldStyle(.roundedBorder)
                Button("Wybierz szablon .drp…") { chooseTemplate() }
                Text("Podaj wzorcowy plik .drp wyeksportowany z DaVinci Resolve. Jeśli go nie podasz, utworzymy folder projektu i manifest JSON.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Zaawansowane") {
                Toggle("Weryfikuj checksum (SHA-256) przy wykrywaniu duplikatów", isOn: $model.settings.verifyChecksums)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

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
        var all = Set<String>()
        for group in Self.allExtensions {
            for item in group.items { all.insert(item.ext) }
        }
        if select {
            model.settings.enabledExtensions.formUnion(all)
        } else {
            model.settings.enabledExtensions.subtract(all)
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
