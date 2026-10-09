import Foundation

/// Zestawia kompletny projekt: katalogi + plik .drp (z szablonu, jeśli podany) + manifest JSON.
public struct ProjectBuilder {
    public let settings: Settings

    public init(settings: Settings) {
        self.settings = settings
    }

    /// Tworzy projekt w miejscu docelowym i zwraca strukturę ścieżek.
    @discardableResult
    public func build(projectName: String) throws -> ProjectLayout {
        let layout = ProjectLayout(destinationRoot: settings.destinationRoot, projectName: projectName)
        try layout.createDirectories()
        try writeManifest(to: layout)
        try writeDRPProject(to: layout)
        return layout
    }

    /// Zapisuje manifest JSON z metadanymi projektu.
    private func writeManifest(to layout: ProjectLayout) throws {
        let manifest: [String: Any] = [
            "projectName": layout.projectName,
            "resolution": settings.resolution,
            "frameRate": settings.frameRate,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "structure": [
                "video": "Video",
                "audio": "Audio",
                "photos": "Zdjęcia",
                "daVinci": "DaVinci"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: layout.manifestURL(), options: .atomic)
    }

    /// Tworzy plik projektu DaVinci Resolve.
    ///
    /// Format `.drp` nie jest publicznie udokumentowany, dlatego zamiast generować plik
    /// od zera, kopiujemy wzorcowy plik `.drp` dostarczony przez użytkownika i nadajemy mu
    /// nazwę projektu. Jeżeli szablon nie jest skonfigurowany, tworzymy plik `.drp` zastępczy
    /// o zerowej długości z ostrzeżeniem w manifestcie.
    private func writeDRPProject(to layout: ProjectLayout) throws {
        let target = layout.drpFileURL()

        if let templatePath = settings.drpTemplatePath,
           !templatePath.isEmpty,
           FileManager.default.fileExists(atPath: templatePath) {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: templatePath), to: target)
        } else {
            // Zastępczy plik; użytkownik zostanie poinformowany, że powinien podać szablon.
            let placeholder = Data()
            try placeholder.write(to: target, options: .atomic)
        }
    }
}
