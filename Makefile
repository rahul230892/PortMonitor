# PortMonitorTest build helpers.
#
# Requires only Xcode Command Line Tools (a full Xcode install is not needed).

APP_NAME  := PortMonitorTest
TEST_NAME := PortMonitorCoreTests
RELEASE   := .build/release
BUNDLE    := build/$(APP_NAME).app
BUNDLE_ID := com.example.portmonitor
MIN_MACOS := 14.0

.PHONY: help build test run clean bundle

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

build: ## Compile the app (debug)
	swift build

test: ## Run the test suite
	swift run $(TEST_NAME)

run: ## Build and launch the app
	swift run $(APP_NAME)

bundle: ## Package a Release .app into build/
	swift build -c release
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS"
	cp "$(RELEASE)/$(APP_NAME)" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0">' \
	  '<dict>' \
	  '  <key>CFBundleName</key><string>Port Monitor</string>' \
	  '  <key>CFBundleDisplayName</key><string>Port Monitor</string>' \
	  '  <key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>' \
	  '  <key>CFBundleExecutable</key><string>$(APP_NAME)</string>' \
	  '  <key>CFBundlePackageType</key><string>APPL</string>' \
	  '  <key>CFBundleShortVersionString</key><string>1.0</string>' \
	  '  <key>CFBundleVersion</key><string>1</string>' \
	  '  <key>LSMinimumSystemVersion</key><string>$(MIN_MACOS)</string>' \
	  '  <key>NSHighResolutionCapable</key><true/>' \
	  '</dict>' \
	  '</plist>' > "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign - "$(BUNDLE)"
	@echo "Built $(BUNDLE)"

clean: ## Remove build artifacts
	swift package clean
	rm -rf build
