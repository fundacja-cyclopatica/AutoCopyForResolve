import XCTest
@testable import SDCardOrganizerCore

final class FileTypeFilterTests: XCTestCase {
    func testNormalizesExtensions() {
        let filter = FileTypeFilter(enabledExtensions: [".MOV", " Mp4 ", "jpeg"])
        XCTAssertTrue(filter.enabledExtensions.contains("mov"))
        XCTAssertTrue(filter.enabledExtensions.contains("mp4"))
        XCTAssertTrue(filter.enabledExtensions.contains("jpeg"))
    }

    func testWildcardIncludesEverything() {
        let filter = FileTypeFilter(enabledExtensions: ["*"])
        XCTAssertTrue(filter.isIncluded(URL(fileURLWithPath: "/a/photo.jpg")))
        XCTAssertTrue(filter.isIncluded(URL(fileURLWithPath: "/a/noextension")))
    }

    func testMatchesCaseInsensitive() {
        let filter = FileTypeFilter(enabledExtensions: ["mov", "mp4"])
        XCTAssertTrue(filter.isIncluded(URL(fileURLWithPath: "/a/CLIP.MOV")))
        XCTAssertTrue(filter.isIncluded(URL(fileURLWithPath: "/a/clip.mp4")))
        XCTAssertFalse(filter.isIncluded(URL(fileURLWithPath: "/a/photo.jpg")))
    }

    func testFileWithoutExtensionIsExcluded() {
        let filter = FileTypeFilter(enabledExtensions: ["mov"])
        XCTAssertFalse(filter.isIncluded(URL(fileURLWithPath: "/a/README")))
    }
}

final class UniqueNamerTests: XCTestCase {
    func testNoCollisionReturnsOriginalName() {
        let dir = URL(fileURLWithPath: "/tmp")
        let result = UniqueNamer.uniqueURL(
            for: URL(fileURLWithPath: "/src/clip.mov"),
            in: dir,
            existingNames: []
        )
        XCTAssertEqual(result.lastPathComponent, "clip.mov")
    }

    func testCollisionAddsSuffix() {
        let dir = URL(fileURLWithPath: "/tmp")
        let result = UniqueNamer.uniqueURL(
            for: URL(fileURLWithPath: "/src/clip.mov"),
            in: dir,
            existingNames: ["clip.mov"]
        )
        XCTAssertEqual(result.lastPathComponent, "clip_1.mov")
    }

    func testMultipleCollisionsIncrement() {
        let dir = URL(fileURLWithPath: "/tmp")
        let result = UniqueNamer.uniqueURL(
            for: URL(fileURLWithPath: "/src/clip.mov"),
            in: dir,
            existingNames: ["clip.mov", "clip_1.mov", "clip_2.mov"]
        )
        XCTAssertEqual(result.lastPathComponent, "clip_3.mov")
    }

    func testNoExtensionCollision() {
        let dir = URL(fileURLWithPath: "/tmp")
        let result = UniqueNamer.uniqueURL(
            for: URL(fileURLWithPath: "/src/file"),
            in: dir,
            existingNames: ["file"]
        )
        XCTAssertEqual(result.lastPathComponent, "file_1")
    }
}
