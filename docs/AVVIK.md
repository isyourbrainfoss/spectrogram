# Avvik

Deviations from tracking Flutter stable for this app. Each entry records what changed, why, which files, the sha256, the off switch, and the rollback.

## 2026-11-21 — Pin Flutter 3.47.8 (no Wayland subsurface renderer)

### What

Flutter is pinned to **3.47.8** everywhere this repo installs a toolchain. The knob is one workflow env, `FLUTTER_VERSION`.

- `linux-flatpak-release.yml` x86_64: `subosito/flutter-action@v2` with `channel: stable` and `flutter-version: ${{ env.FLUTTER_VERSION }}`.
- `linux-flatpak-release.yml` aarch64: `git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1` (flutter-action has no prebuilt arm64 SDK archive).
- `ci.yml` and `android_release.yml`: the same pin. Android is not hit by the Wayland bug. One toolchain per repo avoids a build that works on 3.47 and breaks on 3.50.
- Both Flatpak build jobs, after the build, print `flutter --version` and fail if `flatpak/build-<arch>/files/bin/lib/libflutter_linux_gtk.so` contains `FlViewRendererSubsurface`.
- The Flatpak workflow also runs on `pull_request` to `main` and still uploads `flatpak-bundle-x86_64` and `flatpak-bundle-aarch64`. The `publish` job (gh-pages, release assets, `repository_dispatch`) runs only when `github.event_name != 'pull_request' && github.ref == 'refs/heads/main'`. Concurrency is `flatpak-pages-${{ github.event_name == 'pull_request' && github.ref || 'main' }}`, so a PR run does not cancel a main publish.
- `pubspec.lock` moves four transitive packages that the 3.47.8 SDK requires and the old lock cannot satisfy (`flutter pub get --enforce-lockfile` fails): `vector_math` 2.2.0 → 2.4.4 (`flutter` requires `^2.4.0`), `meta` 1.18.0 → 1.19.0 (`flutter` requires `^1.18.3`), `matcher` 0.12.19 → 0.12.20, `test_api` 0.7.11 → 0.7.12 (`flutter_test` pins those two). No `pubspec.yaml` constraint changed.
- No application code changed. The README does not name a Flutter version, so it was left alone. Flutter rewrote `analysis_options.yaml` locally; that rewrite is not committed.

### Why

Flutter 3.50.x on Linux/Wayland uses `FlViewRendererSubsurface` (`fl_view_renderer_subsurface.cc`, `fl_subsurface*.cc`). On a Fairphone 5 (BengalOS 0.26.1120.1, Phosh/phoc 0.59, aarch64, GNOME Platform 50) the app logs `Timed out waiting for subsurface frame ... (have 3840x2160)` and then deadlocks: the main thread waits on a futex and the raster thread spins, so no window appears. Upstream: flutter#196529, #196663, #195822. `FLUTTER_LINUX_RENDERER=software` aborts in Impeller `DlText`, and 3.50 has no `opengl-gtk` opt-out.

3.47.8 is a stable release that does not ship that renderer (framework `737ba8f885`, `engine.version` `cf636b1dfb`, engine hash `dfd2e6cb7d31`, Dart 3.13.7). Its Linux shell has only `fl_view_renderer.{cc,h}`. The 3.47.8 `linux-arm64-release` `libflutter_linux_gtk.so` has 0 occurrences of `FlViewRendererSubsurface` and 0 of `Timed out waiting for subsurface`. The same artifact for 3.50.1 has 3 and 1. 3.47.9 also lacks the renderer; this pin stays on 3.47.8 because that is the requested version.

### Files

- `.github/workflows/linux-flatpak-release.yml`
- `.github/workflows/ci.yml`
- `.github/workflows/android_release.yml`
- `pubspec.lock`
- `docs/AVVIK.md`

### sha256

Local x86_64 build on the desk, Flutter 3.47.8, 2026-11-21. The Flutter bundle copy and the Flatpak build-dir copy of the engine library are byte-identical. `strings` on that library: `FlViewRendererSubsurface` 0, `Timed out waiting for subsurface` 0.

| File | sha256 |
|---|---|
| `libflutter_linux_gtk.so` (x86_64, 17256536 bytes) | `360ff98cd21382014818e418a9b96dcddf93240751300627fe14816d5993a891` |
| `com.isyourbrainfoss.Spectrogram-x86_64.flatpak` (7495528 bytes) | `8766b55300b58f32030eb1dc6f300ce5622548bba59625433b8b33932550932a` |

aarch64 sha256 is not from this desk (no aarch64 emulation). It comes from the PR's `linux-flatpak-release` artifacts.

### Off switch

There is no runtime switch. The renderer is compiled into `libflutter_linux_gtk.so`. To build with a different Flutter, change `FLUTTER_VERSION` in the three workflows (or revert the pin commits) and rebuild. A running install keeps the engine it was built with until it is replaced.

### Rollback

Revert the pin commits. Unpin only after a stable Flutter release contains the subsurface fix and that build has been verified on the Fairphone 5: the window maps under Phosh/phoc, the log has no `Timed out waiting for subsurface frame`, and the main thread does not stall on a futex. A desktop check is not that verification. The desk compositor is not phoc.
