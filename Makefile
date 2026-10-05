# MiniGolf.app 조립·배포 (PLAN.md: SPM + Makefile로 .app — .xcodeproj 없이)
#   make app  → dist/MiniGolf.app (유니버설: arm64 + x86_64)
#   make zip  → dist/MiniGolf-$(VERSION).zip (Release 업로드용)

VERSION := 0.8.9
APP     := dist/MiniGolf.app
BUILD   := swift build -c release --arch arm64 --arch x86_64

.PHONY: app zip release clean

release:
	$(BUILD)

# 실행 파일 경로는 빌드 도구에 묻는다(--show-bin-path). 고정 경로(.build/apple/Products/Release)는 Swift 6.4에서
# .build/out/Products/Release로 바뀌었고, 그때 빌드는 성공하는데 옛 폴더에 남아 있던 실행 파일이 앱에 들어갔다
# (2026-10-05 발견 — 그대로 릴리스했다면 옛 버전이 새 번호로 나갔다). 소스보다 오래된 실행 파일이면 조립을 멈춘다
app: release
	@BIN="$$($(BUILD) --show-bin-path)/MiniGolf"; \
	if [ ! -f "$$BIN" ]; then echo "ERROR: 실행 파일이 없다: $$BIN"; exit 1; fi; \
	if [ -n "$$(find Sources Package.swift -newer "$$BIN" -print -quit)" ]; then \
		echo "ERROR: $$BIN 이 소스보다 오래됐다 — 빌드 산출물 경로가 또 바뀌었나?"; exit 1; fi; \
	echo "bin $$BIN"; \
	rm -rf $(APP) && mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources && cp "$$BIN" $(APP)/Contents/MacOS/MiniGolf
	cp assets/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	sed 's/@VERSION@/$(VERSION)/g' assets/Info.plist > $(APP)/Contents/Info.plist
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	plutil -lint $(APP)/Contents/Info.plist
	@echo "OK $(APP)"

zip: app
	rm -f dist/MiniGolf-$(VERSION).zip
	ditto -c -k --sequesterRsrc --keepParent $(APP) dist/MiniGolf-$(VERSION).zip
	@shasum -a 256 dist/MiniGolf-$(VERSION).zip

clean:
	rm -rf dist .build/apple .build/out
