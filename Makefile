# PortMonitor build helpers.
#
# Requires only Xcode Command Line Tools (a full Xcode install is not needed).

APP_NAME  := PortMonitor
TEST_NAME := PortMonitorCoreTests
RELEASE   := .build/release
BUNDLE    := build/$(APP_NAME).app
ZIP       := build/$(APP_NAME).zip
BUNDLE_ID := com.rahul.PortMonitor
MIN_MACOS := 14.0
ICON_SRC  := Assets/AppIcon.icns

# Code signing.
#   CODESIGN_IDENTITY=-                                             ad-hoc (default)
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)"     for distribution
CODESIGN_IDENTITY ?= -
# Keychain profile for notarytool, created once with:
#   xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#       --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
NOTARY_PROFILE ?= portmonitor-notary

# Set MENUBAR_ONLY=1 to build a Dock-less, menu-bar-only app (LSUIElement).
MENUBAR_ONLY ?= 0

.PHONY: help build test test-xctest run clean bundle notarize

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Compile the app (debug)
	swift build

test: ## Run the dependency-free test suite
	swift run $(TEST_NAME)

test-xctest: ## Run the opt-in XCTest suite (needs a full Xcode install)
	PORTMONITOR_ENABLE_XCTEST=1 swift test

run: ## Build and launch the app
	swift run $(APP_NAME)

bundle: ## Package a Release .app (with icon) into build/
	swift build -c release
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(RELEASE)/$(APP_NAME)" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp "$(ICON_SRC)" "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0">' \
	  '<dict>' \
	  '  <key>CFBundleName</key><string>Port Monitor</string>' \
	  '  <key>CFBundleDisplayName</key><string>Port Monitor</string>' \
	  '  <key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>' \
	  '  <key>CFBundleExecutable</key><string>$(APP_NAME)</string>' \
	  '  <key>CFBundleIconFile</key><string>AppIcon</string>' \
	  '  <key>CFBundlePackageType</key><string>APPL</string>' \
	  '  <key>CFBundleShortVersionString</key><string>1.2.0</string>' \
	  '  <key>CFBundleVersion</key><string>2</string>' \
	  '  <key>LSMinimumSystemVersion</key><string>$(MIN_MACOS)</string>' \
	  '  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>' \
	  '  <key>NSHighResolutionCapable</key><true/>' \
	  '</dict>' \
	  '</plist>' > "$(BUNDLE)/Contents/Info.plist"
	@if [ "$(MENUBAR_ONLY)" = "1" ]; then \
	  /usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$(BUNDLE)/Contents/Info.plist"; \
	  echo "Packaged as menu-bar-only (LSUIElement)"; \
	fi
	@if [ "$(CODESIGN_IDENTITY)" = "-" ]; then \
	  echo "Signing ad-hoc (set CODESIGN_IDENTITY for a Developer ID build)"; \
	  codesign --force --deep --sign - "$(BUNDLE)"; \
	else \
	  codesign --force --deep --options runtime --timestamp --sign "$(CODESIGN_IDENTITY)" "$(BUNDLE)"; \
	fi
	@echo "Built $(BUNDLE)"

notarize: bundle ## Notarize + staple the bundle (needs CODESIGN_IDENTITY + NOTARY_PROFILE)
	@if [ "$(CODESIGN_IDENTITY)" = "-" ]; then \
	  echo "error: set CODESIGN_IDENTITY to a 'Developer ID Application' identity first"; exit 1; \
	fi
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(BUNDLE)" "$(ZIP)"
	xcrun notarytool submit "$(ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(BUNDLE)"
	@echo "Notarized and stapled $(BUNDLE)"

clean: ## Remove build artifacts
	swift package clean
	rm -rf build
