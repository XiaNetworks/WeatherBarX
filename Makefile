APP_NAME := WeatherBarX
PROJECT := weatherX.xcodeproj
SCHEME := weatherX
CONFIGURATION := Debug
DERIVED_DATA := /tmp/$(APP_NAME)DerivedData
BUILD_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: all build test install clean

all: test install

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) build

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) test

install: build
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED_APP)"
	cp -R "$(BUILD_APP)" "$(INSTALLED_APP)"

clean:
	rm -rf "$(DERIVED_DATA)"
