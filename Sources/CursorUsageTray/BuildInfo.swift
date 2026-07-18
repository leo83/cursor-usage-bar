import AppKit

enum BuildInfo {
    static var gitHash: String {
        guard let h = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String,
              !h.isEmpty else { return "dev" }
        return h
    }

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    }

    static var display: String { "v\(version) (\(gitHash))" }

    static func copyHashToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(gitHash, forType: .string)
    }
}
