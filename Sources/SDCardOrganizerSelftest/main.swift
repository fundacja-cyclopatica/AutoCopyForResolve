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
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let historyURL = dir.appendingPathComponent("history.json")
            IngestHistory.append(record, to: historyURL)
            let loaded = IngestHistory.load(from: historyURL)
            return loaded.contains(where: { $0.projectName == "SampleProject" && $0.filesCopied == 5 })
        }

        check("DaySummary formatuje daty (Dzisiaj/Wczoraj/dd.MM.yyyy)") {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.locale = Locale(identifier: "en_US_POSIX")

            let todayString = df.string(from: Date())
            let yesterdayString = df.string(from: Date().addingTimeInterval(-86400))
            let oldDateString = "2024-05-14"

            let summaryToday = DaySummary(dayString: todayString, files: [])
            let summaryYesterday = DaySummary(dayString: yesterdayString, files: [])
            let summaryOld = DaySummary(dayString: oldDateString, files: [])

            return summaryToday.displayText == "Dzisiaj"
                && summaryYesterday.displayText == "Wczoraj"
                && summaryOld.displayText == "14.05.2024"
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

        check("Ustawienia ze starszej wersji zachowują wartości użytkownika") {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("settings.json")
            let json = #"{"destinationRoot":"/Volumes/SSD","enabledExtensions":["mov"],"resolution":"3840x2160","frameRate":50,"verifyChecksums":false}"#
            try! json.data(using: .utf8)!.write(to: url)
            let loaded = try! SettingsStore.load(from: url)
            return loaded.destinationRoot == "/Volumes/SSD"
                && loaded.enabledExtensions == ["mov"]
                && loaded.frameRate == 50
                && loaded.cameraPresets == Settings.defaultCameraPresets
                && loaded.verifyCopies
        }

        check("Nieczytelny plik ustawień zostaje zachowany jako kopia") {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("settings.json")
            try! "to nie jest JSON".data(using: .utf8)!.write(to: url)
            let loaded = try! SettingsStore.load(from: url)
            let backups = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
                .filter { $0.contains(".unreadable-") } ?? []
            return loaded == Settings() && backups.count == 1
        }

        check("Dogrywanie do istniejącego projektu z szablonem .drp") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let dest = base.appendingPathComponent("dest")
            try! FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let template = base.appendingPathComponent("szablon.drp")
            try! "TEMPLATE".data(using: .utf8)!.write(to: template)
            var s = Settings()
            s.destinationRoot = dest.path
            s.drpTemplatePath = template.path
            guard (try? ProjectBuilder(settings: s).build(projectName: "Wesele")) != nil,
                  let layout = try? ProjectBuilder(settings: s).build(projectName: "Wesele") else {
                return false
            }
            s.drpTemplatePath = nil
            guard (try? ProjectBuilder(settings: s).build(projectName: "Wesele")) != nil else { return false }
            return (try? String(contentsOf: layout.drpFileURL(), encoding: .utf8)) == "TEMPLATE"
        }

        check("Błąd jednego pliku nie przerywa zgrywania") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let card = base.appendingPathComponent("card")
            let dest = base.appendingPathComponent("dest")
            try! FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let good = card.appendingPathComponent("A002.MOV")
            try! "dobry-klip".data(using: .utf8)!.write(to: good)
            let files = [
                MediaFile(url: card.appendingPathComponent("A001.MOV"), category: .video, size: 10),
                MediaFile(url: good, category: .video, size: 10)
            ]
            let layout = ProjectLayout(destinationRoot: dest.path, projectName: "Test")
            let report = try! CopyService(verifyChecksums: false).copy(files: files, to: layout)
            return report.totalFailed == 1 && report.totalCopied == 1
                && FileManager.default.fileExists(atPath: layout.videoDir.appendingPathComponent("A002.MOV").path)
        }

        check("Weryfikacja kopii SHA-256 i zachowanie dat") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let card = base.appendingPathComponent("card")
            let dest = base.appendingPathComponent("dest")
            try! FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let source = card.appendingPathComponent("C0001.MP4")
            let content = Data((0..<200_000).map { UInt8($0 % 251) })
            try! content.write(to: source)
            let shotDate = Date(timeIntervalSince1970: 1_780_000_000)
            try! FileManager.default.setAttributes([.modificationDate: shotDate], ofItemAtPath: source.path)

            let files = try! MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: card)
            let layout = ProjectLayout(destinationRoot: dest.path, projectName: "Test")
            let report = try! CopyService(verifyChecksums: false, verifyCopies: true).copy(files: files, to: layout)
            let copy = layout.videoDir.appendingPathComponent("C0001.MP4")
            let copiedDate = (try? FileManager.default.attributesOfItem(atPath: copy.path))?[.modificationDate] as? Date
            let leftovers = ((try? FileManager.default.contentsOfDirectory(atPath: layout.videoDir.path)) ?? [])
                .filter { $0.hasSuffix(".part") }
            return report.totalVerified == 1
                && (try? Data(contentsOf: copy)) == content
                && abs((copiedDate?.timeIntervalSince1970 ?? 0) - shotDate.timeIntervalSince1970) < 1
                && leftovers.isEmpty
        }

        check("Ponowne zgranie po kolizji nazw nie tworzy duplikatów") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let cardA = base.appendingPathComponent("cardA")
            let cardB = base.appendingPathComponent("cardB")
            let dest = base.appendingPathComponent("dest")
            for dir in [cardA, cardB, dest] {
                try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try! "kamera-a".data(using: .utf8)!.write(to: cardA.appendingPathComponent("C0001.MP4"))
            try! "kamera-b-dluzszy".data(using: .utf8)!.write(to: cardB.appendingPathComponent("C0001.MP4"))
            let filesA = try! MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: cardA)
            let filesB = try! MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: cardB)
            let layout = ProjectLayout(destinationRoot: dest.path, projectName: "Test")
            let service = CopyService(verifyChecksums: false)
            _ = try! service.copy(files: filesA, to: layout)
            let firstB = try! service.copy(files: filesB, to: layout)
            let againB = try! service.copy(files: filesB, to: layout)
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: layout.videoDir.path)) ?? [])
                .filter { !$0.hasPrefix(".") }.sorted()
            return firstB.copied.map(\.lastPathComponent) == ["C0001_1.MP4"]
                && againB.totalSkipped == 1 && againB.totalCopied == 0
                && names == ["C0001.MP4", "C0001_1.MP4"]
        }

        check("Ten sam rozmiar, inna data nagrania -> nie duplikat") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let card = base.appendingPathComponent("card")
            let dest = base.appendingPathComponent("dest")
            try! FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let source = card.appendingPathComponent("A001.BRAW")
            try! "AAAA".data(using: .utf8)!.write(to: source)
            let existing = dest.appendingPathComponent("A001.BRAW")
            try! "BBBB".data(using: .utf8)!.write(to: existing)
            try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: existing.path)
            let decision = CopyPlanner.decision(
                source: source, destinationDirectory: dest, verifyChecksums: false, existingNames: ["A001.BRAW"]
            )
            return decision == .copy(dest.appendingPathComponent("A001_1.BRAW"))
        }

        check("Odznaczenie wszystkich dni = brak plików do zgrania") {
            var config = CardIngestConfig(volumeURL: URL(fileURLWithPath: "/Volumes/Card"), volumeName: "Card")
            config.setScanResults([
                MediaFile(url: URL(fileURLWithPath: "/Volumes/Card/a.mov"), category: .video, size: 10),
                MediaFile(url: URL(fileURLWithPath: "/Volumes/Card/b.wav"), category: .audio, size: 5)
            ])
            let latestOnly = config.isLatestDayOnlySelected && config.filteredFiles.count == 2
            config.includeAudio = false
            let withoutAudio = config.filteredFiles.count == 1
            config.selectedDays = []
            return latestOnly && withoutAudio && config.filteredFiles.isEmpty
        }

        check("Katalog formatów: jedno źródło prawdy, LRF domyślnie wyłączone") {
            Settings.defaultExtensions == MediaFormats.allExtensions.subtracting(["lrf"])
                && MediaCategory.category(for: URL(fileURLWithPath: "/a/clip.MPG")) == .video
                && MediaCategory.category(for: URL(fileURLWithPath: "/a/shot.IIQ")) == .photo
        }

        check("Skaner pomija miniatury kamer (THMBNL)") {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let clips = dir.appendingPathComponent("PRIVATE/M4ROOT/CLIP")
            let thumbnails = dir.appendingPathComponent("PRIVATE/M4ROOT/THMBNL")
            try! FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
            try! "klip".data(using: .utf8)!.write(to: clips.appendingPathComponent("C0001.MP4"))
            try! "miniatura".data(using: .utf8)!.write(to: thumbnails.appendingPathComponent("C0001T01.JPG"))
            let results = try! MediaScanner(enabledExtensions: ["mp4", "jpg"]).scan(volumeRoot: dir)
            return results.map(\.url.lastPathComponent) == ["C0001.MP4"]
        }

        check("Postęp w bajtach i anulowanie bez pozostawionych plików") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let card = base.appendingPathComponent("card")
            try! FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try! Data(repeating: 1, count: 1_000).write(to: card.appendingPathComponent("C0001.MP4"))
            try! Data(repeating: 2, count: 20_000_000).write(to: card.appendingPathComponent("C0002.MP4"))
            let files = try! MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: card)
                .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
            let layout = ProjectLayout(destinationRoot: base.appendingPathComponent("dest").path, projectName: "Test")

            // Anulowanie w trakcie drugiego (dużego) pliku.
            let token = CancellationToken()
            let service = CopyService(verifyChecksums: false, verifyCopies: true, cancellation: token)
            var sawPartialProgress = false
            service.onProgress = { progress in
                if progress.filesDone == 1 && progress.processedBytes > 1_000 {
                    sawPartialProgress = true
                    token.cancel()
                }
            }
            let report = try! service.copy(files: files, to: layout)
            let left = ((try? FileManager.default.contentsOfDirectory(atPath: layout.videoDir.path)) ?? []).sorted()
            return sawPartialProgress && report.wasCancelled && report.totalCopied == 1
                && report.totalFailed == 0 && left == ["C0001.MP4"]
        }

        check("Miernik prędkości uśrednia w oknie czasowym") {
            var meter = TransferRateMeter(window: 5)
            meter.add(totalBytes: 0, at: 100)
            meter.add(totalBytes: 100_000_000, at: 101)
            let rate = meter.bytesPerSecond ?? 0
            let eta = meter.secondsRemaining(forRemainingBytes: 200_000_000) ?? 0
            return abs(rate - 100_000_000) < 1 && abs(eta - 2) < 0.001
        }

        check("Polska odmiana liczebników") {
            PolishPlural.files(1) == "1 plik" && PolishPlural.files(3) == "3 pliki"
                && PolishPlural.files(5) == "5 plików" && PolishPlural.files(13) == "13 plików"
                && PolishPlural.files(22) == "22 pliki" && PolishPlural.cards(2) == "2 karty"
        }

        check("Dogrywanie do istniejącego projektu z innego dnia") {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            try! FileManager.default.createDirectory(at: dir.appendingPathComponent("2026-10-08_Wesele"), withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(at: dir.appendingPathComponent("Inny folder"), withIntermediateDirectories: true)
            let projects = ProjectCatalog.projects(in: dir.path)
            guard projects.map(\.folderName) == ["2026-10-08_Wesele"], let project = projects.first else { return false }
            var s = Settings()
            s.destinationRoot = dir.path
            let layout = try! ProjectBuilder(settings: s).build(projectName: project.name, date: project.date)
            return layout.root.lastPathComponent == "2026-10-08_Wesele"
        }

        check("Wybór trzech najnowszych dni") {
            var config = CardIngestConfig(volumeURL: URL(fileURLWithPath: "/Volumes/Card"), volumeName: "Card")
            let start = Date(timeIntervalSince1970: 1_780_000_000)
            config.setScanResults((0..<5).map { day in
                MediaFile(url: URL(fileURLWithPath: "/Volumes/Card/C\(day).mov"), category: .video, size: 10,
                          date: start.addingTimeInterval(Double(day) * 86_400 * 2))
            })
            config.selectLatestDays(3)
            return config.areLatestDaysSelected(3) && config.filteredFiles.count == 3
        }

        check("Kopia zapasowa, pliki towarzyszące i raport zgrania") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let card = base.appendingPathComponent("card")
            try! FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try! Data(repeating: 7, count: 50_000).write(to: card.appendingPathComponent("C0001.MP4"))
            try! "<xml/>".data(using: .utf8)!.write(to: card.appendingPathComponent("C0001M01.XML"))
            let files = try! MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: card)
            let primary = ProjectLayout(destinationRoot: base.appendingPathComponent("ssd").path, projectName: "Test")
            let backup = ProjectLayout(destinationRoot: base.appendingPathComponent("hdd").path, projectName: "Test")

            let report = try! CopyService(verifyChecksums: false, verifyCopies: true, copySidecars: true)
                .copy(files: files, to: primary, backupLayout: backup)
            let written = try! IngestReportWriter.write(
                projectRoot: primary.root, projectName: "Test",
                sections: [.init(title: "Kamera A", report: report)], wasCancelled: false
            )
            let checksumLines = ((try? String(contentsOf: written.checksums!, encoding: .utf8)) ?? "")
                .split(separator: "\n")
            return report.totalCopied == 1 && report.backupCopied.count == 1
                && report.sidecarsCopied.count == 2
                && FileManager.default.fileExists(atPath: backup.videoDir.appendingPathComponent("C0001M01.XML").path)
                && checksumLines.count == 1 && checksumLines[0].hasSuffix("  Video/C0001.MP4")
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
