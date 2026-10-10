import XCTest
@testable import SDCardOrganizerCore

/// Postęp liczony w bajtach, anulowanie zgrywania i pomiar prędkości.
final class ProgressAndCancellationTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
    }

    /// Karta z plikami wideo o podanych rozmiarach.
    private func makeCard(sizes: [Int]) throws -> [MediaFile] {
        let card = tempDir.appendingPathComponent("card", isDirectory: true)
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        for (index, size) in sizes.enumerated() {
            try Data(repeating: UInt8(index), count: size)
                .write(to: card.appendingPathComponent(String(format: "C%04d.MP4", index + 1)))
        }
        return try MediaScanner(enabledExtensions: ["mp4"]).scan(volumeRoot: card)
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    private func visibleFiles(in dir: URL) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    func testProgressIsReportedInBytesAndReachesTotal() throws {
        // Drugi plik większy niż blok 8 MB — postęp przychodzi także w trakcie pliku.
        let files = try makeCard(sizes: [1_000, 10_000_000])
        let layout = ProjectLayout(destinationRoot: tempDir.appendingPathComponent("dest").path, projectName: "Test")
        let service = CopyService(verifyChecksums: false, verifyCopies: true)
        var events: [CopyProgress] = []
        service.onProgress = { events.append($0) }

        _ = try service.copy(files: files, to: layout)

        let last = try XCTUnwrap(events.last)
        XCTAssertEqual(last.totalBytes, 10_001_000)
        XCTAssertEqual(last.processedBytes, 10_001_000)
        XCTAssertEqual(last.fraction, 1)
        XCTAssertTrue(events.contains { $0.filesDone == 1 && $0.processedBytes > 1_000 && $0.processedBytes < 10_001_000 })
        XCTAssertEqual(events.map(\.processedBytes), events.map(\.processedBytes).sorted())
    }

    func testCancellationStopsBeforeNextFile() throws {
        let files = try makeCard(sizes: [1_000, 2_000])
        let layout = ProjectLayout(destinationRoot: tempDir.appendingPathComponent("dest").path, projectName: "Test")
        let token = CancellationToken()
        let service = CopyService(verifyChecksums: false, cancellation: token)
        service.onProgress = { progress in
            if progress.filesDone == 1 { token.cancel() }
        }

        let report = try service.copy(files: files, to: layout)

        XCTAssertTrue(report.wasCancelled)
        XCTAssertEqual(report.totalCopied, 1)
        XCTAssertEqual(report.totalFailed, 0)
        XCTAssertEqual(visibleFiles(in: layout.videoDir), ["C0001.MP4"])
    }

    func testCancellationMidFileLeavesNoPartialFile() throws {
        let files = try makeCard(sizes: [20_000_000])
        let layout = ProjectLayout(destinationRoot: tempDir.appendingPathComponent("dest").path, projectName: "Test")
        let token = CancellationToken()
        let service = CopyService(verifyChecksums: false, verifyCopies: true, cancellation: token)
        service.onProgress = { progress in
            if progress.filesDone == 0 && progress.processedBytes > 0 { token.cancel() }
        }

        let report = try service.copy(files: files, to: layout)

        XCTAssertTrue(report.wasCancelled)
        XCTAssertEqual(report.totalCopied, 0)
        XCTAssertEqual(report.totalFailed, 0)
        XCTAssertEqual(visibleFiles(in: layout.videoDir), [], "Nie może zostać ani klip, ani plik .part")
    }

    func testRateMeterAveragesOverWindow() {
        var meter = TransferRateMeter(window: 5)
        meter.add(totalBytes: 0, at: 100)
        meter.add(totalBytes: 10_000_000, at: 100.2)
        XCTAssertNil(meter.bytesPerSecond, "Za krótki pomiar")

        meter.add(totalBytes: 100_000_000, at: 101)
        XCTAssertEqual(meter.bytesPerSecond ?? 0, 100_000_000, accuracy: 1)
        XCTAssertEqual(meter.secondsRemaining(forRemainingBytes: 200_000_000) ?? 0, 2, accuracy: 0.001)

        // Stare próbki wypadają z okna; zostaje jedna sprzed jego początku (t = 101).
        meter.add(totalBytes: 150_000_000, at: 110)
        meter.add(totalBytes: 160_000_000, at: 111)
        XCTAssertEqual(meter.bytesPerSecond ?? 0, 6_000_000, accuracy: 1)
    }
}
