APP     := AgentStats
BUNDLE  := build/$(APP).pock
SRC     := $(wildcard Sources/*.swift)
# Frameworks come from the Pock workspace build (see ../README.md).
PRODUCTS ?= ../build/Build/Products/Debug
WIDGETS := $(HOME)/Library/Application Support/Pock/Widgets

.PHONY: build install clean

build: $(BUNDLE)

$(BUNDLE): $(SRC) Info.plist
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	swiftc -O -emit-library -module-name $(APP) -target arm64-apple-macos12.0 \
		-F $(PRODUCTS)/PockKit -F $(PRODUCTS)/TinyConstraints -framework PockKit \
		-o $(BUNDLE)/Contents/MacOS/$(APP) $(SRC)
	codesign --force --sign - $(BUNDLE)

# Pock loads widgets only at launch, so restart it.
install: build
	rm -rf "$(WIDGETS)/$(APP).pock"
	mkdir -p "$(WIDGETS)"
	cp -R $(BUNDLE) "$(WIDGETS)/"
	-pkill -x Pock
	@echo "Installed to $(WIDGETS). Relaunch Pock and add Agent Stats in Customize Touch Bar."

clean:
	rm -rf build
