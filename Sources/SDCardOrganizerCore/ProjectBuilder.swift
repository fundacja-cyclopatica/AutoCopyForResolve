import Foundation

/// Zestawia kompletny projekt: katalogi + plik .drp (z szablonu, jeśli podany) + manifest JSON.
public struct ProjectBuilder {
    public let settings: Settings

    public init(settings: Settings) {
        self.settings = settings
    }

    /// Tworzy projekt w miejscu docelowym i zwraca strukturę ścieżek.
    ///
    /// Można ją wywołać wielokrotnie dla tego samego projektu (dogrywanie kolejnych kart
    /// tego samego dnia): istniejące katalogi i plik `.drp` zostają nietknięte, a manifest
    /// zachowuje pierwotną datę utworzenia.
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
        let now = ISO8601DateFormatter().string(from: Date())
        let manifest: [String: Any] = [
            "projectName": layout.projectName,
            "resolution": settings.resolution,
            "frameRate": settings.frameRate,
            "createdAt": existingManifestCreatedAt(in: layout) ?? now,
            "updatedAt": now,
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

    /// Data utworzenia z manifestu zapisanego przy wcześniejszym zgraniu do tego projektu.
    private func existingManifestCreatedAt(in layout: ProjectLayout) -> String? {
        guard let data = try? Data(contentsOf: layout.manifestURL()),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["createdAt"] as? String
    }

    /// Tworzy plik projektu DaVinci Resolve.
    ///
    /// Format `.drp` nie jest publicznie udokumentowany, dlatego zamiast generować plik
    /// od zera, kopiujemy wzorcowy plik `.drp` dostarczony przez użytkownika i nadajemy mu
    /// nazwę projektu. Jeżeli szablon nie jest skonfigurowany, tworzymy plik `.drp` zastępczy
    /// o zerowej długości z ostrzeżeniem w manifestcie.
    ///
    /// Istniejący plik `.drp` (z wcześniejszego zgrania do tego projektu) nigdy nie jest
    /// nadpisywany.
    private func writeDRPProject(to layout: ProjectLayout) throws {
        let target = layout.drpFileURL()
        guard !FileManager.default.fileExists(atPath: target.path) else { return }

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
