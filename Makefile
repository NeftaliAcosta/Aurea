APP_NAME := aurae
BIN_DIR  := bin
SRC      := ./cmd/aurae
APP_BUNDLE := $(BIN_DIR)/Aurae.app

.PHONY: all build test clean doctor run install app

all: build test

build:
	@mkdir -p $(BIN_DIR) $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	go build -ldflags="-s -w" -o $(BIN_DIR)/$(APP_NAME) $(SRC)
	@cp $(BIN_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/aurae-engine
	@swiftc -O -o $(BIN_DIR)/aurae-listener cmd/listener/main.swift
	@cp cmd/app/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@cp cmd/app/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@swiftc -O -framework Cocoa -framework SwiftUI -framework Carbon -framework QuartzCore cmd/app/main.swift -o $(APP_BUNDLE)/Contents/MacOS/Aurae
	@codesign --force --deep -s - $(APP_BUNDLE)
	@echo "✅ Binarios generados y firmados en $(BIN_DIR)/$(APP_NAME) y $(APP_BUNDLE)"

test:
	go test -v ./internal/...

doctor: build
	./$(BIN_DIR)/$(APP_NAME) doctor

clean:
	rm -rf $(BIN_DIR)

app: build
	@echo "🚀 Abriendo Aurae en la barra de menú..."
	@open $(APP_BUNDLE)

install: build
	@echo "Instalando $(APP_NAME) en /usr/local/bin..."
	@cp $(BIN_DIR)/$(APP_NAME) /usr/local/bin/$(APP_NAME) 2>/dev/null || sudo cp $(BIN_DIR)/$(APP_NAME) /usr/local/bin/$(APP_NAME)
	@echo "Instalando Aurae.app en /Applications..."
	@rm -rf /Applications/Aurae.app 2>/dev/null || sudo rm -rf /Applications/Aurae.app
	@cp -R $(APP_BUNDLE) /Applications/ 2>/dev/null || sudo cp -R $(APP_BUNDLE) /Applications/
	@echo "✅ Instalado. Ejecuta 'open /Applications/Aurae.app' o 'aurae --help'"
