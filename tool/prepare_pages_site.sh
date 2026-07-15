#!/usr/bin/env bash
# Build a GitHub Pages site with a stable APK URL for Obtainium.
set -euo pipefail

APK="${1:?APK path required}"
VERSION="${2:?version name required}"
VERSION_CODE="${3:?version code required}"
SITE_DIR="${4:?site output directory required}"

PAGES_BASE="https://isyourbrainfoss.github.io/spectrogram"
APK_URL="https://raw.githubusercontent.com/isyourbrainfoss/spectrogram/gh-pages/spectrogram-arm64-v8a.apk"
OBTAINIUM_URL="https://raw.githubusercontent.com/isyourbrainfoss/spectrogram/gh-pages/version.json"

mkdir -p "$SITE_DIR"
cp "$APK" "$SITE_DIR/spectrogram-arm64-v8a.apk"
touch "$SITE_DIR/.nojekyll"

SHA256=$(sha256sum "$APK" | awk '{print $1}')
TIMESTAMP=$(date -u +%s)000

cat > "$SITE_DIR/version.json" <<EOF
{
  "version": "${VERSION}",
  "versionName": "${VERSION}",
  "versionCode": ${VERSION_CODE},
  "sha256sum": "${SHA256}",
  "url": "${APK_URL}",
  "uploadTimestamp": ${TIMESTAMP}
}
EOF

cat > "$SITE_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Spectrogram ${VERSION} (Android)</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 40rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; background: #0d1117; color: #e6edf3; }
    a { color: #58a6ff; }
    a.button { display: inline-block; padding: 0.6rem 1.2rem; background: #238636; color: #fff; text-decoration: none; border-radius: 6px; }
    code { background: #21262d; padding: 0.1rem 0.3rem; border-radius: 3px; }
  </style>
</head>
<body>
  <h1>Spectrogram ${VERSION}</h1>
  <p>Live microphone spectrogram for Android and Linux.</p>
  <p><a class="button" href="${APK_URL}">Download APK (arm64-v8a)</a></p>
  <p>Version <strong>${VERSION}</strong> (build ${VERSION_CODE}). SHA-256: <code>${SHA256}</code></p>
  <p>Install via <a href="https://github.com/ImranR98/Obtainium">Obtainium</a>:</p>
  <p><code>${OBTAINIUM_URL}</code></p>
  <p><a href="https://github.com/isyourbrainfoss/spectrogram">Source on GitHub</a></p>
</body>
</html>
EOF

ls -lh "$SITE_DIR"
