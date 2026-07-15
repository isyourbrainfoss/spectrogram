#!/usr/bin/env bash
# Build a Spectrogram Flatpak for the current (or requested) CPU architecture.
#
# Produces:
#   - ostree repo at $REPO_DIR (default: flatpak/repo) for hosting under gh-pages/repo
#   - single-file bundle flatpak/com.isyourbrainfoss.Spectrogram-${ARCH}.flatpak
#   - spectrogram.flatpakrepo (repo root copy for gh-pages)
#
# Usage:
#   ./flatpak/build-flatpak.sh [x86_64|aarch64]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLATPAK_DIR="$ROOT/flatpak"
APP_DIR="$ROOT"
ARCH="${1:-$(uname -m)}"

case "$ARCH" in
  x86_64|amd64)
    FLATPAK_ARCH=x86_64
    FLUTTER_OUT=x64
    ;;
  aarch64|arm64)
    FLATPAK_ARCH=aarch64
    FLUTTER_OUT=arm64
    ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

if ! command -v flatpak-builder >/dev/null; then
  echo "flatpak-builder is required." >&2
  exit 1
fi

if ! command -v flutter >/dev/null; then
  echo "flutter is required." >&2
  exit 1
fi

echo "==> Ensuring GNOME Platform/SDK 48"
flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
flatpak install -y --user flathub org.gnome.Platform//48 org.gnome.Sdk//48 >/dev/null 2>&1 || \
  flatpak install -y flathub org.gnome.Platform//48 org.gnome.Sdk//48

echo "==> Building Flutter Linux release ($FLATPAK_ARCH)"
cd "$APP_DIR"
flutter pub get
flutter build linux --release

BUNDLE="$APP_DIR/build/linux/$FLUTTER_OUT/release/bundle"
if [[ ! -x "$BUNDLE/spectrogram" ]]; then
  echo "Missing Linux bundle at $BUNDLE" >&2
  exit 1
fi

# Icon from Android launcher assets
ICON_SRC="$APP_DIR/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
if [[ ! -f "$ICON_SRC" ]]; then
  ICON_SRC="$APP_DIR/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"
fi
ICON_DST="$FLATPAK_DIR/com.isyourbrainfoss.Spectrogram.png"
cp "$ICON_SRC" "$ICON_DST"

echo "==> Staging pulseaudio tools (parecord/pactl for record_linux)"
TOOLS_DIR="$FLATPAK_DIR/pulse-tools"
rm -rf "$TOOLS_DIR"
mkdir -p "$TOOLS_DIR/bin" "$TOOLS_DIR/lib"

stage_bin() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    local src
    src="$(command -v "$name")"
    cp -a "$src" "$TOOLS_DIR/bin/"
    # Copy immediate shared libs if ldd is available (best-effort).
    if command -v ldd >/dev/null 2>&1; then
      ldd "$src" 2>/dev/null | awk '/=> \// {print $3}' | while read -r lib; do
        [[ -f "$lib" ]] || continue
        base="$(basename "$lib")"
        # Skip glibc / system core libs already in the runtime
        case "$base" in
          libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|libresolv.so*|ld-linux*) continue ;;
        esac
        cp -an "$lib" "$TOOLS_DIR/lib/" 2>/dev/null || true
      done
    fi
  else
    echo "Warning: $name not found on host — Flatpak mic capture may fail without it." >&2
  fi
}

stage_bin parecord
stage_bin pactl
# Keep directory non-empty for flatpak-builder dir source
touch "$TOOLS_DIR/.keep"

echo "==> Packaging Flutter bundle archive"
tar -czf "$FLATPAK_DIR/spectrogram-linux-bundle.tar.gz" -C "$BUNDLE" .

REPO_DIR="${REPO_DIR:-$FLATPAK_DIR/repo}"
mkdir -p "$REPO_DIR"
BUILD_DIR="${BUILD_DIR:-$FLATPAK_DIR/build-$FLATPAK_ARCH}"
rm -rf "$BUILD_DIR"

echo "==> flatpak-builder ($FLATPAK_ARCH) → $REPO_DIR"
flatpak-builder \
  --user \
  --arch="$FLATPAK_ARCH" \
  --force-clean \
  --repo="$REPO_DIR" \
  "$BUILD_DIR" \
  "$FLATPAK_DIR/com.isyourbrainfoss.Spectrogram.yml"

BUNDLE_OUT="$FLATPAK_DIR/com.isyourbrainfoss.Spectrogram-${FLATPAK_ARCH}.flatpak"
flatpak build-bundle "$REPO_DIR" "$BUNDLE_OUT" com.isyourbrainfoss.Spectrogram \
  --arch="$FLATPAK_ARCH" \
  --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo

# Ensure .flatpakrepo is present at flatpak/ (and optionally project root for CI copy)
cp "$FLATPAK_DIR/spectrogram.flatpakrepo" "$ROOT/spectrogram.flatpakrepo" 2>/dev/null || true

echo
echo "==> Built:"
echo "    Repo:   $REPO_DIR"
echo "    Bundle: $BUNDLE_OUT"
echo "    Remote: $FLATPAK_DIR/spectrogram.flatpakrepo"
echo
echo "Add as a user remote (after publishing to gh-pages):"
echo "  flatpak remote-add --if-not-exists --user spectrogram \\"
echo "    https://isyourbrainfoss.github.io/spectrogram/spectrogram.flatpakrepo"
echo "  flatpak install --user spectrogram com.isyourbrainfoss.Spectrogram"
echo
echo "Local test (no network):"
echo "  flatpak --user remote-add --if-not-exists --no-gpg-verify spectrogram-local file://$REPO_DIR"
echo "  flatpak install --user spectrogram-local com.isyourbrainfoss.Spectrogram"
echo "  flatpak run com.isyourbrainfoss.Spectrogram"
