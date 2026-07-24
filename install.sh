#!/usr/bin/env bash
# Nabz installer (SPEC-07). Builds a release binary, wraps it in a minimal
# Nabz.app bundle so the Bluetooth permission prompt is attributed to Nabz
# (PRD R-1 / D-01), and symlinks `nabz` onto your PATH.
#
# The PATH symlink points *inside* the bundle on purpose: running the binary
# from its bundle location is what gives you the Nabz-named TCC prompt.
#
# Override locations if you like:
#   APP_DIR=~/Applications BIN_DIR=~/.local/bin ./install.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-/Applications}"
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
APP="$APP_DIR/Nabz.app"
BUNDLED_BIN="$APP/Contents/MacOS/nabz"

# Echo "sudo" when we can't write to a dir (walk up to the nearest existing parent).
needs_sudo() {
  local d="$1"
  while [ ! -e "$d" ]; do d="$(dirname "$d")"; done
  [ -w "$d" ] || echo sudo
}

echo "==> Building release binary"
swift build -c release --package-path "$REPO"
SRC_BIN="$(swift build -c release --package-path "$REPO" --show-bin-path)/nabz"
[ -x "$SRC_BIN" ] || { echo "error: built binary not found at $SRC_BIN" >&2; exit 1; }

APP_SUDO="$(needs_sudo "$APP_DIR")"
BIN_SUDO="$(needs_sudo "$BIN_DIR")"

echo "==> Assembling $APP"
$APP_SUDO mkdir -p "$APP/Contents/MacOS"
$APP_SUDO cp "$REPO/packaging/Info.plist" "$APP/Contents/Info.plist"
$APP_SUDO cp "$SRC_BIN" "$BUNDLED_BIN"

echo "==> Linking $BIN_DIR/nabz -> $BUNDLED_BIN"
$BIN_SUDO mkdir -p "$BIN_DIR"
$BIN_SUDO ln -sf "$BUNDLED_BIN" "$BIN_DIR/nabz"

echo
echo "Installed. Try:  nabz --simulate"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Note: $BIN_DIR is not on your PATH — add it or move the symlink." ;;
esac
