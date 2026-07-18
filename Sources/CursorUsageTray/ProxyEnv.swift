import Foundation

/// Reads an HTTP(S) proxy URL from the environment.
///
/// Apps launched from Finder/Spotlight do not inherit the shell environment, so
/// the fallback asks the login shell for the same proxy variables a terminal has.
enum ProxyEnv {
    private static let keys = [
        "HTTPS_PROXY", "https_proxy",
        "HTTP_PROXY", "http_proxy",
        "ALL_PROXY", "all_proxy",
    ]

    static func current() -> String? {
        if let value = fromProcessEnv() { return value }
        return fromLoginShell()
    }

    private static func fromProcessEnv() -> String? {
        let env = ProcessInfo.processInfo.environment
        for key in keys {
            if let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func fromLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let expr = "printf %s \"${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-${ALL_PROXY:-${all_proxy:-}}}}}}\""

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
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

struct ProxyConfig {
    let host: String
    let port: Int
    let username: String?
    let password: String?

    init?(urlString: String) {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard let comps = URLComponents(string: s),
              let host = comps.host, !host.isEmpty else { return nil }
        self.host = host
        self.port = comps.port ?? 3128
        self.username = comps.user?.isEmpty == false ? comps.user : nil
        self.password = comps.password?.isEmpty == false ? comps.password : nil
    }
}
