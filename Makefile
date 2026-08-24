# MiniGolf.app 조립·배포 (PLAN.md: SPM + Makefile로 .app — .xcodeproj 없이)
#   make app  → dist/MiniGolf.app (유니버설: arm64 + x86_64)
#   make zip  → dist/MiniGolf-$(VERSION).zip (Release 업로드용)

VERSION := 0.3.0
APP     := dist/MiniGolf.app
BIN     := .build/apple/Products/Release/MiniGolf

.PHONY: app zip release clean

release:
	swift build -c release --arch arm64 --arch x86_64

app: release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/MiniGolf
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
	rm -rf dist .build/apple
