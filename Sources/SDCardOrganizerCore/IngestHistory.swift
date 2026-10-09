import Foundation

/// Wpis w historii zgrywań — trwale zapisywany na dysku.
public struct IngestRecord: Codable, Identifiable, Equatable {
    public let id: String
    public let date: Date
    public let projectName: String
    public let sourceVolumeName: String
    public let destinationPath: String
    public let filesCopied: Int
    public let filesSkipped: Int
    public let filesFailed: Int
    public let totalBytes: Int64

    public init(
        date: Date = Date(),
        projectName: String,
        sourceVolumeName: String,
        destinationPath: String,
        filesCopied: Int,
        filesSkipped: Int,
        filesFailed: Int,
        totalBytes: Int64
    ) {
        self.id = UUID().uuidString
        self.date = date
        self.projectName = projectName
        self.sourceVolumeName = sourceVolumeName
        self.destinationPath = destinationPath
        self.filesCopied = filesCopied
        self.filesSkipped = filesSkipped
        self.filesFailed = filesFailed
        self.totalBytes = totalBytes
    }
}

/// Trwała historia zgrywań, zapisywana jako JSON w Application Support.
public struct IngestHistory {
    public static func defaultHistoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SDCardOrganizer", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    public static func load(from url: URL = defaultHistoryURL()) -> [IngestRecord] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([IngestRecord].self, from: data)) ?? []
    }

    public static func append(_ record: IngestRecord, to url: URL = defaultHistoryURL()) {
        var records = load(from: url)
        records.insert(record, at: 0)
        // Zachowaj ostatnie 100 wpisów.
        if records.count > 100 { records = Array(records.prefix(100)) }
        save(records, to: url)
    }

    public static func save(_ records: [IngestRecord], to url: URL = defaultHistoryURL()) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func clear(at url: URL = defaultHistoryURL()) {
        save([], to: url)
    }
}
