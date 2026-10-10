import XCTest
@testable import SDCardOrganizerCore

/// Odmiana liczebników, lista istniejących projektów i dogrywanie do projektu z innego dnia.
final class ProjectsAndWordingTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
    }

    func testPolishPluralForms() {
        XCTAssertEqual(PolishPlural.files(0), "0 plików")
        XCTAssertEqual(PolishPlural.files(1), "1 plik")
        XCTAssertEqual(PolishPlural.files(2), "2 pliki")
        XCTAssertEqual(PolishPlural.files(4), "4 pliki")
        XCTAssertEqual(PolishPlural.files(5), "5 plików")
        XCTAssertEqual(PolishPlural.files(12), "12 plików")
        XCTAssertEqual(PolishPlural.files(14), "14 plików")
        XCTAssertEqual(PolishPlural.files(22), "22 pliki")
        XCTAssertEqual(PolishPlural.files(112), "112 plików")
        XCTAssertEqual(PolishPlural.files(1_024), "1024 pliki")
        XCTAssertEqual(PolishPlural.cards(3), "3 karty")
        XCTAssertEqual(PolishPlural.photos(21), "21 zdjęć")
        XCTAssertEqual(PolishPlural.errors(1), "1 błąd")
    }

    func testParsesProjectFolderNames() throws {
        let parsed = try XCTUnwrap(ProjectLayout.parseFolderName("2026-10-08_Wesele Ani"))
        XCTAssertEqual(parsed.name, "Wesele Ani")
        XCTAssertEqual(ProjectLayout.folderName(projectName: parsed.name, date: parsed.date), "2026-10-08_Wesele Ani")

        XCTAssertNil(ProjectLayout.parseFolderName("Wesele"))
        XCTAssertNil(ProjectLayout.parseFolderName("2026-10-08_"))
        XCTAssertNil(ProjectLayout.parseFolderName("2026-13-45_Zla data"))
        XCTAssertNil(ProjectLayout.parseFolderName("20261008_Bez myslnikow"))
    }

    func testCatalogListsOnlyProjectFoldersNewestFirst() throws {
        for name in ["2026-10-01_Reklama", "2026-10-08_Wesele", "Inne pliki", ".2026-10-09_Ukryty"] {
            try fm.createDirectory(at: tempDir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try "x".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("2026-10-09_plik.txt"))

        let projects = ProjectCatalog.projects(in: tempDir.path)

        XCTAssertEqual(projects.map(\.folderName), ["2026-10-08_Wesele", "2026-10-01_Reklama"])
        XCTAssertEqual(projects.first?.name, "Wesele")
        XCTAssertEqual(ProjectCatalog.projects(in: tempDir.appendingPathComponent("brak").path), [])
    }

    func testBuildIntoExistingProjectFromAnotherDay() throws {
        let existing = tempDir.appendingPathComponent("2026-10-08_Wesele", isDirectory: true)
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        let project = try XCTUnwrap(ProjectCatalog.projects(in: tempDir.path).first)

        var settings = Settings()
        settings.destinationRoot = tempDir.path
        let layout = try ProjectBuilder(settings: settings).build(projectName: project.name, date: project.date)

        XCTAssertEqual(layout.root.standardizedFileURL.path, existing.standardizedFileURL.path)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: tempDir.path).filter { !$0.hasPrefix(".") }, ["2026-10-08_Wesele"])
    }
}
