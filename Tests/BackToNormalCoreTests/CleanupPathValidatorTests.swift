import XCTest
@testable import BackToNormalCore

final class CleanupPathValidatorTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackToNormalPathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
    }

    func testAcceptsMatchingDirectChildDirectory() throws {
        let child = temporaryRoot.appendingPathComponent("Project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let identifier = try XCTUnwrap(CleanupPathValidator.filesystemObjectIdentifier(at: child))
        XCTAssertEqual(
            CleanupPathValidator.validatedDirectChild(
                path: child.path,
                expectedObjectIdentifier: identifier,
                allowedRoot: temporaryRoot
            ),
            child.standardizedFileURL
        )
    }

    func testRejectsNestedDirectory() throws {
        let parent = temporaryRoot.appendingPathComponent("Parent", isDirectory: true)
        let child = parent.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let identifier = try XCTUnwrap(CleanupPathValidator.filesystemObjectIdentifier(at: child))
        XCTAssertNil(CleanupPathValidator.validatedDirectChild(
            path: child.path, expectedObjectIdentifier: identifier, allowedRoot: temporaryRoot
        ))
    }

    func testRejectsSymbolicLink() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackToNormalOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = temporaryRoot.appendingPathComponent("Linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let identifier = try XCTUnwrap(CleanupPathValidator.filesystemObjectIdentifier(at: link))
        XCTAssertNil(CleanupPathValidator.validatedDirectChild(
            path: link.path, expectedObjectIdentifier: identifier, allowedRoot: temporaryRoot
        ))
    }

    func testRejectsChangedFilesystemIdentifier() throws {
        let child = temporaryRoot.appendingPathComponent("Project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        XCTAssertNil(CleanupPathValidator.validatedDirectChild(
            path: child.path, expectedObjectIdentifier: "0:0", allowedRoot: temporaryRoot
        ))
    }
}
