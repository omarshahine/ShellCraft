import XCTest
@testable import ShellCraft

final class PathValidatorTests: XCTestCase {

    private var validator: PathValidator!

    override func setUp() {
        super.setUp()
        validator = PathValidator.shared
    }

    // MARK: - Existing Path

    func testExistingPathReturnsTrue() async {
        // /usr/bin should always exist on macOS
        let result = await validator.validate("/usr/bin")
        XCTAssertTrue(result)
    }

    func testExistingFileReturnsTrue() async {
        // /usr/bin/env should always exist on macOS
        let result = await validator.validate("/usr/bin/env")
        XCTAssertTrue(result)
    }

    func testHomeDirectoryReturnsTrue() async {
        let home = NSHomeDirectory()
        let result = await validator.validate(home)
        XCTAssertTrue(result)
    }

    // MARK: - Non-Existing Path

    func testNonExistingPathReturnsFalse() async {
        let result = await validator.validate("/nonexistent/path/that/does/not/exist")
        XCTAssertFalse(result)
    }

    func testNonExistingFileReturnsFalse() async {
        let result = await validator.validate("/usr/bin/definitely_not_a_real_command_\(UUID().uuidString)")
        XCTAssertFalse(result)
    }

    // MARK: - Tilde Expansion

    func testTildeExpansionForExistingPath() async {
        // ~ should expand to home directory which always exists
        let result = await validator.validate("~")
        XCTAssertTrue(result)
    }

    func testTildeSlashExpansionForExistingPath() async {
        // ~/Library should exist on macOS
        let result = await validator.validate("~/Library")
        XCTAssertTrue(result)
    }

    func testTildeExpansionForNonExistingPath() async {
        let result = await validator.validate("~/nonexistent_directory_\(UUID().uuidString)")
        XCTAssertFalse(result)
    }

    // MARK: - Validate All

    func testValidateAllPathEntries() async {
        let entries = [
            PathEntry(path: "/usr/bin", order: 0),
            PathEntry(path: "/nonexistent/path", order: 1),
            PathEntry(path: "/usr/local/bin", order: 2),
        ]

        let validated = await validator.validateAll(entries)

        XCTAssertEqual(validated.count, 3)

        // /usr/bin should exist
        XCTAssertTrue(validated[0].exists)
        XCTAssertEqual(validated[0].expandedPath, "/usr/bin")

        // /nonexistent/path should not exist
        XCTAssertFalse(validated[1].exists)

        // /usr/local/bin may or may not exist; just check it was processed
        XCTAssertEqual(validated[2].expandedPath, "/usr/local/bin")
    }

    func testValidateAllWithTildePaths() async {
        let entries = [
            PathEntry(path: "~/Library", order: 0),
            PathEntry(path: "~/nonexistent_\(UUID().uuidString)", order: 1),
        ]

        let validated = await validator.validateAll(entries)

        XCTAssertEqual(validated.count, 2)

        // ~/Library should expand and exist
        XCTAssertTrue(validated[0].exists)
        XCTAssertTrue(validated[0].expandedPath.hasSuffix("/Library"))
        XCTAssertFalse(validated[0].expandedPath.hasPrefix("~"))

        // Non-existent should not exist
        XCTAssertFalse(validated[1].exists)
        XCTAssertFalse(validated[1].expandedPath.hasPrefix("~"))
    }

    func testValidateAllPreservesOrder() async {
        let entries = [
            PathEntry(path: "/usr/bin", order: 2),
            PathEntry(path: "/usr/local/bin", order: 0),
            PathEntry(path: "/opt/homebrew/bin", order: 1),
        ]

        let validated = await validator.validateAll(entries)

        // Order should be preserved (not re-sorted)
        XCTAssertEqual(validated[0].path, "/usr/bin")
        XCTAssertEqual(validated[0].order, 2)
        XCTAssertEqual(validated[1].path, "/usr/local/bin")
        XCTAssertEqual(validated[1].order, 0)
    }

    func testValidateAllEmptyList() async {
        let validated = await validator.validateAll([])
        XCTAssertTrue(validated.isEmpty)
    }

    // MARK: - Edge Cases

    func testEmptyStringPath() async {
        let result = await validator.validate("")
        // Empty string expands to empty string, which does not exist as a path
        XCTAssertFalse(result)
    }

    func testRootPathExists() async {
        let result = await validator.validate("/")
        XCTAssertTrue(result)
    }

    func testPathWithTrailingSlash() async {
        let result = await validator.validate("/usr/bin/")
        XCTAssertTrue(result)
    }
}
