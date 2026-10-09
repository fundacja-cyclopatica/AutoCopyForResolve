import Foundation
import SDCardOrganizerCore

/// Lekki, samowystarczalny runner testowy — działa bez Xcode/XCTest
/// (środowisko z samym CommandLineTools nie ma frameworka XCTest).
/// Uruchomienie: `swift run SDCardOrganizerSelftest`
@main
struct SelfTest {
    static var passed = 0
    static var failed = 0

    static func main() {
        check("FileTypeFilter normalizuje rozszerzenia") {
            let f = FileTypeFilter(enabledExtensions: [".MOV", " Mp4 "])
            return f.enabledExtensions.contains("mov") && f.enabledExtensions.contains("mp4")
        }
        check("FileTypeFilter wildcard") {
            FileTypeFilter(enabledExtensions: ["*"]).isIncluded(URL(fileURLWithPath: "/a/x.jpg"))
        }
        check("FileTypeFilter wyklucza inne typy") {
            !FileTypeFilter(enabledExtensions: ["mov"]).isIncluded(URL(fileURLWithPath: "/a/x.jpg"))
        }

        check("UniqueNamer brak kolizji") {
            UniqueNamer.uniqueURL(for: URL(fileURLWithPath: "/s/a.mov"), in: URL(fileURLWithPath: "/d"), existingNames: []).lastPathComponent == "a.mov"
        }
        check("UniqueNamer dodaje sufiks") {
            UniqueNamer.uniqueURL(for: URL(fileURLWithPath: "/s/a.mov"), in: URL(fileURLWithPath: "/d"), existingNames: ["a.mov"]).lastPathComponent == "a_1.mov"
        }
        check("UniqueNamer inkrementuje wielokrotnie") {
            UniqueNamer.uniqueURL(for: URL(fileURLWithPath: "/s/a.mov"), in: URL(fileURLWithPath: "/d"), existingNames: ["a.mov", "a_1.mov", "a_2.mov"]).lastPathComponent == "a_3.mov"
        }

        check("ProjectLayout sanityzuje nazwę") {
            ProjectLayout.sanitize("a/b\\c?d") == "a-b-c-d"
        }
        check("ProjectLayout pusty -> Projekt") {
            ProjectLayout.sanitize("   ") == "Projekt"
        }
        check("ProjectLayout ścieżki") {
            let l = ProjectLayout(destinationRoot: "/Volumes/D", projectName: "Test")
            return l.videoDir.lastPathComponent == "Video"
                && l.audioDir.lastPathComponent == "Audio"
                && l.photoDir.lastPathComponent == "Zdjęcia"
                && l.daVinciDir.lastPathComponent == "DaVinci"
        }

        check("MediaScanner znajduje i kategoryzuje") {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            try? "v".data(using: .utf8)!.write(to: dir.appendingPathComponent("v.mp4"))
            try? "a".data(using: .utf8)!.write(to: dir.appendingPathComponent("a.wav"))
            try? "p".data(using: .utf8)!.write(to: dir.appendingPathComponent("p.jpg"))
            try? "x".data(using: .utf8)!.write(to: dir.appendingPathComponent("x.txt"))
            let results = try! MediaScanner(enabledExtensions: ["*"]).scan(volumeRoot: dir)
            let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.url.lastPathComponent, $0.category) })
            return results.count == 3 && byName["v.mp4"] == .video && byName["p.jpg"] == .photo
        }

        check("CopyService kopiuje i liczy bajty") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let card = base.appendingPathComponent("card")
            let dest = base.appendingPathComponent("dest")
            try! FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let testData = "content-of-test-clip-12345".data(using: .utf8)!
            try! testData.write(to: card.appendingPathComponent("A001.MOV"))

            var s = Settings()
            s.destinationRoot = dest.path
            let files = try! MediaScanner(enabledExtensions: ["mov"]).scan(volumeRoot: card)
            let layout = ProjectLayout(destinationRoot: dest.path, projectName: "Test")
            let report = try! CopyService(verifyChecksums: false).copy(files: files, to: layout)
            let copiedOK = FileManager.default.fileExists(atPath: layout.videoDir.appendingPathComponent("A001.MOV").path)
            return report.totalCopied == 1 && report.totalBytesCopied == Int64(testData.count) && copiedOK
        }

        check("IngestHistory zapisuje i odczytuje rekordy") {
            let record = IngestRecord(
                projectName: "SampleProject",
                sourceVolumeName: "SD_CARD",
                destinationPath: "/Volumes/SSD/2026-10-09_SampleProject",
                filesCopied: 5,
                filesSkipped: 1,
                filesFailed: 0,
                totalBytes: 1024 * 1024
            )
            IngestHistory.append(record)
            let loaded = IngestHistory.load()
            return loaded.contains(where: { $0.projectName == "SampleProject" && $0.filesCopied == 5 })
        }

        check("CardIngestConfig zarządza dniami i selekcją") {
            var config = CardIngestConfig(
                volumeURL: URL(fileURLWithPath: "/Volumes/Card1"),
                volumeName: "Card1",
                cameraLabel: "Kamera A"
            )
            let file1 = MediaFile(url: URL(fileURLWithPath: "/Volumes/Card1/clip1.mov"), category: .video, size: 100, date: Date(timeIntervalSince1970: 1000))
            let file2 = MediaFile(url: URL(fileURLWithPath: "/Volumes/Card1/photo1.jpg"), category: .photo, size: 200, date: Date(timeIntervalSince1970: 1000000))
            config.setScanResults([file1, file2])
            config.selectAllDays()
            let all = config.filteredFiles.count

            config.includePhotos = false
            let onlyVideos = config.filteredFiles.count

            config.includeVideos = false
            config.includePhotos = true
            let onlyPhotos = config.filteredFiles.count

            return all == 2 && onlyVideos == 1 && onlyPhotos == 1 && config.cameraLabel == "Kamera A"
        }

        check("CopyService obsługuje podfoldery kamer") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let card = base.appendingPathComponent("card")
            let dest = base.appendingPathComponent("dest")
            try! FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let testData = "camera-a-clip".data(using: .utf8)!
            try! testData.write(to: card.appendingPathComponent("A002.MOV"))

            var s = Settings()
            s.destinationRoot = dest.path
            let files = try! MediaScanner(enabledExtensions: ["mov"]).scan(volumeRoot: card)
            let layout = ProjectLayout(destinationRoot: dest.path, projectName: "MultiCam")
            let report = try! CopyService(verifyChecksums: false).copy(files: files, to: layout, cameraLabel: "Kamera A")
            let cameraFolder = layout.videoDir.appendingPathComponent("Kamera A", isDirectory: true)
            let copiedOK = FileManager.default.fileExists(atPath: cameraFolder.appendingPathComponent("A002.MOV").path)
            return report.totalCopied == 1 && copiedOK
        }

        check("ProjectBuilder tworzy katalogi, manifest i .drp") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let dest = base.appendingPathComponent("dest")
            try! FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            var s = Settings()
            s.destinationRoot = dest.path
            let layout = try! ProjectBuilder(settings: s).build(projectName: "Projekt Test")
            return FileManager.default.fileExists(atPath: layout.manifestURL().path)
                && FileManager.default.fileExists(atPath: layout.drpFileURL().path)
                && FileManager.default.fileExists(atPath: layout.videoDir.path)
        }

        print("")
        print("Wynik: \(passed) zdało, \(failed) nie zdało.")
        if failed > 0 { exit(1) }
    }

    static func check(_ name: String, _ body: () -> Bool) {
        if body() {
            passed += 1
            print("✅ \(name)")
        } else {
            failed += 1
            print("❌ \(name)")
        }
    }
}
