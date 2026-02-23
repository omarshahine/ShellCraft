import Foundation

struct ProcessService {
    struct Result: Sendable {
        let output: String
        let error: String
        let exitCode: Int32
        var succeeded: Bool { exitCode == 0 }
    }

    @discardableResult
    static func run(_ command: String, arguments: [String] = [], environment: [String: String]? = nil) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", ([command] + arguments).joined(separator: " ")]

            if let environment {
                var env = ProcessInfo.processInfo.environment
                env.merge(environment) { _, new in new }
                process.environment = env
            }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()

                // Read pipe data before waitUntilExit to avoid deadlock.
                // If the child writes >64 KB the pipe buffer fills; the
                // process blocks on write and waitUntilExit never returns.
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

                process.waitUntilExit()

                let result = Result(
                    output: String(data: outputData, encoding: .utf8)?.trimmed ?? "",
                    error: String(data: errorData, encoding: .utf8)?.trimmed ?? "",
                    exitCode: process.terminationStatus
                )
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Run a command and return just the output string
    static func output(of command: String) async throws -> String {
        let result = try await run(command)
        guard result.succeeded else {
            throw ProcessError.commandFailed(command: command, error: result.error, exitCode: result.exitCode)
        }
        return result.output
    }

    /// Check if a command exists in PATH
    static func commandExists(_ command: String) async -> Bool {
        let result = try? await run("which \(command)")
        return result?.succeeded ?? false
    }
}

enum ProcessError: LocalizedError {
    case commandFailed(command: String, error: String, exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let error, let exitCode):
            "Command '\(command)' failed (exit \(exitCode)): \(error)"
        }
    }
}
