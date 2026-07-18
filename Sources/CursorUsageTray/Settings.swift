import Foundation

enum Settings {
    private static let d = UserDefaults.standard

    private enum Key {
        static let proxyEnabled = "proxyEnabled"
        static let proxyURL = "proxyURL"
        static let usageEndpoint = "usageEndpoint"
        static let pollSeconds = "pollSeconds"
        static let monochrome = "monochrome"
        static let showLetters = "showLetters"
        static let showIcon = "showIcon"
        static let displayTimeZone = "displayTimeZone"
    }

    static let defaultUsageEndpoint = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    private static let legacyUsageEndpoints = [
        "https://www.cursor.com/api/dashboard/get-usage",
        "https://cursor.com/api/dashboard/get-usage",
    ]

    static var usageEndpoint: String {
        get {
            let saved = d.string(forKey: Key.usageEndpoint) ?? ""
            return saved.isEmpty || legacyUsageEndpoints.contains(saved) ? defaultUsageEndpoint : saved
        }
        set { d.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.usageEndpoint) }
    }

    static var fallbackUsageEndpoints: [String] {
        [
            usageEndpoint,
            defaultUsageEndpoint,
            "https://api2.cursor.sh/auth/usage",
        ].reduce(into: []) { result, endpoint in
            if !result.contains(endpoint) { result.append(endpoint) }
        }
    }

    static var monochrome: Bool {
        get { d.object(forKey: Key.monochrome) == nil ? true : d.bool(forKey: Key.monochrome) }
        set { d.set(newValue, forKey: Key.monochrome) }
    }

    static var showLetters: Bool {
        get { d.object(forKey: Key.showLetters) == nil ? true : d.bool(forKey: Key.showLetters) }
        set { d.set(newValue, forKey: Key.showLetters) }
    }

    static var showIcon: Bool {
        get { d.object(forKey: Key.showIcon) == nil ? true : d.bool(forKey: Key.showIcon) }
        set { d.set(newValue, forKey: Key.showIcon) }
    }

    static var displayTimeZoneID: String {
        get { d.string(forKey: Key.displayTimeZone) ?? "" }
        set { d.set(newValue, forKey: Key.displayTimeZone) }
    }

    static var displayTimeZone: TimeZone {
        if !displayTimeZoneID.isEmpty, let tz = TimeZone(identifier: displayTimeZoneID) {
            return tz
        }
        return .autoupdatingCurrent
    }

    static var proxyEnabled: Bool {
        get { d.bool(forKey: Key.proxyEnabled) }
        set { d.set(newValue, forKey: Key.proxyEnabled) }
    }

    static var proxyURL: String {
        get { d.string(forKey: Key.proxyURL) ?? "" }
        set { d.set(newValue, forKey: Key.proxyURL) }
    }

    static var pollSeconds: Int {
        get {
            let v = d.integer(forKey: Key.pollSeconds)
            return v <= 0 ? 60 : max(15, v)
        }
        set { d.set(max(15, newValue), forKey: Key.pollSeconds) }
    }

    static func adoptEnvProxyIfEmpty() {
        guard ProxyConfig(urlString: proxyURL) == nil else { return }
        if let envProxy = ProxyEnv.current() {
            proxyURL = envProxy
            proxyEnabled = true
        }
    }

    static var activeProxy: ProxyConfig? {
        guard proxyEnabled, !proxyURL.isEmpty else { return nil }
        return ProxyConfig(urlString: proxyURL)
    }
}
