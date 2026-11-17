# Search Adaptive Kit — Changelog

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