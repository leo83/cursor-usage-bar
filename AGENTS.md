# AGENTS.md

Инструкции для AI-агентов и разработчиков, работающих с репозиторием
**cursor-usage-tray**. Человеческое onboarding находится в [README.md](README.md).

## Назначение проекта

Нативное macOS-приложение для menu bar. Показывает три Cursor usage-бакета:
`First-party models`, `API`, `On-demand`. При наведении показывает tooltip, по
клику открывает меню с деталями и действиями.

## Архитектура

```text
main.swift -> AppDelegate (NSStatusItem, Timer, меню, tooltip)
                    |
                    v
              UsageClient.fetch -> Cursor usage endpoint
                    |              Authorization + proxy
                    |
              UsageResponse / UsageMapper -> [BarSpec] -> BarsRenderer -> NSImage
```

Приложение работает как accessory app без Dock-иконки: `NSApp.setActivationPolicy(.accessory)`
в `main.swift`, `LSUIElement=true` в bundle `Info.plist`.

## Стек

| Часть | Технологии |
|-------|------------|
| Язык | Swift 5.9+, target macOS 13 |
| UI | AppKit: `NSStatusItem`, `NSMenu`, `NSWindow`, `NSGridView` |
| Сеть | `URLSession` с `ephemeral` configuration |
| Прокси | `connectionProxyDictionary` и `URLSessionTaskDelegate` для 407 |
| Автозапуск | `ServiceManagement` / `SMAppService`, нужен `.app` bundle |
| Сборка | Swift Package Manager, `Makefile`, `scripts/bundle.sh` |

## Ключевые файлы

| Путь | Назначение |
|------|------------|
| `main.swift` | Entry point, флаги `--selftest`, `--probe`, `--probe-loop` |
| `AppDelegate.swift` | Status item, refresh timer, menu, tooltip, launch at login |
| `UsageClient.swift` | HTTP-запросы, retries, proxy, mapping ошибок |
| `UsageModels.swift` | Гибкий JSON parser Cursor usage и `BarSpec` |
| `Credentials.swift` | Env, JSON-файлы и Keychain для Cursor token |
| `BarsRenderer.swift` | Cursor mark, три столбика, буквы, countdown |
| `Settings.swift` | `UserDefaults`: endpoint, proxy, poll interval, icon style |
| `ProxyEnv.swift` | Автоподхват proxy из process env и login shell |
| `SettingsWindowController.swift` | Окно настроек |
| `SelfTest.swift` | Headless selftest и live probe |
| `scripts/bundle.sh` | Universal `.app`, `Info.plist`, ad-hoc codesign |

## Источник данных

- Default endpoint: `https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`.
- Protocol: Connect RPC v1 JSON over HTTP (`POST {}`, `Connect-Protocol-Version: 1`).
- Endpoint настраивается в UI через `Settings.usageEndpoint`.
- `UsageClient` также пробует fallback endpoints из `Settings.fallbackUsageEndpoints`.
- Cursor usage API не считается стабильным публичным контрактом. При изменении
  JSON править сначала `UsageModels.swift`, потом обновлять `SelfTest.swift`,
  `README.md` и этот файл.
- Канонический порядок баров фиксирован: `first_party_models`, `api`, `on_demand`.

## Токены и секреты

- Никогда не печатать и не логировать токены или proxy passwords.
- `--probe` должен печатать только факт наличия токена и длину.
- Источники токена по порядку:
  1. Env: `CURSOR_API_KEY`, `CURSOR_TOKEN`, `CURSOR_ACCESS_TOKEN`,
     `CURSOR_SESSION_TOKEN`.
  2. Cursor IDE storage: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`,
     key `cursorAuth/accessToken`.
  3. Keychain item приложения `Cursor Usage Tray-token`.
  4. JSON-файлы `~/.cursor/credentials.json`, `~/.cursor/auth.json`,
     `~/.cursor/cursor-auth.json`, `~/.cursor/cli-auth.json`.
  5. Cursor-looking Keychain service names.
- Токен, введённый в Settings, сохраняется в Keychain. Не переносить его в
  `UserDefaults`.

## Прокси

- Proxy URL хранится как полный URL в формате `HTTPS_PROXY`.
- Если сохранённый proxy URL пустой или невалидный, приложение пробует взять
  proxy из process env, затем из login shell.
- Аутентификация proxy идёт через `ProxyAuthDelegate`. TLS/server trust должен
  уходить в default handling.

## UI-инварианты

- Рисуется ровно три столбика в порядке `f`, `a`, `o`.
- В монохромном режиме `NSImage.isTemplate = true`.
- В цветном режиме `NSImage.isTemplate = false`, иначе macOS уничтожит цвета.
- `critical` ниже 100% не считается блокировкой. Countdown включается только
  при `percent >= 100` или явной exhausted/blocked severity.
- Transient ошибки не должны стирать последнее успешное чтение. Показывать
  stale note в tooltip/menu.

## Команды

```bash
make selftest
make probe
swift build
make run
make app
make install
make login      # install + регистрация автозапуска (SMAppService), из установленного .app
make unlogin    # снять автозапуск
```

Автозапуск: `SMAppService.mainApp` регистрирует _бандл_, в котором лежит
работающий бинарник. Поэтому регистрировать нужно из
`/Applications/CursorUsageTray.app` (что и делает `make login`), а не из
`.build/...` — иначе login item укажет на debug-бинарник и запустится
терминал-стайл. CLI-флаги: `--register-login` / `--unregister-login`.

Перед завершением значимых изменений запускайте минимум:

```bash
make selftest
swift build
```

Если меняется источник данных, parser или авторизация, дополнительно запускайте
`make probe`, когда есть валидный токен.
