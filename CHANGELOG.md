# Search Adaptive Kit Changelog

## v0.5 — shared search palette, update notifications, rounded page edge

- One per-browser live color model for toolbar, sidebar and Omnibox; no independent palette race on new tabs.
- Omnibox uses the shared palette directly to avoid a light neutral search field over a dark site.
- Edge-to-edge web pages below horizontal tabs have **top-only rounded corners** using native `StageView.layer.maskedCorners` (no extra clipping on the whole SwiftUI window).
- Restore background checks for official Search releases **ON by default**; report new versions through Search's in-app announcements.
- Block all official binary replacement paths in the modified app; rebuild with the kit to actually update.
- Add `updates-on` / `updates-off` in `toggle-mode.command` (manual update checking still possible).
- Add a seventh upstream integration file (`Stage.swift`) and regression test assertions.

## v0.4 — Search overlay and modal color matching

- Preserve the last valid page palette while showing the omnibox/new-tab field; avoid reverting to a white field over a dark page.
- Keep the search scrim on the native toolbar and the WebView in sync, including when the address bar is opened for a new tab.
- Use the actual CSS modal-backdrop RGB shade rather than assuming every backdrop is black. Supports light overlays too.
- Refresh the shared browser-color cache when the search field opens/closes; keep stale modal dimming out of the cache.
- Extend detector tests to cover RGB-colored modal overlays and light overlay shades.

## v0.3 — Search and smooth chrome

- Smooth 240 ms color transitions when a site's theme/background changes.
- Shared tint and fade between the omnibox scrim and native chrome, including horizontal/vertical tabs.
- Search input, text, suggestions, and field backdrop follow active site's contrast and hue.
- HSL lightness adjustments instead of neutral black/white mixing for active/hover/pinned tabs.
- Bounded on-screen pixel verification of the visible top-of-page color after changes.
- Hold the previous page color briefly while a navigation commits.
- Update script still applies the patch to fresh upstream Search; no upstream fork required.

## v0.2

- Top-edge detection, modal dimming, shared UI palette, stable top toolbar, safe updater handling, debug marker.

## v0.1

- Initial adaptive chrome prototype for Search.