import Foundation

/// Reads a Cursor API/session token without ever logging the token value.
///
/// Sources, in priority order:
/// 1. environment variables (`CURSOR_API_KEY`, `CURSOR_TOKEN`, `CURSOR_ACCESS_TOKEN`);
/// 2. Cursor IDE's `cursorAuth/accessToken` from VS Code-style global storage;
/// 3. the app's own Keychain item, written from Settings;
/// 4. a few common Cursor-looking JSON files and Keychain service names.
enum Credentials {
    static let manualKeychainService = "Cursor Usage Tray-token"
    private static let keychainAccount = "default"

    private static let envKeys = [
        "CURSOR_API_KEY",
        "CURSOR_TOKEN",
        "CURSOR_ACCESS_TOKEN",
        "CURSOR_SESSION_TOKEN",
    ]

    private static let keychainServices = [
        manualKeychainService,
        "Cursor-credentials",
        "Cursor Code-credentials",
        "Cursor-credentials-token",
        "Cursor Auth",
        "Cursor",
    ]

    static func accessToken() -> String? {
        tokenFromEnv() ?? tokenFromCursorStateDB() ?? tokenFromFiles() ?? tokenFromKeychain()
    }

    static func saveManualToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return runSecurity([
            "add-generic-password",
            "-U",
            "-s", manualKeychainService,
            "-a", keychainAccount,
            "-w", trimmed,
        ]).ok
    }

    static func deleteManualToken() -> Bool {
        let result = runSecurity([
            "delete-generic-password",
            "-s", manualKeychainService,
            "-a", keychainAccount,
        ])
        return result.ok || result.output.contains("could not be found")
    }

    // MARK: - Environment

    private static func tokenFromEnv() -> String? {
        if let value = tokenFromProcessEnv() { return value }
        return tokenFromLoginShell()
    }

    private static func tokenFromProcessEnv() -> String? {
        let env = ProcessInfo.processInfo.environment
        for key in envKeys {
            if let value = cleanToken(env[key]) { return value }
        }
        return nil
    }

    private static func tokenFromLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let expr = "printf %s \"${CURSOR_API_KEY:-${CURSOR_TOKEN:-${CURSOR_ACCESS_TOKEN:-${CURSOR_SESSION_TOKEN:-}}}}\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", expr]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        return cleanToken(String(data: data, encoding: .utf8))
    }

    // MARK: - Files

    private static func tokenFromCursorStateDB() -> String? {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let query = "select value from ItemTable where key = 'cursorAuth/accessToken' limit 1;"
        let result = runProcess(
            executable: "/usr/bin/sqlite3",
            arguments: ["-readonly", path, query]
        )
        guard result.ok else { return nil }
        return cleanToken(result.output)
    }

    private static func tokenFromFiles() -> String? {
        let home = NSHomeDirectory()
        let paths = [
            "\(home)/.cursor/credentials.json",
            "\(home)/.cursor/auth.json",
            "\(home)/.cursor/cursor-auth.json",
            "\(home)/.cursor/cli-auth.json",
        ]

        for path in paths {
            guard let data = FileManager.default.contents(atPath: path),
                  let token = token(fromJSON: data) else { continue }
            return token
        }
        return nil
    }

    // MARK: - Keychain

    private static func tokenFromKeychain() -> String? {
        for service in keychainServices {
            let result = runProcess(executable: "/usr/bin/security", arguments: ["find-generic-password", "-s", service, "-w"])
            guard result.ok, let rawToken = cleanToken(result.output) else { continue }
            if rawToken.hasPrefix("{"), let data = rawToken.data(using: .utf8),
               let parsed = token(fromJSON: data) {
                return parsed
            }
            return rawToken
        }
        return nil
    }

    private static func runSecurity(_ arguments: [String]) -> (ok: Bool, output: String) {
        runProcess(executable: "/usr/bin/security", arguments: arguments)
    }

    private static func runProcess(executable: String, arguments: [String]) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return (false, "")
        }
        process.waitUntilExit()

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, stdout + stderr)
    }

    // MARK: - Shared parsing

    private static func token(fromJSON data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return token(fromJSONObject: obj)
    }

    private static func token(fromJSONObject obj: Any) -> String? {
        if let dict = obj as? [String: Any] {
            for key in ["accessToken", "access_token", "token", "apiKey", "api_key", "authToken", "sessionToken"] {
                if let token = cleanToken(dict[key] as? String) { return token }
            }
            for child in dict.values {
                if let token = token(fromJSONObject: child) { return token }
            }
        } else if let array = obj as? [Any] {
            for child in array {
                if let token = token(fromJSONObject: child) { return token }
            }
        }
        return nil
    }

    private static func cleanToken(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
