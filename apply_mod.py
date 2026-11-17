#!/usr/bin/env python3
"""Search Adaptive v0.4 overlay. Validates all anchors before touching files.

Works against a clean upstream checkout; safe to run twice on the same checkout.
The update script always restores upstream main first so a new release is never
patched on top of a previous, possibly incompatible, patched source tree.
"""
from pathlib import Path
import argparse
import shutil
import sys


def one(code: str, before: str, after: str, file: Path) -> str:
    n = code.count(before)
    if n != 1:
        raise RuntimeError(f"{file.name}: expected exactly one anchor, found {n}: {before[:100]!r}")
    return code.replace(before, after, 1)


def apply(repo: Path, kit: Path) -> None:
    root = repo / 'Sources' / 'Search'
    paths = {n: root / n for n in ['Tab.swift', 'App.swift', 'Side.swift', 'TabBar.swift', 'Omnibox.swift', 'Updater.swift']}
    for file in paths.values():
        if not file.is_file():
            raise RuntimeError(f"Not a Search source tree: missing {file}")
    changes = {n: p.read_text(encoding='utf8') for n, p in paths.items()}

    tab = paths['Tab.swift']; s = changes['Tab.swift']
    if 'private let adaptiveChromeRelay' not in s:
        s = one(s,
            '    @Published private(set) var cover: NSImage?',
            '''    @Published private(set) var cover: NSImage?

    // Search Adaptive v0.4. Only the active Tab's report is drawn in the chrome.
    @Published private(set) var adaptiveChromeReport = AdaptiveChromeReport()
    private let adaptiveChromeRelay = AdaptiveChromeRelay()
    private var adaptiveChromeGeneration = 0
    private var adaptiveChromeSnapshots = 0
    private var adaptiveChromeSnapshotKey: String?
    private var adaptiveChromeHasReport = false

    func receiveAdaptiveChrome(_ body: [String: Any]) {
        let proposed = (body["color"] as? String ?? "").lowercased()
        let dim = min(0.85, max(0, body["dim"] as? Double ?? 0))
        let shade = (body["shade"] as? String ?? "#000000").lowercased()
        let parsed = AdaptiveChrome.parse(proposed) == nil ? "" : proposed
        let color = parsed.isEmpty && dim > 0 ? adaptiveChromeReport.hex : parsed
        let next = AdaptiveChromeReport(hex: color, dim: dim,
                                        shade: AdaptiveChrome.parse(shade) == nil ? "#000000" : shade,
                                        source: body["source"] as? String ?? "dom",
                                        snapshot: body["snapshot"] as? Bool ?? false)
        adaptiveChromeHasReport = true
        if next != adaptiveChromeReport { adaptiveChromeReport = next }

        // Verify the actual painted top edge, not only its CSS. Sampling stays
        // bounded and is debounced after theme changes, so dark/light toggles
        // do not freeze the page or race a modal backdrop.
        guard next.snapshot, dim < 0.01,
              adaptiveChromeSnapshots < 4, let web = built,
              web.window != nil, web.bounds.width > 2, web.bounds.height > 2 else { return }
        let key = next.hex + "|" + next.source
        guard adaptiveChromeSnapshotKey != key else { return }
        adaptiveChromeSnapshotKey = key
        adaptiveChromeSnapshots += 1
        let generation = adaptiveChromeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self, weak web] in
            guard let self, let web, self.adaptiveChromeGeneration == generation,
                  self.adaptiveChromeReport.dim < 0.01,
                  self.adaptiveChromeReport.hex == next.hex else { return }
            let request = WKSnapshotConfiguration()
            request.rect = CGRect(x: 0, y: 0, width: web.bounds.width, height: min(3, web.bounds.height))
            request.afterScreenUpdates = true
            web.takeSnapshot(with: request) { [weak self] image, _ in
                MainActor.assumeIsolated {
                    guard let self, self.adaptiveChromeGeneration == generation,
                          self.adaptiveChromeReport.dim < 0.01,
                          self.adaptiveChromeReport.hex == next.hex,
                          let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                          let chosen = AdaptiveChrome.sample(cg) else { return }
                    self.adaptiveChromeReport = AdaptiveChromeReport(hex: chosen,
                        dim: 0, source: "pixels", snapshot: false)
                }
            }
        }
    }
''', tab)
        s = one(s,
            '    func didCommit() {\n        popupGesture.clear()',
            '''    func didCommit() {
        adaptiveChromeGeneration &+= 1
        adaptiveChromeSnapshots = 0
        adaptiveChromeSnapshotKey = nil
        adaptiveChromeHasReport = false
        let generation = adaptiveChromeGeneration
        // Carry the previous colour through navigation, rather than flashing
        // the window's default white during a dark-site page load.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.adaptiveChromeGeneration == generation,
                  !self.adaptiveChromeHasReport else { return }
            self.adaptiveChromeReport = AdaptiveChromeReport()
        }
        popupGesture.clear()''', tab)
        s = one(s,
            '        controller.add(dusk, contentWorld: Web.world, name: DuskRelay.name)',
            '''        controller.add(dusk, contentWorld: Web.world, name: DuskRelay.name)
        controller.removeScriptMessageHandler(forName: AdaptiveChromeRelay.name, contentWorld: .defaultClient)
        adaptiveChromeRelay.tab = self
        controller.add(adaptiveChromeRelay, contentWorld: .defaultClient, name: AdaptiveChromeRelay.name)''', tab)
        s = one(s,
            '        add(ScrollRelay.script, .atDocumentEnd, mainFrameOnly: true, in: Web.world)',
            '''        add(ScrollRelay.script, .atDocumentEnd, mainFrameOnly: true, in: Web.world)
        if AdaptiveChrome.enabled {
            add(AdaptiveChromeRelay.script, .atDocumentEnd, mainFrameOnly: true, in: .defaultClient)
        }''', tab)
        s = one(s,
            '        let controller = web.configuration.userContentController\n        Web.release(controller)\n        controller.removeAllUserScripts()',
            '''        let controller = web.configuration.userContentController
        controller.removeScriptMessageHandler(forName: AdaptiveChromeRelay.name, contentWorld: .defaultClient)
        Web.release(controller)
        controller.removeAllUserScripts()''', tab)
        changes['Tab.swift'] = s

    app = paths['App.swift']; s = changes['App.swift']
    if 'AdaptiveChromeSurface(browser: browser' not in s:
        s = one(s,
            '(fullscreenTab != nil ? Color.black : cards ? Palette.frame : Palette.ground)',
            '''Group {
                if fullscreenTab != nil { Color.black }
                else { AdaptiveChromeSurface(browser: browser, fallback: cards ? Palette.frame : Palette.ground) }
            }''', app)
        s = one(s,
            '            Omnibox(browser: browser, over: !(browser.active?.isBlank ?? true))',
            """            Omnibox(browser: browser, over: !(browser.active?.isBlank ?? true))
                .modifier(AdaptiveChromeSearchContext(browser: browser))""", app)
        changes['App.swift'] = s

    side = paths['Side.swift']; s = changes['Side.swift']
    if 'AdaptiveChromeStyle(browser: browser, greys: greys)' not in s:
        s = one(s,
            '        .environment(\\.greys, greys)\n        .frame(width: width)',
            '''        .modifier(AdaptiveChromeStyle(browser: browser, greys: greys))
        .frame(width: width)''', side)
        s = one(s,
            '                landing ? greys.hover : onFrame ? Palette.frame : Palette.ground',
            '''                if landing { greys.hover }
                else { AdaptiveChromeSurface(browser: browser, fallback: onFrame ? Palette.frame : Palette.ground) }''', side)
        s = one(s,
            'if !onFrame { Rectangle().fill(Palette.hairline).frame(width: 1) }',
            'if !onFrame && !AdaptiveChrome.enabled { Rectangle().fill(Palette.hairline).frame(width: 1) }', side)
        # The row's ink should follow the same palette as its greys (not Search's neutral ink).
        anchor = '''private struct SideRow: View, Equatable {
    @Environment(\\.greys) private var greys'''
        s = one(s, anchor,
            '''private struct SideRow: View, Equatable {
    @Environment(\\.adaptiveChromePalette) private var adaptive
    @Environment(\\.greys) private var greys''', side)
        s = one(s,
            '''    private var colour: Color {
        if live { return Palette.ink }
        let colour = hovering ? Palette.ink.opacity(0.7) : Palette.muted
        return putAway ? colour.opacity(0.45) : colour
    }''',
            '''    private var colour: Color {
        if live { return adaptive?.ink ?? Palette.ink }
        let colour = hovering ? (adaptive?.ink ?? Palette.ink).opacity(0.7) : (adaptive?.muted ?? Palette.muted)
        return putAway ? colour.opacity(0.45) : colour
    }''', side)
        # Shared toolbar Door (back/forward/reload, bookmarks) also needs
        # proper contrast. It appears in both the horizontal and side layouts.
        s = one(s,
            'struct Door: View {\n    @Environment(\\.greys) private var greys',
            'struct Door: View {\n    @Environment(\\.adaptiveChromePalette) private var adaptive\n    @Environment(\\.greys) private var greys', side)
        s = one(s,
            '                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.7) : Palette.muted))',
            '                .foregroundStyle(on ? (adaptive?.ink ?? Palette.ink) : (hovering ? (adaptive?.ink ?? Palette.ink).opacity(0.7) : (adaptive?.muted ?? Palette.muted)))', side)
        # Sidebar action buttons share the tint too.
        s = one(s,
            'struct Quiet: View {\n    @Environment(\\.greys) private var greys',
            'struct Quiet: View {\n    @Environment(\\.adaptiveChromePalette) private var adaptive\n    @Environment(\\.greys) private var greys', side)
        s = one(s,
            '            .foregroundStyle(hovering ? Palette.ink.opacity(0.7) : Palette.faint)',
            '            .foregroundStyle(hovering ? (adaptive?.ink ?? Palette.ink).opacity(0.7) : (adaptive?.muted ?? Palette.faint))', side)
        changes['Side.swift'] = s

    bar = paths['TabBar.swift']; s = changes['TabBar.swift']
    if 'AdaptiveChromeStyle(browser: browser, greys: .white' not in s:
        s = one(s,
            '''        .animation(Motion.settle, value: browser.tabs.map(\\.id))
    }

    // MARK: - the spaces, one above the other''',
            '''        // Avoid animating the entire toolbar when adding/closing a tab.
        // Individual tab pills retain their own animations.
        .animation(nil, value: browser.tabs.map(\\.id))
        .background(AdaptiveChromeSurface(browser: browser, fallback: Palette.ground))
        .modifier(AdaptiveChromeStyle(browser: browser, greys: .white, diagnostic: true))
    }

    // MARK: - the spaces, one above the other''', bar)
        s = one(s,
            '''private struct TabPill: View, Equatable {
    @Environment(\\.tabShortcutNumbers) private var shortcutNumbers''',
            '''private struct TabPill: View, Equatable {
    @Environment(\\.adaptiveChromePalette) private var adaptive
    @Environment(\\.tabShortcutNumbers) private var shortcutNumbers''', bar)
        # Limit replacements to TabPill itself rather than changing the rest of Search.
        start = s.index('private struct TabPill: View, Equatable {')
        end = s.index('/// The address, inside its own tab.', start)
        pill = s[start:end]
        expected = {
            'Rectangle().fill(pinned ? Palette.pinLive : Palette.wash)': 'Rectangle().fill(pinned ? (adaptive?.pin ?? Palette.pinLive) : (adaptive?.active ?? Palette.wash))',
            '.fill(Palette.wash)': '.fill(adaptive?.active ?? Palette.wash)',
            '.fill(Palette.hover)': '.fill(adaptive?.hover ?? Palette.hover)',
            '.fill(Palette.wash.opacity(0.55))': '.fill(adaptive?.tile ?? Palette.wash.opacity(0.55))',
            '''    private var colour: Color {
        if live { return Palette.ink }
        return hovering ? Palette.ink.opacity(0.7) : Palette.muted
    }''': '''    private var colour: Color {
        if live { return adaptive?.ink ?? Palette.ink }
        return hovering ? (adaptive?.ink ?? Palette.ink).opacity(0.7) : (adaptive?.muted ?? Palette.muted)
    }'''
        }
        for before, after in expected.items():
            pill = one(pill, before, after, bar)
        s = s[:start] + pill + s[end:]
        changes['TabBar.swift'] = s

    # Search's native URL panel has its own hard-coded neutral palette and a
    # site-independent white scrim. The search context keeps AppKit text, the
    # SwiftUI field, and the page/topbar shade consistent with the site.
    omnibox = paths['Omnibox.swift']; s = changes['Omnibox.swift']
    if 'adaptive?.searchScrim' not in s:
        s = one(s, 'struct Omnibox: View {',
            'struct Omnibox: View {\n    @Environment(\\.adaptiveChromePalette) private var adaptive', omnibox)
        s = one(s,
            '                        .fill(Palette.ground.opacity(0.74))',
            '                        .fill(adaptive?.searchScrim ?? Palette.ground.opacity(0.74))', omnibox)
        s = one(s,
            '                        .fill(Palette.ground)',
            '                        .fill(adaptive?.searchField ?? Palette.ground)', omnibox)
        s = one(s,
            '                        refused ? Color.red.opacity(0.35) : Palette.hairline,',
            '                        refused ? Color.red.opacity(0.35) : (adaptive?.hairline ?? Palette.hairline),', omnibox)
        s = one(s,
            '        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))',
            '        .background(adaptive?.searchField ?? Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))', omnibox)
        s = one(s,
            'struct AddressField: NSViewRepresentable {',
            'struct AddressField: NSViewRepresentable {\n    @Environment(\\.adaptiveChromePalette) private var adaptive', omnibox)
        s = one(s, '        field.textColor = Palette.NS.ink',
            '        field.textColor = adaptive?.inkNS ?? Palette.NS.ink', omnibox)
        s = one(s, '    private static func placeholder(_ words: String) -> NSAttributedString {',
            '    private static func placeholder(_ words: String, ink: NSColor? = nil) -> NSAttributedString {', omnibox)
        s = one(s, '                .foregroundColor: NSColor(Palette.ink.opacity(0.3)),',
            '                .foregroundColor: ink?.withAlphaComponent(0.42) ?? NSColor(Palette.ink.opacity(0.3)),', omnibox)
        if s.count('Self.placeholder(words)') != 2:
            raise RuntimeError('Omnibox.swift: expected two placeholder call sites')
        s = s.replace('Self.placeholder(words)', 'Self.placeholder(words, ink: adaptive?.inkNS)')
        s = one(s, '        let coordinator = context.coordinator\n        coordinator.browser = browser',
            '        let coordinator = context.coordinator\n        field.textColor = adaptive?.inkNS ?? Palette.NS.ink\n        coordinator.browser = browser', omnibox)
        # Search suggestions and site chip also need readable hue-aware ink.
        # Only the compact Omnibox views are touched, not Search's global design.
        for component in ['    struct Row: View {', 'private struct SiteIcon: View {',
                          'private struct SiteChip: View {', 'private struct SiteOfferRow: View {']:
            s = one(s, component,
                component + '\n    @Environment(\\.adaptiveChromePalette) private var adaptive', omnibox)
        front, divider, tail = s.partition('/// The breath under the field:')
        if not divider:
            raise RuntimeError('Omnibox.swift: missing breath section')
        front = front.replace('.foregroundStyle(Palette.ink)', '.foregroundStyle(adaptive?.ink ?? Palette.ink)')
        front = front.replace('.foregroundStyle(Palette.muted)', '.foregroundStyle(adaptive?.muted ?? Palette.muted)')
        front = front.replace('.fill(Palette.wash)', '.fill(adaptive?.active ?? Palette.wash)')
        front = front.replace('.fill(Palette.hover)', '.fill(adaptive?.hover ?? Palette.hover)')
        front = front.replace('.background(Palette.wash,', '.background(adaptive?.active ?? Palette.wash,')
        front = front.replace('.strokeBorder(Palette.hairline,', '.strokeBorder(adaptive?.hairline ?? Palette.hairline,')
        s = front + divider + tail
        changes['Omnibox.swift'] = s

    # Never install an official update over our modified .app.
    updater = paths['Updater.swift']; s = changes['Updater.swift']
    if 'if AdaptiveChrome.installed' not in s:
        s = one(s,
            '    func checkIfDue(then say: @escaping (String) -> Void) {',
            '    func checkIfDue(then say: @escaping (String) -> Void) {\n        self.say = say\n        if AdaptiveChrome.installed { return }', updater)
        s = one(s,
            '    func checkByHand() {',
            '    func checkByHand() {\n        if AdaptiveChrome.installed {\n            say?("Search Adaptive updates via update-and-build.sh, not the official updater")\n            return\n        }', updater)
        s = one(s,
            '    func check(then done: @escaping (Release?) -> Void) {',
            '    func check(then done: @escaping (Release?) -> Void) {\n        if AdaptiveChrome.installed { done(nil); return }', updater)
        changes['Updater.swift'] = s

    shipped = kit / 'AdaptiveChrome.swift'
    if not shipped.is_file():
        raise RuntimeError(f"Missing {shipped}")
    # All anchors passed, now write changes atomically per file.
    for name, content in changes.items():
        path = paths[name]
        if path.read_text(encoding='utf8') != content:
            path.write_text(content, encoding='utf8')
    shutil.copy2(shipped, root / 'AdaptiveChrome.swift')
    print('Applied Search Adaptive Chrome v0.4 (6 integration files + module).')
    print('Enable before launch: defaults write com.officecommun.search adaptive.chrome.enabled -bool true')


def main():
    cli = argparse.ArgumentParser()
    cli.add_argument('repo', type=Path)
    args = cli.parse_args()
    try:
        apply(args.repo.resolve(), Path(__file__).resolve().parent)
    except Exception as err:
        print(f'Search Adaptive: upstream changed; stopped safely: {err}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()