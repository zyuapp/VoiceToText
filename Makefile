SHELL := /bin/bash

PROJECT := JustSpeak.xcodeproj
SCHEME := JustSpeak
CONFIGURATION ?= Debug
DERIVED_DATA := build
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/JustSpeak.app
INSTALL_PATH := /Applications/JustSpeak.app
XCODE_DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: parakeet build release run open install clean-debug-apps clean rebuild

parakeet:
	./setup-parakeet.sh

build:
	mkdir -p "$(DERIVED_DATA)"
	touch "$(DERIVED_DATA)/.metadata_never_index"
	xcodebuild -quiet -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -derivedDataPath "$(DERIVED_DATA)" build
	./scripts/sign-local.sh "$(APP_PATH)"
	./scripts/verify-local-signing.sh "$(APP_PATH)"

release:
	$(MAKE) build CONFIGURATION=Release

run: build
	open "$(APP_PATH)"

open:
	open "$(APP_PATH)"

install: parakeet release
	pkill -x JustSpeak 2>/dev/null || true
	rm -rf "$(INSTALL_PATH)"
	ditto "$(DERIVED_DATA)/Build/Products/Release/JustSpeak.app" "$(INSTALL_PATH)"
	$(MAKE) clean-debug-apps
	rm -rf "$(DERIVED_DATA)/Build/Products/Release/JustSpeak.app"
	open "$(INSTALL_PATH)"

clean-debug-apps:
	rm -rf "$(DERIVED_DATA)/Build/Products/Debug/JustSpeak.app"
	if [ -d "$(XCODE_DERIVED_DATA)" ]; then find "$(XCODE_DERIVED_DATA)" -type d -path "*/Build/Products/Debug/JustSpeak.app" -prune -exec rm -rf {} +; fi

clean:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -derivedDataPath "$(DERIVED_DATA)" clean
	rm -rf "$(DERIVED_DATA)"

rebuild: clean build
