import Foundation

/// Wygląd ikony aplikacji w pasku menu.
public enum MenuBarIconStyle: String, Codable, CaseIterable {
    /// Kolor dopasowany do paska menu (biała na ciemnym, czarna na jasnym) — ikona szablonowa.
    case automatic
    /// Zawsze biała.
    case white
    /// Zawsze czarna.
    case black
    /// Musztardowa, gdy są podłączone karty; w przeciwnym razie automatyczna.
    case accent
    /// Własny plik graficzny wgrany w ustawieniach.
    case custom
}

/// Trwałe ustawienia aplikacji, zapisywane jako JSON w Application Support.
public struct Settings: Codable, Equatable {
    /// Domyślna lista rozszerzeń (wszystkie obsługiwane poza podglądami DJI `.LRF`).
    public static let defaultExtensions: Set<String> = MediaFormats.defaultExtensions

    /// Domyślne presety podpisów kamer
    public static let defaultCameraPresets: [String] = [
        "Kamera A", "Kamera B", "Kamera C", "Dron", "GoPro", "Audio"
    ]

    /// Ścieżka do dysku/folderu docelowego, na który zgrywane są materiały.
    public var destinationRoot: String

    /// Wybrane rozszerzenia plików (bez kropki, małymi literami).
    public var enabledExtensions: Set<String>

    /// Konfigurowalna lista presetów podpisów kamer ("chmurek")
    public var cameraPresets: [String]

    /// Opcje automatycznego otwierania aplikacji po zgraniu
    public var openInDaVinciResolve: Bool
    public var openInLightroom: Bool

    /// Rozdzielczość projektu DaVinci Resolve, np. "1920x1080".
    public var resolution: String

    /// Liczba klatek na sekundę projektu DaVinci Resolve.
    public var frameRate: Double

    /// Czy przy wykrywaniu duplikatów porównywać checksum plików (wolniejsze, ale pewniejsze).
    public var verifyChecksums: Bool

    /// Czy po skopiowaniu weryfikować każdą kopię sumą kontrolną SHA-256 (porównanie z kartą).
    public var verifyCopies: Bool

    /// Ścieżka do wzorcowego pliku .drp używanego jako szablon projektu.
    public var drpTemplatePath: String?

    /// Druga kopia zapasowa: folder, do którego materiał trafia równocześnie z dyskiem
    /// docelowym (ta sama struktura projektu). Pusty — kopia zapasowa wyłączona.
    public var backupDestinationRoot: String

    /// Automatycznie wysuń karty po zgraniu bez błędów (i bez anulowania).
    public var ejectCardsAfterIngest: Bool

    /// Zgrywaj pliki towarzyszące (Sony XML, DJI SRT, XMP) razem z materiałem.
    public var copySidecarFiles: Bool

    /// Zapisuj w folderze projektu raport zgrania z listą plików i sumami SHA-256.
    public var writeIngestReport: Bool

    /// Wygląd ikony w pasku menu.
    public var menuBarIconStyle: MenuBarIconStyle

    /// Ścieżka własnej ikony (kopia w Application Support), używana przy stylu `.custom`.
    public var customMenuBarIconPath: String?

    /// Czy własną ikonę traktować jako szablon (kolor dopasowany do paska menu).
    public var customMenuBarIconIsTemplate: Bool

    public init(
        destinationRoot: String = "",
        enabledExtensions: Set<String> = Settings.defaultExtensions,
        cameraPresets: [String] = Settings.defaultCameraPresets,
        openInDaVinciResolve: Bool = false,
        openInLightroom: Bool = false,
        resolution: String = "1920x1080",
        frameRate: Double = 25,
        verifyChecksums: Bool = false,
        verifyCopies: Bool = true,
        drpTemplatePath: String? = nil,
        backupDestinationRoot: String = "",
        ejectCardsAfterIngest: Bool = false,
        copySidecarFiles: Bool = true,
        writeIngestReport: Bool = true,
        menuBarIconStyle: MenuBarIconStyle = .automatic,
        customMenuBarIconPath: String? = nil,
        customMenuBarIconIsTemplate: Bool = true
    ) {
        self.destinationRoot = destinationRoot
        self.enabledExtensions = enabledExtensions
        self.cameraPresets = cameraPresets
        self.openInDaVinciResolve = openInDaVinciResolve
        self.openInLightroom = openInLightroom
        self.resolution = resolution
        self.frameRate = frameRate
        self.verifyChecksums = verifyChecksums
        self.verifyCopies = verifyCopies
        self.drpTemplatePath = drpTemplatePath
        self.backupDestinationRoot = backupDestinationRoot
        self.ejectCardsAfterIngest = ejectCardsAfterIngest
        self.copySidecarFiles = copySidecarFiles
        self.writeIngestReport = writeIngestReport
        self.menuBarIconStyle = menuBarIconStyle
        self.customMenuBarIconPath = customMenuBarIconPath
        self.customMenuBarIconIsTemplate = customMenuBarIconIsTemplate
    }

    private enum CodingKeys: String, CodingKey {
        case destinationRoot, enabledExtensions, cameraPresets, openInDaVinciResolve, openInLightroom,
             resolution, frameRate, verifyChecksums, verifyCopies, drpTemplatePath,
             backupDestinationRoot, ejectCardsAfterIngest, copySidecarFiles, writeIngestReport,
             menuBarIconStyle, customMenuBarIconPath, customMenuBarIconIsTemplate
    }

    /// Dekodowanie odporne na zmiany formatu: brakujące lub nieprawidłowe pola przyjmują
    /// wartości domyślne, dzięki czemu plik ustawień ze starszej wersji aplikacji nie jest
    /// odrzucany w całości po dodaniu nowego pola.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            try? container.decodeIfPresent(type, forKey: key)
        }

        let defaults = Settings()
        self.destinationRoot = value(String.self, .destinationRoot) ?? defaults.destinationRoot
        self.enabledExtensions = value(Set<String>.self, .enabledExtensions) ?? defaults.enabledExtensions
        self.cameraPresets = value([String].self, .cameraPresets) ?? defaults.cameraPresets
        self.openInDaVinciResolve = value(Bool.self, .openInDaVinciResolve) ?? defaults.openInDaVinciResolve
        self.openInLightroom = value(Bool.self, .openInLightroom) ?? defaults.openInLightroom
        self.resolution = value(String.self, .resolution) ?? defaults.resolution
        self.frameRate = value(Double.self, .frameRate) ?? defaults.frameRate
        self.verifyChecksums = value(Bool.self, .verifyChecksums) ?? defaults.verifyChecksums
        self.verifyCopies = value(Bool.self, .verifyCopies) ?? defaults.verifyCopies
        self.drpTemplatePath = value(String.self, .drpTemplatePath) ?? defaults.drpTemplatePath
        self.backupDestinationRoot = value(String.self, .backupDestinationRoot) ?? defaults.backupDestinationRoot
        self.ejectCardsAfterIngest = value(Bool.self, .ejectCardsAfterIngest) ?? defaults.ejectCardsAfterIngest
        self.copySidecarFiles = value(Bool.self, .copySidecarFiles) ?? defaults.copySidecarFiles
        self.writeIngestReport = value(Bool.self, .writeIngestReport) ?? defaults.writeIngestReport
        self.menuBarIconStyle = value(MenuBarIconStyle.self, .menuBarIconStyle) ?? defaults.menuBarIconStyle
        self.customMenuBarIconPath = value(String.self, .customMenuBarIconPath) ?? defaults.customMenuBarIconPath
        self.customMenuBarIconIsTemplate = value(Bool.self, .customMenuBarIconIsTemplate)
            ?? defaults.customMenuBarIconIsTemplate
    }

    /// Domyślna ścieżka pliku ustawień w katalogu Application Support użytkownika.
    public static func defaultSettingsURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SDCardOrganizer", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}

/// Ładowanie i zapisywanie ustawień na dysku.
public struct SettingsStore {
    public static func load(from url: URL = Settings.defaultSettingsURL()) throws -> Settings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Settings()
        }
        let data = try Data(contentsOf: url)
        var settings: Settings
        do {
            settings = try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            // Plik jest nieczytelny (np. uszkodzony). Zachowaj jego kopię, zanim aplikacja
            // zapisze w tym miejscu ustawienia domyślne.
            backUpUnreadableFile(at: url)
            settings = Settings()
        }
        if settings.cameraPresets.isEmpty {
            settings.cameraPresets = Settings.defaultCameraPresets
        }
        return settings
    }

    /// Kopiuje nieczytelny plik ustawień obok oryginału jako `settings.unreadable-<data>.json`.
    static func backUpUnreadableFile(at url: URL) {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        let name = "\(url.deletingPathExtension().lastPathComponent).unreadable-\(df.string(from: Date())).json"
        let backup = url.deletingLastPathComponent().appendingPathComponent(name)
        try? FileManager.default.copyItem(at: url, to: backup)
    }

    public static func save(_ settings: Settings, to url: URL = Settings.defaultSettingsURL()) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
    }
}
