APP      := noiser.app
BIN      := .build/release/noiser
CONTENTS := $(APP)/Contents
# Per-user; Spotlight and Login Items treat it like /Applications, and it needs no admin rights.
PREFIX   ?= $(HOME)/Applications

.PHONY: all build test bundle run install uninstall clean icon

all: bundle

build:
	swift build -c release

test:
	swift test

# Command Line Tools have no app template, so the bundle is assembled by hand.
bundle: build
	rm -rf $(APP)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources $(CONTENTS)/Resources/Fonts
	cp $(BIN) $(CONTENTS)/MacOS/noiser
	cp Support/Info.plist $(CONTENTS)/Info.plist
	cp Support/noiser.icns $(CONTENTS)/Resources/noiser.icns
	cp Support/Fonts/Archivo.ttf Support/Fonts/OFL.txt $(CONTENTS)/Resources/Fonts/
	printf 'APPL????' > $(CONTENTS)/PkgInfo
	codesign --force --sign - $(APP)

run: bundle
	open $(APP)

install: bundle
	rm -rf $(PREFIX)/$(APP)
	cp -R $(APP) $(PREFIX)/

uninstall:
	rm -rf $(PREFIX)/$(APP)

clean:
	rm -rf .build $(APP)

# Regenerates Support/noiser.icns from the drawing code; only needed after editing make-icon.swift.
icon:
	rm -rf .build/noiser.iconset
	swift Support/make-icon.swift icns tomato .build/noiser.iconset
	iconutil -c icns .build/noiser.iconset -o Support/noiser.icns
