.PHONY: build run app install launch clean selftest probe probe-loop

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

clean:
	swift package clean
	rm -rf .build/CursorUsageTray.app
