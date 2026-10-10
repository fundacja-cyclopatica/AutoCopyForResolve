import Foundation

/// Obsługiwany format pliku: rozszerzenie (bez kropki, małe litery) i nazwa do wyświetlenia.
public struct MediaFormat: Hashable {
    public let ext: String
    public let label: String

    public init(_ ext: String, _ label: String) {
        self.ext = ext
        self.label = label
    }
}

/// Grupa formatów jednej kategorii, w kolejności wyświetlania w ustawieniach.
public struct MediaFormatGroup {
    public let category: MediaCategory
    public let title: String
    public let formats: [MediaFormat]
}

/// Jedyne źródło prawdy o obsługiwanych rozszerzeniach — z niego korzystają skaner,
/// domyślne ustawienia i listy w oknach ustawień.
public enum MediaFormats {
    public static let groups: [MediaFormatGroup] = [
        MediaFormatGroup(category: .video, title: "Wideo", formats: [
            MediaFormat("mov", "MOV"), MediaFormat("mp4", "MP4"), MediaFormat("mxf", "MXF"),
            MediaFormat("braw", "Blackmagic RAW (BRAW)"), MediaFormat("r3d", "RED R3D"),
            MediaFormat("m4v", "M4V"), MediaFormat("avi", "AVI"), MediaFormat("mkv", "MKV"),
            MediaFormat("mpg", "MPG"), MediaFormat("mpeg", "MPEG"),
            MediaFormat("mts", "MTS/AVCHD"), MediaFormat("m2ts", "M2TS"),
            MediaFormat("crm", "Canon RAW (CRM)"), MediaFormat("lrf", "DJI Low-Res (LRF)")
        ]),
        MediaFormatGroup(category: .photo, title: "Zdjęcia i RAW", formats: [
            MediaFormat("arw", "Sony RAW (ARW)"), MediaFormat("srf", "Sony SRF"), MediaFormat("sr2", "Sony SR2"),
            MediaFormat("cr2", "Canon CR2"), MediaFormat("cr3", "Canon CR3"), MediaFormat("crw", "Canon CRW"),
            MediaFormat("nef", "Nikon NEF"), MediaFormat("nrw", "Nikon NRW"),
            MediaFormat("raf", "Fujifilm RAW (RAF)"), MediaFormat("rw2", "Panasonic RW2"),
            MediaFormat("orf", "Olympus ORF"), MediaFormat("ori", "Olympus ORI"),
            MediaFormat("pef", "Pentax PEF"), MediaFormat("rwl", "Leica RWL"),
            MediaFormat("3fr", "Hasselblad 3FR"), MediaFormat("fff", "Hasselblad FFF"),
            MediaFormat("iiq", "Phase One IIQ"),
            MediaFormat("dng", "Adobe DNG / Dron RAW"), MediaFormat("gpr", "GoPro RAW (GPR)"),
            MediaFormat("jpg", "JPG"), MediaFormat("jpeg", "JPEG"), MediaFormat("png", "PNG"),
            MediaFormat("heic", "HEIC"), MediaFormat("heif", "HEIF"),
            MediaFormat("tiff", "TIFF"), MediaFormat("tif", "TIF"), MediaFormat("raw", "Inne RAW")
        ]),
        MediaFormatGroup(category: .audio, title: "Dźwięk", formats: [
            MediaFormat("wav", "WAV"), MediaFormat("mp3", "MP3"), MediaFormat("aac", "AAC"),
            MediaFormat("aiff", "AIFF"), MediaFormat("aif", "AIF"), MediaFormat("m4a", "M4A"),
            MediaFormat("flac", "FLAC")
        ])
    ]

    /// Formaty domyślnie wyłączone. DJI `.LRF` to podglądy niskiej jakości — zgrywane obok
    /// oryginałów podwajałyby liczbę klipów w projekcie.
    public static let disabledByDefault: Set<String> = ["lrf"]

    /// Wszystkie obsługiwane rozszerzenia.
    public static let allExtensions: Set<String> = Set(groups.flatMap { $0.formats.map(\.ext) })

    /// Rozszerzenia włączone w nowych ustawieniach.
    public static let defaultExtensions: Set<String> = allExtensions.subtracting(disabledByDefault)

    /// Rozszerzenia danej kategorii.
    public static func extensions(for category: MediaCategory) -> Set<String> {
        extensionsByCategory[category] ?? []
    }

    /// Wyliczane raz — skaner sprawdza kategorię każdego pliku na karcie.
    private static let extensionsByCategory: [MediaCategory: Set<String>] = Dictionary(
        grouping: groups, by: \.category
    ).mapValues { Set($0.flatMap { $0.formats.map(\.ext) }) }
}
