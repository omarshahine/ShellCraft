import XCTest
@testable import ShellCraft

final class ShellConfigParserTests: XCTestCase {

    // MARK: - Alias Parsing

    func testParseSimpleAlias() {
        let result = ShellLineParser.parseAlias(from: "alias ll='ls -la'")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "ll")
        XCTAssertEqual(result?.expansion, "ls -la")
        XCTAssertTrue(result?.enabled ?? false)
    }

    func testParseDoubleQuotedAlias() {
        let result = ShellLineParser.parseAlias(from: "alias gs=\"git status\"")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "gs")
        XCTAssertEqual(result?.expansion, "git status")
        XCTAssertTrue(result?.enabled ?? false)
    }

    func testParseSingleQuotedAlias() {
        let result = ShellLineParser.parseAlias(from: "alias grep='grep --color=auto'")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "grep")
        XCTAssertEqual(result?.expansion, "grep --color=auto")
        XCTAssertTrue(result?.enabled ?? false)
    }

    func testParseAliasWithSpacesInExpansion() {
        let result = ShellLineParser.parseAlias(from: "alias cdp='cd ~/Projects/my project'")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "cdp")
        XCTAssertEqual(result?.expansion, "cd ~/Projects/my project")
    }

    func testParseCommentedAlias() {
        let result = ShellLineParser.parseAlias(from: "# alias old='some old command'")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "old")
        XCTAssertEqual(result?.expansion, "some old command")
        XCTAssertFalse(result?.enabled ?? true)
    }

    func testParseNonAliasLineReturnsNil() {
        XCTAssertNil(ShellLineParser.parseAlias(from: "export PATH=/usr/bin"))
        XCTAssertNil(ShellLineParser.parseAlias(from: "echo hello"))
        XCTAssertNil(ShellLineParser.parseAlias(from: ""))
    }

    // MARK: - Function Parsing

    func testParseFunctionStart() {
        let name = ShellLineParser.parseFunctionStart(from: "my_func() {")
        XCTAssertEqual(name, "my_func")
    }

    func testParseFunctionKeywordStart() {
        let name = ShellLineParser.parseFunctionStart(from: "function my_func {")
        XCTAssertEqual(name, "my_func")
    }

    func testParseFunctionKeywordWithParens() {
        let name = ShellLineParser.parseFunctionStart(from: "function helper() {")
        XCTAssertEqual(name, "helper")
    }

    func testParseFunctionStartNonFunction() {
        XCTAssertNil(ShellLineParser.parseFunctionStart(from: "alias gs='git status'"))
        XCTAssertNil(ShellLineParser.parseFunctionStart(from: "export PATH=/usr/bin"))
        XCTAssertNil(ShellLineParser.parseFunctionStart(from: "echo hello"))
    }

    func testParseFunctionWithHyphen() {
        let name = ShellLineParser.parseFunctionStart(from: "my-func() {")
        XCTAssertEqual(name, "my-func")
    }

    func testParseMultiLineFunctionFromConfig() throws {
        let lines = [
            "# Greet the user",
            "greet() {",
            "  echo \"Hello, $1!\"",
            "  echo \"Welcome back.\"",
            "}",
        ]

        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "test_functions_\(UUID().uuidString)"
        let content = lines.joined(separator: "\n")
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let config = try ShellConfigParser.parseSingleFile(tempFile)
        XCTAssertEqual(config.functions.count, 1)

        let fn = config.functions[0]
        XCTAssertEqual(fn.name, "greet")
        XCTAssertTrue(fn.body.contains("echo"))
        XCTAssertEqual(fn.description, "Greet the user")
    }

    func testParseSingleLineFunctionFromConfig() throws {
        let content = "quick() { echo done; }"
        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "test_single_fn_\(UUID().uuidString)"
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let config = try ShellConfigParser.parseSingleFile(tempFile)
        XCTAssertEqual(config.functions.count, 1)
        XCTAssertEqual(config.functions[0].name, "quick")
    }

    func testParseNestedBracesFunction() throws {
        let lines = [
            "check() {",
            "  if [ -f \"$1\" ]; then",
            "    echo \"exists\"",
            "  fi",
            "}",
        ]

        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "test_nested_\(UUID().uuidString)"
        let content = lines.joined(separator: "\n")
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let config = try ShellConfigParser.parseSingleFile(tempFile)
        XCTAssertEqual(config.functions.count, 1)
        XCTAssertEqual(config.functions[0].name, "check")
    }

    // MARK: - PATH Parsing

    func testParseSimplePathExport() throws {
        let content = "export PATH=\"/usr/local/bin:/usr/bin\""
        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "test_path_\(UUID().uuidString)"
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let config = try ShellConfigParser.parseSingleFile(tempFile)
        XCTAssertEqual(config.pathEntries.count, 2)
        XCTAssertEqual(config.pathEntries[0].path, "/usr/local/bin")
        XCTAssertEqual(config.pathEntries[1].path, "/usr/bin")
    }

    func testParsePathPrepend() throws {
        let content = "PATH=\"/opt/homebrew/bin:$PATH\""
        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "test_path_prepend_\(UUID().uuidString)"
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let config = try ShellConfigParser.parseSingleFile(tempFile)
        XCTAssertEqual(config.pathEntries.count, 1)
        XCTAssertEqual(config.pathEntries[0].path, "/opt/homebrew/bin")
    }

    func testParsePathWithDollarPATHFiltered() throws {
        let content = "export PATH=\"/usr/local/bin:$PATH\""
        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "test_path_dollar_\(UUID().uuidString)"
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let config = try ShellConfigParser.parseSingleFile(tempFile)
        // $PATH should be filtered out, leaving only the actual paths
        for entry in config.pathEntries {
            XCTAssertNotEqual(entry.path, "$PATH")
            XCTAssertNotEqual(entry.path, "${PATH}")
        }
    }

    func testParseMultiplePathEntries() throws {
        let content = "export PATH=\"/opt/homebrew/bin:/usr/local/go/bin:$HOME/.cargo/bin:$PATH\""
        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "test_multi_path_\(UUID().uuidString)"
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let config = try ShellConfigParser.parseSingleFile(tempFile)
        XCTAssertEqual(config.pathEntries.count, 3)
    }

    // MARK: - Export Parsing

    func testParseSimpleExport() {
        let result = ShellLineParser.parseExport(from: "export EDITOR=\"vim\"")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "EDITOR")
        XCTAssertEqual(result?.value, "vim")
    }

    func testParseSingleQuotedExport() {
        let result = ShellLineParser.parseExport(from: "export API_KEY='abc123'")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "API_KEY")
        XCTAssertEqual(result?.value, "abc123")
    }

    func testParseExportWithVariableReference() {
        let result = ShellLineParser.parseExport(from: "export GOPATH=$HOME/go")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "GOPATH")
        XCTAssertEqual(result?.value, "$HOME/go")
    }

    func testParseNonExportReturnsNil() {
        XCTAssertNil(ShellLineParser.parseExport(from: "alias gs='git status'"))
        XCTAssertNil(ShellLineParser.parseExport(from: "echo hello"))
    }

    // MARK: - Round Trip (Parse then Write)

    func testRoundTripAliases() throws {
        let lines = [
            "alias gs='git status'",
            "alias ll='ls -la'",
            "# alias old='disabled'",
        ]

        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "test_roundtrip_\(UUID().uuidString)"
        let content = lines.joined(separator: "\n")
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        // Parse
        let config = try ShellConfigParser.parseSingleFile(tempFile)
        XCTAssertEqual(config.aliases.count, 3)

        // Generate alias lines back
        for alias in config.aliases {
            let generated = ShellConfigWriter.generateAliasLine(
                name: alias.name,
                expansion: alias.expansion,
                enabled: alias.isEnabled
            )
            // Verify the generated line can be parsed back to the same values
            let reparsed = ShellLineParser.parseAlias(from: generated)
            XCTAssertNotNil(reparsed)
            XCTAssertEqual(reparsed?.name, alias.name)
            XCTAssertEqual(reparsed?.expansion, alias.expansion)
            XCTAssertEqual(reparsed?.enabled, alias.isEnabled)
        }
    }

    func testRoundTripFunction() {
        let name = "greet"
        let body = "echo \"Hello, $1!\"\necho \"Welcome back.\""

        let generated = ShellConfigWriter.generateFunctionBlock(name: name, body: body)
        let generatedLines = generated.components(separatedBy: "\n")

        // First line should be parseable as function start
        let parsedName = ShellLineParser.parseFunctionStart(from: generatedLines[0])
        XCTAssertEqual(parsedName, name)
    }

    // MARK: - Comment and Blank Line Handling

    func testCommentDetection() {
        XCTAssertTrue(ShellLineParser.isComment("# This is a comment"))
        XCTAssertTrue(ShellLineParser.isComment("  # Indented comment"))
        XCTAssertFalse(ShellLineParser.isComment("echo hello # inline comment"))
        XCTAssertFalse(ShellLineParser.isComment("alias gs='git status'"))
    }

    func testBlankLineDetection() {
        XCTAssertTrue(ShellLineParser.isBlank(""))
        XCTAssertTrue(ShellLineParser.isBlank("   "))
        XCTAssertTrue(ShellLineParser.isBlank("\t"))
        XCTAssertFalse(ShellLineParser.isBlank("hello"))
        XCTAssertFalse(ShellLineParser.isBlank("  x"))
    }

    func testCommentPreservation() throws {
        let lines = [
            "# My aliases",
            "alias gs='git status'",
            "",
            "# Navigation",
            "alias ..='cd ..'",
        ]

        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "test_comments_\(UUID().uuidString)"
        let content = lines.joined(separator: "\n")
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let config = try ShellConfigParser.parseSingleFile(tempFile)

        // Raw lines should contain the comments and blank lines
        let rawLines = config.rawLines[tempFile]
        XCTAssertNotNil(rawLines)
        XCTAssertEqual(rawLines?.count, lines.count)
        XCTAssertEqual(rawLines?[0], "# My aliases")
        XCTAssertEqual(rawLines?[2], "")
        XCTAssertEqual(rawLines?[3], "# Navigation")
    }

    // MARK: - Mixed Content Parsing

    func testMixedConfigFileParsing() throws {
        let lines = [
            "# Shell config",
            "export EDITOR=\"vim\"",
            "export PATH=\"/opt/homebrew/bin:$PATH\"",
            "",
            "alias gs='git status'",
            "",
            "greet() {",
            "  echo hello",
            "}",
        ]

        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "test_mixed_\(UUID().uuidString)"
        let content = lines.joined(separator: "\n")
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }

        let config = try ShellConfigParser.parseSingleFile(tempFile)

        XCTAssertEqual(config.environmentVariables.count, 1) // EDITOR only (PATH is handled separately)
        XCTAssertEqual(config.environmentVariables[0].key, "EDITOR")
        XCTAssertEqual(config.pathEntries.count, 1)
        XCTAssertEqual(config.pathEntries[0].path, "/opt/homebrew/bin")
        XCTAssertEqual(config.aliases.count, 1)
        XCTAssertEqual(config.aliases[0].name, "gs")
        XCTAssertEqual(config.functions.count, 1)
        XCTAssertEqual(config.functions[0].name, "greet")
    }

    // MARK: - Unquote Utility

    func testUnquoteSingleQuotes() {
        XCTAssertEqual(ShellLineParser.unquote("'hello world'"), "hello world")
    }

    func testUnquoteDoubleQuotes() {
        XCTAssertEqual(ShellLineParser.unquote("\"hello world\""), "hello world")
    }

    func testUnquoteNoQuotes() {
        XCTAssertEqual(ShellLineParser.unquote("hello"), "hello")
    }

    func testUnquoteTrimsWhitespace() {
        XCTAssertEqual(ShellLineParser.unquote("  'hello'  "), "hello")
    }

    // MARK: - Keychain Detection

    func testIsKeychainDerived() {
        let keychainValue = "$(security find-generic-password -s 'env/API_KEY' -a \"$USER\" -w)"
        XCTAssertTrue(ShellLineParser.isKeychainDerived(keychainValue))
    }

    func testIsNotKeychainDerived() {
        XCTAssertFalse(ShellLineParser.isKeychainDerived("plain_value"))
        XCTAssertFalse(ShellLineParser.isKeychainDerived("/usr/local/bin"))
    }
}
