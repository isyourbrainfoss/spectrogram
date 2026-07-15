# Spectrogram

Live adaptive spectrogram for **Android**, **Linux desktop**, and **Linux mobile**.

Capture the microphone and view a real-time spectrogram (time × frequency × amplitude as color) or a live spectrum (frequency × amplitude). Tap the plot to place a crosshair and read exact **frequency (Hz)** and **amplitude (dBFS)**.

## Features

- **Spectrogram mode** — scrolling STFT heatmap (time on X, frequency on Y, dBFS as color)
- **Spectrum mode** — live frequency vs dBFS line plot
- **Crosshair** — tap / drag for exact Hz + dBFS readout
- **Adaptive UI** — bottom navigation on phones, navigation rail on wide screens
- **Settings** — sample rate, FFT size, hop, time window, frequency/dB range, colormap, theme
- **Sane defaults** — 48 kHz, FFT 2048, Hann window, hop 512, 8 s window, viridis colormap

## Install

### Android (Obtainium recommended)

1. Install [Obtainium](https://github.com/ImranR98/Obtainium/releases).
2. Add app → paste:

   ```
   https://raw.githubusercontent.com/isyourbrainfoss/spectrogram/gh-pages/version.json
   ```

One-tap (Obtainium installed):

```
https://apps.obtainium.imranr.dev/redirect.html?r=obtainium://add/https://raw.githubusercontent.com/isyourbrainfoss/spectrogram/gh-pages/version.json
```

APKs are also attached to [GitHub Releases](https://github.com/isyourbrainfoss/spectrogram/releases).

#### “App not installed” / must uninstall to update

Android only upgrades an APK if the **signing certificate** matches the installed app.

Releases use a **stable upload keystore** in the repo so Obtainium can update in-place. If you installed an older build signed with a temporary CI debug key, **uninstall once**, then install again from Obtainium — later updates work without uninstalling.

```bash
adb uninstall com.isyourbrainfoss.spectrogram
```
### Linux (Flatpak — recommended)

Add the remote and install (same pattern as Flowlog / Progressor):

```bash
flatpak remote-add --if-not-exists --user spectrogram \
  https://isyourbrainfoss.github.io/spectrogram/spectrogram.flatpakrepo
flatpak install --user spectrogram com.isyourbrainfoss.Spectrogram
flatpak run com.isyourbrainfoss.Spectrogram
```

CI publishes the ostree repo under `gh-pages/repo` on every push to `main`. Single-file `.flatpak` bundles are attached to releases when available.

**Build Flatpak locally:**

```bash
# needs: flatpak, flatpak-builder, flutter, pulseaudio-utils
./flatpak/build-flatpak.sh          # current arch
./flatpak/build-flatpak.sh x86_64
./flatpak/build-flatpak.sh aarch64
```

Local remote for testing:

```bash
flatpak --user remote-add --if-not-exists --no-gpg-verify spectrogram-local \
  file://$(pwd)/flatpak/repo
flatpak install --user spectrogram-local com.isyourbrainfoss.Spectrogram
```

### Linux (from source)

**Dependencies** (microphone capture via the `record` plugin):

```bash
# Debian/Ubuntu
sudo apt install pulseaudio-utils ffmpeg

# Fedora
sudo dnf install pulseaudio-utils ffmpeg

# Arch
sudo pacman -S libpulse ffmpeg
```

PipeWire users: `pulseaudio-utils` / `parecord` still work via the Pulse compatibility layer.

```bash
flutter pub get
flutter run -d linux
flutter build linux --release
# binary: build/linux/x64/release/bundle/spectrogram
```

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # Android device/emulator
flutter run -d linux   # desktop / Linux phone
```

### Project layout

```
lib/
  dsp/           # PCM, STFT (fftea), colormap (pure Dart, unit-tested)
  services/      # mic capture, engine, settings persistence
  features/      # home plot, settings, painters
  shell/         # adaptive NavigationRail / NavigationBar
```

### DSP notes

- Encoder: PCM 16-bit mono via [`record`](https://pub.dev/packages/record)
- Transform: Hann-windowed STFT via [`fftea`](https://pub.dev/packages/fftea)
- Level: `dBFS ≈ 20·log10(2·|X[k]|/N)` (full-scale sine near a bin ≈ 0 dBFS)

## License

MIT — see [LICENSE](LICENSE).
