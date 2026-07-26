SHELL := /bin/bash

PROJECT := JustSpeak.xcodeproj
SCHEME := JustSpeak
CONFIGURATION ?= Debug
DERIVED_DATA := build
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/JustSpeak.app

.PHONY: parakeet build run open clean rebuild

parakeet:
	./setup-parakeet.sh

build:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -derivedDataPath "$(DERIVED_DATA)" build

run: build
	open "$(APP_PATH)"

open:
	open "$(APP_PATH)"

clean:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -derivedDataPath "$(DERIVED_DATA)" clean
	rm -rf "$(DERIVED_DATA)"

rebuild: clean build
