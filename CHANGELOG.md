# Search Adaptive Kit — Changelog

## v0.7 — Native settings & seamless page top corners

- Fixed Peek-mode dimming: the native horizontal tab strip, its icons and buttons now get the same 22% black overlay as Search's page scrim; vertical sidebar controls follow the same dimming.
- Hardened top-only rounded corners by clipping both the full SwiftUI page stage (including loading overlays) and its AppKit WebView host. The native corner mask refreshes on layout/window rehosting and respects flipped layer geometry.
- No artificial outline, border, gutter or added shadow is introduced.
- Rebuilt Appearance controls using Search's native `GroupBlock` → `Card` → `SettingRow` / `Rule` / `Switch` / `Pill` components instead of stock-blue SwiftUI toggles and free-floating buttons.
- Split color controls and GitHub mod updater into two correctly styled settings groups, preserving the existing explicit build/install confirmations.
- Removed the custom page-top outline, drawn border, and artificial 5-point gutter. Native AppKit clipping still rounds only the top corners when the horizontal tabbar is in use; same-color pages remain seamless.
- Added documentation of the macOS Apple Passwords helper allowlist and passkey entitlements that prevent unsigned/ad-hoc local builds from inheriting official Search's integration.
- Added regression tests to protect border-free rounding and Settings UI hooks.

## v0.6 — Settings and staged GitHub updates

- Fix light-page search field: light input is distinctly brighter than the dimmed page; dark inputs keep their hue.
- Dim the full horizontal toolbar including icons, tabs and buttons at the top-level window overlay, just under the omnibox.
- Expose five preferences in `search://settings/appearance`: adaptive colors, search overlay, rounded corners, diagnostics, and official release checks.
- Give top-only page corners a small gutter and faint edge, so the rounding is visible even when chrome and page match.
- Add opt-in GitHub update panel with branch/tag and exact SHA selection, two-step local build/staged install/restart, and a local build log. Nothing runs from GitHub without confirmation.
- Keep official Search release notifications enabled by default, blocking installation of unmodified official binaries over the patched app.
- Add mod update script and a managed checkout; never reset user-owned directories.
- Expand patch to `Settings.swift` and copy a second isolated module, `AdaptiveSettings.swift`.

## v0.5 — Shared palette, page geometry, safe official update notices

- Single per-window observer shared by tabs, toolbar and omnibox.
- Experimental top-only corner rounding of edge-to-edge WebViews.
- Check for official Search releases by default, without overwriting the modified browser.
- Optional CLI flags to disable release notifications.

## v0.4 — New-tab and modal tint

- Preserve the active site's last reliable background during new-tab creation.
- Detect RGB tint and alpha of modal overlays instead of assuming every backdrop is black.

## v0.3 — Search and smooth chrome

- 240 ms color transitions, search tint, hue-preserving HSL accent colors and bounded pixel snapshot fallback.

## v0.2 — Colors and stability

- Dominant top-edge color detector, hover/pinned tab palette, modal shading and stable tab strip.

## v0.1

- Initial adaptive chrome prototype.
### v0.7 — top corner compositor fix
- Browser page corner rounding is now enforced by two tiny corner cutouts rendered **above** WKWebView, filled with the toolbar's adaptive background. This avoids WebKit compositor layers bypassing ordinary SwiftUI and CALayer masks.
- The cutouts use no border, gutter or shadow; their fill follows Search and Peek overlay dimming. Existing Peek shading remains unchanged.
- Added idempotence and integration assertions for the cutout layer.

### v0.7 — corner placement correction
- Removed root-window corner overlay and its guessed `chrome.height` offset; cutouts are now attached directly to the page stage **before** SwiftUI padding and motion transforms.
- A visible pink cutout diagnostic is available only with `debug-on`, making wrong placement and an old app build easy to identify.
- Peek shading remains unchanged and is applied once above the page-attached cutouts.
