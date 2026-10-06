# Swarm screensaver for macOS
#
#   make           build build/Swarm.saver (universal: Apple silicon + Intel)
#   make preview   watch it in a window, no install needed (Escape quits)
#   make frames    run it offscreen and write PNGs plus a wasp-path trace
#   make preview-full  the same, filling the screen
#   make zip       build, then wrap it up for copying to another Mac
#   make install   build, then copy it into ~/Library/Screen Savers
#   make reinstall install, then clear the caches that keep the old build alive
#   make uninstall remove it from ~/Library/Screen Savers
#   make clean     delete the build directory

NAME       := Swarm
BUNDLE     := build/$(NAME).saver
SOURCES    := $(wildcard Sources/*.swift)
DEPLOY     := 11.0
ARCHS      := arm64 x86_64
SDK        := $(shell xcrun --show-sdk-path)
TOOLCHAIN  := $(shell dirname $(shell xcrun --find swiftc))/../lib/swift/macosx
INSTALLDIR := $(HOME)/Library/Screen Savers
SWIFTFLAGS := -O -wmo -module-name $(NAME) -sdk "$(SDK)" -swift-version 5

.PHONY: all preview preview-full frames bench zip install reinstall uninstall clean

all: $(BUNDLE)

$(BUNDLE): $(SOURCES) Resources/Info.plist Makefile
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	@for arch in $(ARCHS); do \
		echo "  compiling $$arch"; \
		mkdir -p build/$$arch; \
		xcrun swiftc $(SWIFTFLAGS) -target $$arch-apple-macos$(DEPLOY) \
			-c $(SOURCES) -o build/$$arch/$(NAME).o || exit 1; \
		xcrun clang -bundle -target $$arch-apple-macos$(DEPLOY) -isysroot "$(SDK)" \
			-L"$(SDK)/usr/lib/swift" -L/usr/lib/swift -L"$(TOOLCHAIN)" \
			-Xlinker -rpath -Xlinker /usr/lib/swift \
			-framework AppKit -framework ScreenSaver \
			build/$$arch/$(NAME).o -o build/$$arch/$(NAME) || exit 1; \
	done
	@xcrun lipo -create $(foreach a,$(ARCHS),build/$(a)/$(NAME)) \
		-output "$(BUNDLE)/Contents/MacOS/$(NAME)"
	@cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$(date +%Y%m%d.%H%M%S)" \
		"$(BUNDLE)/Contents/Info.plist"
	@printf 'BNDL????' > "$(BUNDLE)/Contents/PkgInfo"
	@codesign --force --sign - "$(BUNDLE)"
	@echo "built $(BUNDLE)"

# Watch the saver in a normal window, without installing it.
preview: build/preview $(BUNDLE)
	@build/preview "$(BUNDLE)"

# The same, filling the screen. Press Escape to quit.
preview-full: build/preview $(BUNDLE)
	@build/preview "$(BUNDLE)" --fullscreen

# Render stills and a wasp-path trace offscreen, without taking over the screen.
frames: build/render $(BUNDLE)
	@build/render "$(BUNDLE)" build/frames --seconds 90 --shots 5,20,60

bench: build/render $(BUNDLE)
	@build/render "$(BUNDLE)" build/frames --seconds 8 --bench

build/render: Tools/Render.swift
	@mkdir -p build
	@xcrun swiftc -O -sdk "$(SDK)" Tools/Render.swift -o build/render

build/preview: Tools/Preview.swift
	@mkdir -p build
	@xcrun swiftc -O -sdk "$(SDK)" Tools/Preview.swift -o build/preview

# The saver is signed ad hoc rather than notarised, so if the copy on the other
# Mac picks up a quarantine flag, which AirDrop, Mail and any download will set,
# Gatekeeper refuses to load it and the saver simply never appears. Copying over
# a USB disk, scp or rsync does not set it. If in doubt, run this on the other
# Mac after copying:
#     xattr -dr com.apple.quarantine ~/Library/Screen\ Savers/$(NAME).saver
zip: $(BUNDLE)
	@rm -f build/$(NAME).saver.zip
	@ditto -c -k --sequesterRsrc --keepParent "$(BUNDLE)" build/$(NAME).saver.zip
	@echo "wrote build/$(NAME).saver.zip"
	@echo "copy it over, unzip into ~/Library/Screen Savers, then if it does not"
	@echo "show up: xattr -dr com.apple.quarantine ~/Library/Screen\ Savers/$(NAME).saver"

install: $(BUNDLE)
	@mkdir -p "$(INSTALLDIR)"
	@rm -rf "$(INSTALLDIR)/$(NAME).saver"
	@cp -R "$(BUNDLE)" "$(INSTALLDIR)/"
	@echo "installed to $(INSTALLDIR)/$(NAME).saver"
	@echo "open System Settings > Screen Saver and pick Swarm"

# Install over a copy macOS has already loaded. The saver runs inside a host
# process that caches the bundle, and System Settings caches it again, so both
# have to go or you keep watching the previous build.
reinstall: install
	@killall legacyScreenSaver 2>/dev/null || true
	@osascript -e 'quit app id "com.apple.systempreferences"' 2>/dev/null || true
	@echo "restarted the screen saver host and quit System Settings"
	@echo "reopen System Settings > Screen Saver and pick Swarm again"

uninstall:
	@rm -rf "$(INSTALLDIR)/$(NAME).saver"
	@echo "removed $(INSTALLDIR)/$(NAME).saver"

clean:
	@rm -rf build
