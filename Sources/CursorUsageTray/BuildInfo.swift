import AppKit

enum BuildInfo {
    private static let fallbackVersion = "0.1.0"

    static var gitHash: String {
        if let h = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String,
           !h.isEmpty {
            return h
        }
        return gitHashFromWorkingTree() ?? "dev"
    }

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? fallbackVersion
    }

    static var display: String { "v\(version) (\(gitHash))" }

    static func copyHashToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(gitHash, forType: .string)
    }

    private static func gitHashFromWorkingTree() -> String? {
        guard let hash = runGit(["rev-parse", "--short", "HEAD"]), !hash.isEmpty else {
            return nil
        }
        let isDirty = runGit(["diff", "--quiet"]) == nil
        return isDirty ? "\(hash)+" : hash
    }

    private static func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardError = Pipe()

        let out = Pipe()
        process.standardOutput = out

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
