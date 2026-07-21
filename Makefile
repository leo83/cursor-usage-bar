.PHONY: build run app install launch login unlogin uninstall clean selftest probe probe-loop

APP := /Applications/CursorUsageTray.app

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

# Автозапуск при входе через переносимый per-user LaunchAgent.
# plist генерируется из bundle id/пути установленного .app — ничего
# машинно-специфичного не коммитится.
login: install
	bash scripts/loginitem.sh on "$(APP)"
	open -a CursorUsageTray

unlogin:
	-bash scripts/loginitem.sh off "$(APP)" 2>/dev/null || true

# Полное удаление: снять автозапуск и убрать .app из /Applications.
uninstall:
	-bash scripts/loginitem.sh off "$(APP)" 2>/dev/null || true
	-killall CursorUsageTray 2>/dev/null || true
	rm -rf "$(APP)"
	@echo "Удалено: $(APP) и автозапуск сняты."

clean:
	swift package clean
	rm -rf .build/CursorUsageTray.app
