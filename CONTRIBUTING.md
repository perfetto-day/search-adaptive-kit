# Contributing

Thank you for helping improve Search Adaptive Kit.

## Before filing a bug

1. Check whether the problem reproduces in the original Search browser.
2. Note the **macOS**, **Xcode**, **Search upstream commit**, and **kit** versions.
3. Record whether the site is in light/dark mode and whether the problem occurs on navigation, search, or a modal.
4. Enable diagnostics with `./toggle-mode.command debug-on` and include the resulting source/color if possible.
5. Prefer a public reproducible site or a minimal HTML fixture. **Never post private tabs, passwords, internal websites, or personal information.**

## Development flow

- Create a feature branch and send a pull request to `main`.
- Keep upstream-specific modifications in `apply_mod.py` and reusable logic in `AdaptiveChrome.swift`.
- Add a JavaScript detector or Python patcher regression test for fixes.
- Verify the patcher applies twice cleanly and fails safely when an upstream anchor changes.
- Do not add proprietary upstream source files, signed app binaries, credentials, or browser profile data.

## Checks

```bash
python3 tests/patcher.test.py
node tests/color-detector.test.js
bash -n update-and-build.sh toggle-mode.command
```

If available, also compile with full Xcode and manually verify the native UI. A green CI check does **not** imply a successful macOS application build.

## Scope

This project is an **experimental source-level modification**, not a WebExtension. Please keep it small and maintainable across upstream releases.
