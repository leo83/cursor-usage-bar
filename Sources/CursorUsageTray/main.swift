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

// Headless login-item management (scriptable from the Makefile / repair steps).
// `--register-login` only works from the installed .app; `--unregister-login`
// removes whatever the running executable previously registered (used to purge
// a stale `.build` binary registration).
if CommandLine.arguments.contains("--register-login") {
    let ok = LoginItem.register()
    print(ok ? "Автозапуск включён для: \(Bundle.main.bundlePath)"
             : "Не удалось включить автозапуск (сборку нужно запускать из .app).")
    exit(ok ? 0 : 1)
}

if CommandLine.arguments.contains("--unregister-login") {
    let ok = LoginItem.unregister()
    print(ok ? "Автозапуск выключен для: \(Bundle.main.bundlePath)"
             : "Не удалось выключить автозапуск.")
    exit(ok ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
