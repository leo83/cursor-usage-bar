import AppKit

if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
    exit(0)
}

if CommandLine.arguments.contains("--probe") {
    SelfTest.probe()
    exit(0)
}

if let idx = CommandLine.arguments.firstIndex(of: "--probe-loop") {
    let count = (idx + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[idx + 1]) : nil) ?? 20
    SelfTest.probeLoop(count: count)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
