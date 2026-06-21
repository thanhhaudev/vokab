# vokab — local dev tasks
#
# Quick start:
#   make run        # build + (re)launch the app
#   make open       # just launch the last build (no rebuild)
#
# The app is a menubar agent (LSUIElement) — after launch it lives in the
# menubar, not the Dock. Click its menubar icon to open the Library/capture.

PROJECT  := App/vokab.xcodeproj
SCHEME   := vokab
CONFIG   := Debug
DERIVED  := build
APP      := $(DERIVED)/Build/Products/$(CONFIG)/vokab.app
INSTALLED := /Applications/vokab.app

.PHONY: all run build open kill restart generate test clean help install

all: build

## generate: regenerate the Xcode project from App/project.yml (xcodegen)
generate:
	cd App && xcodegen generate

## build: compile the app (generates the project first if missing)
build:
	@[ -d "$(PROJECT)" ] || $(MAKE) generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO build -quiet

## run: build, then quit any running instance and relaunch
run: build restart

## install: build, copy into /Applications, and relaunch from there
##   Quick Capture's synthetic-⌘C auto-grab needs Accessibility, which macOS
##   ties to the binary's identity+location. Always run the /Applications copy
##   — the DerivedData build is a different (untrusted) binary, so auto-grab
##   silently fails there. After a rebuild changes the code hash you must
##   re-grant: System Settings → Privacy & Security → Accessibility.
install: build kill
	rm -rf "$(INSTALLED)"
	cp -R "$(APP)" "$(INSTALLED)"
	@echo "Installed to $(INSTALLED)"
	open "$(INSTALLED)"

## restart: quit the running app and launch the latest build (no rebuild)
restart: kill open

## open: launch the latest build without rebuilding
open:
	@[ -d "$(APP)" ] || { echo "No build found — run 'make build' first."; exit 1; }
	open "$(APP)"

## kill: quit the running app (no-op if not running)
kill:
	@pkill -x vokab 2>/dev/null && sleep 0.3 || true

## test: run the offline unit tests (VokabKit)
test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO test -quiet

## clean: remove the local build directory
clean:
	rm -rf $(DERIVED)

## help: list the available targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
