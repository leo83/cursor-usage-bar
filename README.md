# Cursor Usage Tray

Небольшое macOS-приложение для menu bar, которое показывает расход лимитов Cursor
тремя живыми столбиками:

- `First-party models`
- `API`
- `On-demand`

При наведении отображается подробный tooltip, по клику открывается меню с теми
же значениями, ручным обновлением, настройками, автозапуском и выходом.

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![arch](https://img.shields.io/badge/binary-universal%20(arm64%2Bx86__64)-blueviolet)
![language](https://img.shields.io/badge/Swift-5.9%2B-orange)
![license](https://img.shields.io/badge/license-Beerware-yellow)

## Возможности

- Три столбика в menu bar: `First-party models`, `API`, `On-demand`.
- Цветной режим с severity-цветами или нативный монохромный template-режим.
- Буквы внутри столбиков: `f`, `a`, `o`.
- Tooltip и меню с процентами, reset time и spend-значениями вроде `$0 / $50`.
- Отсчёт `H:MM`, если один из лимитов достиг 100%.
- Настраиваемый usage endpoint.
- Токен из env, Keychain или JSON-файла.
- HTTP(S)-прокси с авторизацией, включая автоподхват из shell environment.
- Настраиваемый интервал опроса.
- `.app`-bundle с ad-hoc подписью и поддержкой launch at login.

## Быстрый старт

Требования:

- macOS 13 или новее
- Xcode Command Line Tools: `xcode-select --install`
- токен Cursor, доступный одним из способов ниже

Сборка и запуск:

```bash
make run
```

Headless-проверка парсинга и рендера:

```bash
make selftest
```

Живая проверка endpoint:

```bash
make probe
```

## Токен

Приложение ищет токен в таком порядке:

1. Env-переменные `CURSOR_API_KEY`, `CURSOR_TOKEN`, `CURSOR_ACCESS_TOKEN`,
   `CURSOR_SESSION_TOKEN`. При запуске из Finder дополнительно читается login shell.
2. Локальный Cursor storage:
   `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`,
   ключ `cursorAuth/accessToken`.
3. Keychain item `Cursor Usage Tray-token`, который можно сохранить через окно
   настроек.
4. JSON-файлы `~/.cursor/credentials.json`, `~/.cursor/auth.json`,
   `~/.cursor/cursor-auth.json`, `~/.cursor/cli-auth.json`.
5. Несколько Cursor-looking Keychain service names.

`make probe` не печатает токен, только факт наличия и длину.

## Настройки

Откройте menu bar icon -> `Настройки...`.

| Настройка | Описание |
|-----------|----------|
| Прокси URL | Полный URL в формате `HTTPS_PROXY`, например `http://user:pass@host:3128`. |
| Usage endpoint | Internal Cursor dashboard usage endpoint. По умолчанию `https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`. |
| Токен | Если заполнить поле, значение сохраняется в Keychain приложения. Пустое поле не меняет сохранённый токен. |
| Интервал | Период опроса в секундах, минимум 15. |
| Цветные столбики | Включает цветные severity-бары вместо template-иконки. |
| Показывать буквы | Показывает `f` / `a` / `o` внутри столбиков. |
| Часовой пояс | Часовой пояс для reset time. Пустое значение использует системный. |

## Установка

```bash
make install
open -a CursorUsageTray
```

После установки можно включить `Запускать при входе` в меню приложения.

## Сборка bundle

```bash
make app
```

Результат: `.build/CursorUsageTray.app`. Скрипт собирает `arm64` и `x86_64`
отдельно, объединяет через `lipo`, пишет `Info.plist` и подписывает bundle
ad-hoc подписью.

## Диагностика

| Симптом | Что проверить |
|---------|---------------|
| `Токен Cursor не найден` | Задайте `CURSOR_API_KEY`/`CURSOR_TOKEN` или сохраните токен в настройках. |
| `401/403` | Токен истёк, не подходит для endpoint или endpoint ожидает другой тип авторизации. |
| `не найдены usage-бакеты Cursor` | Endpoint ответил JSON, но структура отличается. Нужно обновить `UsageModels.swift` или указать другой endpoint. |
| Proxy `407` | Проверьте логин/пароль в proxy URL. |
| Toggle автозапуска не работает | Используйте установленный `.app` через `make install`, не debug binary. |

## Ограничения

- Cursor usage API не задокументирован как стабильный публичный контракт. Сейчас
  используется internal Connect RPC endpoint `DashboardService/GetCurrentPeriodUsage`;
  endpoint и JSON-структура могут измениться.
- Для неизвестных JSON-форм парсер старается найти бакеты по именам и процентам,
  но при изменении dashboard API может понадобиться адаптация.
- Proxy URL хранится в `UserDefaults` в открытом виде, как обычная shell env
  переменная. Токен, введённый в настройках, хранится в Keychain.

## Структура

```text
Package.swift
Sources/CursorUsageTray/
  main.swift
  AppDelegate.swift
  UsageClient.swift
  UsageModels.swift
  Credentials.swift
  BarsRenderer.swift
  Settings.swift
  ProxyEnv.swift
  SettingsWindowController.swift
  SelfTest.swift
  BuildInfo.swift
scripts/bundle.sh
Makefile
LICENSE
```

## License

[Beerware](LICENSE).
