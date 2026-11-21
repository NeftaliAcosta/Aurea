#!/usr/bin/env bash
set -e

# Aurae Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/neftaliacosta/aurae/main/scripts/install.sh | sh

echo "✨ Instalando Aurae (Dictado Inteligente Local)..."

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "❌ Arquitectura no soportada: $ARCH"; exit 1 ;;
esac

echo "🖥️  Detectado: $OS ($ARCH)"

# Verificar dependencias en macOS
if [ "$OS" = "darwin" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "⚠️  Homebrew es recomendado para instalar whisper-cpp y sox."
  else
    if ! command -v whisper-cli >/dev/null 2>&1; then
      echo "📦 Instalando whisper-cpp..."
      brew install whisper-cpp
    fi
    if ! command -v rec >/dev/null 2>&1; then
      echo "📦 Instalando sox..."
      brew install sox
    fi
  fi
fi

# Instalar binario compilado o compilar con go si está presente
INSTALL_DIR="/usr/local/bin"
if [ ! -w "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/.local/bin"
  mkdir -p "$INSTALL_DIR"
fi

if command -v go >/dev/null 2>&1; then
  echo "🔨 Compilando Aurae localmente..."
  go install github.com/neftaliacosta/aurae/cmd/aurae@latest 2>/dev/null || {
    go build -ldflags="-s -w" -o "$INSTALL_DIR/aurae" ./cmd/aurae
  }
fi

echo "✅ Aurae instalado exitosamente."
echo "👉 Ejecuta 'aurae doctor' para validar tu instalación."
echo "👉 Ejecuta 'aurae record' para empezar a dictar."
