.PHONY: build run app install launch login unlogin clean selftest probe probe-loop

APP_BIN := /Applications/CursorUsageTray.app/Contents/MacOS/CursorUsageTray

build:
	swift build

run: build
	./.build/debug/CursorUsageTray

selftest: build
	./.build/debug/CursorUsageTray --selftest

probe: build
	./.build/debug/CursorUsageTray --probe

probe-loop: build
	./.build/debug/CursorUsageTray --probe-loop 20

app:
	bash scripts/bundle.sh

install: app
	-killall CursorUsageTray 2>/dev/null || true
	rm -rf /Applications/CursorUsageTray.app
	cp -R .build/CursorUsageTray.app /Applications/
	@echo "Установлено: /Applications/CursorUsageTray.app  (open -a CursorUsageTray)"

launch:
	open -a CursorUsageTray

# Устанавливает .app и регистрирует автозапуск при входе (SMAppService).
# Регистрация выполняется из УСТАНОВЛЕННОГО бинарника, поэтому login item
# указывает на /Applications/CursorUsageTray.app, а не на debug-сборку.
login: install
	"$(APP_BIN)" --register-login
	open -a CursorUsageTray
	@echo "Автозапуск включён (login item -> /Applications/CursorUsageTray.app)."

# Отключает автозапуск при входе.
unlogin:
	-"$(APP_BIN)" --unregister-login 2>/dev/null || true
	@echo "Автозапуск выключен."

clean:
	swift package clean
	rm -rf .build/CursorUsageTray.app
