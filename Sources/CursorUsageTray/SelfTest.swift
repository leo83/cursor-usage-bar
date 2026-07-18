import Foundation

enum SelfTest {
    static let sample = """
    {
      "billingCycleStart": "1782950400000",
      "billingCycleEnd": "1785628800000",
      "planUsage": {
        "totalSpend": 980,
        "includedSpend": 980,
        "bonusSpend": 0,
        "remaining": 6020,
        "limit": 7000,
        "autoPercentUsed": 1,
        "apiPercentUsed": 14,
        "totalPercentUsed": 7
      },
      "spendLimitUsage": {
        "totalSpend": 0,
        "individualLimit": 5000,
        "individualUsed": 0,
        "individualRemaining": 5000,
        "limitType": "user"
      }
    }
    """

    static func run() {
        guard let data = sample.data(using: .utf8) else {
            print("selftest: FAIL: sample encoding")
            exit(1)
        }
        do {
            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            let bars = decoded.bars
            print("selftest: decoded \(bars.count) bars")
            precondition(bars.count == 3, "expected 3 bars")
            precondition(bars[0].kind == "first_party_models")
            precondition(bars[1].kind == "api")
            precondition(bars[2].kind == "on_demand")
            precondition(bars[0].letter == "f" && bars[1].letter == "a" && bars[2].letter == "o")
            precondition(Int(bars[0].percent.rounded()) == 1)
            precondition(Int(bars[1].percent.rounded()) == 14)
            precondition(Int(bars[2].percent.rounded()) == 0)
            precondition(bars[2].valueText == "$0 / $50")

            for bar in bars {
                let extra = bar.valueText.map { "  \($0)" } ?? ""
                print("  \(bar.label): \(Int(bar.percent.rounded()))%\(extra)  severity=\(bar.severity)")
            }

            let blocked = BarSpec(kind: "api", label: "API", letter: "a", percent: 100, severity: "critical", resetsAt: nil, valueText: nil)
            precondition(blocked.isBlocking, "100% must block")
            let warning = BarSpec(kind: "api", label: "API", letter: "a", percent: 90, severity: "critical", resetsAt: nil, valueText: nil)
            precondition(!warning.isBlocking, "critical below 100% is warning")
            precondition(UsageError.http(429).isTransient, "429 is transient")
            precondition(UsageError.http(503).isTransient, "5xx is transient")
            precondition(UsageError.network("x").isTransient, "network is transient")
            precondition(!UsageError.unauthorized.isTransient, "auth errors are actionable")
            precondition(!UsageError.noToken.isTransient, "no-token is actionable")

            for mono in [true, false] {
                for icon in [true, false] {
                    for letters in [true, false] {
                        precondition(BarsRenderer.image(for: bars, monochrome: mono, showLetters: letters, showIcon: icon, countdown: nil).tiffRepresentation != nil)
                    }
                    precondition(BarsRenderer.image(for: bars, monochrome: mono, showLetters: true, showIcon: icon, countdown: "1:23").tiffRepresentation != nil)
                    precondition(BarsRenderer.placeholder(monochrome: mono, showLetters: true, showIcon: icon).tiffRepresentation != nil)
                }
            }
            print("selftest: render OK")
            print("selftest: OK")
        } catch {
            print("selftest: FAIL: \(error)")
            exit(1)
        }
    }

    static func probe() {
        let rawURL = Settings.proxyURL
        let scheme = rawURL.contains("://") ? String(rawURL.prefix(while: { $0 != "/" })) : "(none)"
        let hostTail = rawURL.components(separatedBy: "@").last ?? ""
        print("probe: bundleID = \(Bundle.main.bundleIdentifier ?? "nil")")
        print("probe: endpoint = \(Settings.usageEndpoint)")
        print("probe: proxyEnabled = \(Settings.proxyEnabled), proxyURL.len = \(rawURL.count), scheme = \(scheme), hostTail = \(hostTail)")

        Settings.adoptEnvProxyIfEmpty()
        let token = Credentials.accessToken()
        print("probe: token present = \(token != nil), length = \(token?.count ?? -1)")
        if let proxy = Settings.activeProxy {
            let auth = proxy.username != nil ? " (auth: \(proxy.username!):***)" : ""
            print("probe: proxy = \(proxy.host):\(proxy.port)\(auth)")
        } else {
            print("probe: proxy = none")
        }

        var done = false
        UsageClient().fetch { result in
            switch result {
            case .success(let bars):
                print("probe: OK: \(bars.count) bars")
                for bar in bars {
                    let extra = bar.valueText.map { "  \($0)" } ?? ""
                    print("  \(bar.label): \(Int(bar.percent.rounded()))%\(extra) (\(bar.severity))")
                }
            case .failure(let error):
                print("probe: FAIL: \(error.localizedDescription)")
            }
            done = true
        }
        let deadline = Date().addingTimeInterval(30)
        while !done && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
        }
    }

    static func probeLoop(count: Int) {
        Settings.adoptEnvProxyIfEmpty()
        if let proxy = Settings.activeProxy {
            print("probe-loop: proxy = \(proxy.host):\(proxy.port) auth=\(proxy.username != nil)")
        } else {
            print("probe-loop: proxy = none")
        }
        let client = UsageClient()
        var connected = 0
        var net = 0
        for i in 1...count {
            var done = false
            client.fetchOnce { result in
                switch result {
                case .success:
                    connected += 1
                    print("  #\(i): OK")
                case .failure(let err):
                    if case .network(let msg) = err {
                        net += 1
                        print("  #\(i): net: \(msg)")
                    } else {
                        connected += 1
                        print("  #\(i): connected: \(err.localizedDescription)")
                    }
                }
                done = true
            }
            let deadline = Date().addingTimeInterval(25)
            while !done && Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(1.0))
        }
        print("probe-loop: connected=\(connected) network=\(net) of \(count)")
    }
}
