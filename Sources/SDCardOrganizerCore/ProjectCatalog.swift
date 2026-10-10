import Foundation

/// Projekt istniejący już na dysku docelowym (folder `YYYY-MM-DD_Nazwa`).
public struct ExistingProject: Hashable, Identifiable {
    public let name: String
    public let date: Date
    public let folderName: String

    public var id: String { folderName }
}

/// Wyszukuje projekty na dysku docelowym, aby można było dogrywać do nich kolejne karty.
public enum ProjectCatalog {
    /// Projekty z dysku docelowego, od najnowszego. Foldery o innych nazwach są pomijane.
    public static func projects(in destinationRoot: String, limit: Int = 12) -> [ExistingProject] {
        guard !destinationRoot.isEmpty,
              let names = try? FileManager.default.contentsOfDirectory(atPath: destinationRoot) else {
            return []
        }

        let projects = names.compactMap { folderName -> ExistingProject? in
            guard !folderName.hasPrefix("."),
                  let parsed = ProjectLayout.parseFolderName(folderName) else { return nil }
            var isDirectory: ObjCBool = false
            let path = (destinationRoot as NSString).appendingPathComponent(folderName)
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return ExistingProject(name: parsed.name, date: parsed.date, folderName: folderName)
        }

        return Array(projects.sorted {
            $0.folderName > $1.folderName
        }.prefix(limit))
    }
}
