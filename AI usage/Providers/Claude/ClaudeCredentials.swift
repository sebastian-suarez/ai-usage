import Dispatch
import Foundation

struct ClaudeCredentials: Equatable {
    let accessToken: String
    let expiresAt: Date?
}

protocol ClaudeCredentialsSource {
    func load() async throws -> ClaudeCredentials
}

struct KeychainClaudeCredentialsSource: ClaudeCredentialsSource {
    private static let keychainService = "Claude Code-credentials"

    private let credentialsFileURL: URL
    private let securityExecutableURL: URL
    private let securityArguments: [String]
    private let keychainTimeout: TimeInterval

    init(
        credentialsFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/.credentials.json"),
        securityExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/security"),
        securityArguments: [String]? = nil,
        keychainTimeout: TimeInterval = 10
    ) {
        self.credentialsFileURL = credentialsFileURL
        self.securityExecutableURL = securityExecutableURL
        self.securityArguments = securityArguments ?? [
            "find-generic-password",
            "-s",
            Self.keychainService,
            "-w",
        ]
        self.keychainTimeout = keychainTimeout
    }

    func load() async throws -> ClaudeCredentials {
        var keychainItemWasMissing = false

        do {
            let result = try await readKeychain()
            if result.terminationStatus == 0 {
                return try Self.parseCredentials(result.data)
            }

            keychainItemWasMissing = result.terminationReason == .exit
                && result.terminationStatus == 44
        } catch let error as UsageProviderError {
            throw error
        } catch {
            // A missing or unavailable Keychain entry may have a file-based fallback.
        }

        guard FileManager.default.fileExists(atPath: credentialsFileURL.path) else {
            if keychainItemWasMissing {
                throw UsageProviderError.notConnected("Not signed in to Claude Code")
            }

            throw UsageProviderError.notConnected("Couldn’t access Claude Code credentials")
        }

        do {
            return try Self.parseCredentials(Data(contentsOf: credentialsFileURL))
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.notConnected(
                "Couldn’t read Claude Code credentials — sign in again"
            )
        }
    }

    static func parseCredentials(_ data: Data) throws -> ClaudeCredentials {
        do {
            let envelope = try JSONDecoder().decode(CredentialsEnvelope.self, from: data)
            guard let oauth = envelope.claudeAiOauth,
                  !oauth.accessToken.isEmpty else {
                throw CredentialsParseError.missingOAuthCredentials
            }

            return ClaudeCredentials(
                accessToken: oauth.accessToken,
                expiresAt: oauth.expiresAt.map {
                    Date(timeIntervalSince1970: $0 / 1_000)
                }
            )
        } catch {
            throw UsageProviderError.notConnected(
                "Claude Code credentials are malformed — sign in again"
            )
        }
    }

    private func readKeychain() async throws -> SecurityCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()

            process.executableURL = securityExecutableURL
            process.arguments = securityArguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finishedProcess in
                let result = SecurityCommandResult(
                    data: output.fileHandleForReading.readDataToEndOfFile(),
                    terminationStatus: finishedProcess.terminationStatus,
                    terminationReason: finishedProcess.terminationReason
                )
                finishedProcess.terminationHandler = nil
                continuation.resume(returning: result)
            }

            do {
                try process.run()
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + keychainTimeout
                ) {
                    if process.isRunning {
                        process.terminate()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private struct SecurityCommandResult {
    let data: Data
    let terminationStatus: Int32
    let terminationReason: Process.TerminationReason
}

private struct CredentialsEnvelope: Decodable {
    let claudeAiOauth: OAuthCredentials?
}

private struct OAuthCredentials: Decodable {
    let accessToken: String
    let expiresAt: Double?
}

private enum CredentialsParseError: Error {
    case missingOAuthCredentials
}
