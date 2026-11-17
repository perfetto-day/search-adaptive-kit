<div align="center">

<img src="assets/adaptive-chrome.svg" alt="Search Adaptive Kit — seamless browser chrome" width="760" />

# Search Adaptive Kit

**A page-aware color system for [Search Browser](https://searchbrowser.app/) on macOS.**  
Make your browser feel like an extension of the website, not a frame around it.

[![macOS](https://img.shields.io/badge/platform-macOS-181818?logo=apple)](https://www.apple.com/macos/)
[![SwiftUI](https://img.shields.io/badge/native-SwiftUI-F05138?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Project status](https://img.shields.io/badge/status-experimental-F59E0B)](#project-status)
[![Upstream](https://img.shields.io/badge/upstream-Search%20Browser-00BDB4)](https://github.com/driceroland/Search)
[![CI](https://github.com/perfetto-day/search-adaptive-kit/actions/workflows/checks.yml/badge.svg)](https://github.com/perfetto-day/search-adaptive-kit/actions/workflows/checks.yml)

**[Install](#quick-start)** · **[Features](#what-it-does)** · **[Russian guide](README_RU.md)** · **[Changelog](CHANGELOG.md)** · **[Upstream](https://github.com/driceroland/Search)**

</div>

---

## Why this exists

Search is a fast, minimal, native macOS WebKit browser. This project experiments with a more **seamless** look: the toolbar, sidebar, tabs and search overlay adopt the visible background of the active website.

This is **not** a Chrome / Safari extension. Search's interface is written in SwiftUI, so its native controls must be adapted at source level. Instead of maintaining a complete fork, the kit applies a narrowly scoped patch to an up-to-date upstream checkout and builds a **separate** app.

## What it does

| Feature | Implementation |
| --- | --- |
| **Adaptive toolbar** | Estimates the top-of-page background, prioritizing visible colors over page accent metadata |
| **Tinted tabs** | Uses hue-preserving HSL lightness adjustments for active, hovered and pinned tabs |
| **Smooth transitions** | Animates compatible color changes (~240 ms), without animating toolbar position |
| **Unified search overlay** | Applies page-aware shading to the search scrim, native chrome and search field |
| **Modal awareness** | Detects common modal backdrops and approximates their dimming |
| **Pixel validation** | Uses limited, occasional WebKit snapshots when CSS sampling is ambiguous |
| **Repeatable updates** | Reapplies the patch to a clean Search checkout and builds `Search Adaptive.app` |

The color detector is heuristic. Complex canvases, videos, gradients, custom overlays, translucent content and split-screen layouts may not match perfectly.

## Quick start

**Requirements:** macOS 14+, full **Xcode** (not just Command Line Tools), Git and Python 3. Node.js is optional for the detector tests.

Clone **this** repository:

```bash
git clone https://github.com/perfetto-day/search-adaptive-kit.git
cd search-adaptive-kit
./update-and-build.sh
```

Enable adaptive coloring and launch the separate app:

```bash
./toggle-mode.command on
open "$HOME/Applications/Search Adaptive.app"
```

> The installation script works in a dedicated checkout under `~/Library/Application Support/SearchAdaptive/Search-source`. It resets **that managed checkout only**, builds the app, and installs it in `~/Applications`. Read the script before running it.

### Update

Close Search Adaptive, pull the latest kit changes, and run the build script again:

```bash
git pull --ff-only
./update-and-build.sh
```

Unlike upstream Search, the modified app does **not** use upstream's automatic binary updater: an upstream update would otherwise overwrite the patch.

### Controls

```bash
./toggle-mode.command on          # adaptive UI
./toggle-mode.command off         # original Search palette
./toggle-mode.command debug-on    # show detected color / source / dimming
./toggle-mode.command debug-off
./toggle-mode.command status
```

Restart the modified app after changing a setting.

## How it is organized

```text
AdaptiveChrome.swift           WebKit color sampling, palette and SwiftUI integration
apply_mod.py                   Guarded, repeatable upstream patcher
update-and-build.sh            Clone upstream, apply, build, install
toggle-mode.command            Local preference switches
tests/                         Detector and patcher regression tests
README_RU.md                   Full Russian installation / troubleshooting guide
CHANGELOG.md                   Changes between prototypes
```

The patcher modifies **six** upstream Swift sources: `Tab.swift`, `App.swift`, `Side.swift`, `TabBar.swift`, `Omnibox.swift`, and `Updater.swift`. It stops rather than guessing when an upstream code anchor changes.

## Tests

```bash
python3 tests/patcher.test.py
node tests/color-detector.test.js
bash -n update-and-build.sh toggle-mode.command
```

These checks exercise patch application and JavaScript color heuristics. They **do not prove a successful macOS app build**. Full Xcode compilation and real WebKit/SwiftUI visual testing are still required.

## Project status

**Experimental v0.3** — an independent prototype, not a signed, verified browser release. Expect rough edges. The separate app may use Search's existing application identity and profile settings: back up your browser data before the first run. Do not treat this as an isolated browser security profile.

Contributions and bug reports are welcome, especially reproducible color mismatches and upstream patch conflicts. See [Contributing](CONTRIBUTING.md).

## Credits & legal

Based on [Search](https://github.com/driceroland/Search), developed by Office Commun, which is distributed under the [MIT License](https://github.com/driceroland/Search/blob/main/LICENSE). This repository contains an independent patch kit rather than a copy of the full upstream browser. See [LICENSE](LICENSE) and [third-party acknowledgments](THIRD_PARTY.md).

**Not affiliated with, sponsored by, or endorsed by Search Browser or Office Commun.**
