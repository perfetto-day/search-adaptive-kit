#!/usr/bin/env python3
"""Search Adaptive v0.7 overlay. Validates all anchors before touching files.

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
    paths = {n: root / n for n in ['Tab.swift', 'App.swift', 'Side.swift', 'TabBar.swift', 'Omnibox.swift', 'Updater.swift', 'Stage.swift', 'Settings.swift']}
    for file in paths.values():
        if not file.is_file():
            raise RuntimeError(f"Not a Search source tree: missing {file}")
    changes = {n: p.read_text(encoding='utf8') for n, p in paths.items()}

    tab = paths['Tab.swift']; s = changes['Tab.swift']
    if 'private let adaptiveChromeRelay' not in s:
        s = one(s,
            '    @Published private(set) var cover: NSImage?',
            '''    @Published private(set) var cover: NSImage?

    // Search Adaptive v0.7. Only the active Tab's report is drawn in the chrome.
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
        # Window-level top strip shade is composited above tabs/buttons but
        # before the search field. A TabBar-only overlay missed native chrome.
        s = one(s,
            '            .overlay { field }',
            """            .overlay(alignment: .top) {
                if AdaptiveChrome.roundedTop && !cards && !browser.prefs.sidebar && !browser.prefs.splitView && fullscreenTab == nil {
                    AdaptiveChromeTopCornerCutouts(browser: browser)
                        .frame(height: Metrics.cardRadius)
                        .padding(.top, chrome.height)
                        .ignoresSafeArea()
                }
            }
            .overlay(alignment: .top) {
                if !browser.prefs.sidebar && fullscreenTab == nil {
                    AdaptiveChromeTopShade(browser: browser)
                        .frame(height: chrome.height)
                        .ignoresSafeArea()
                }
            }
            .overlay { field }""", app)
        # Add a second clip around the *whole* stage, not just its WKWebView.
        # This also masks SwiftUI reader/cover overlays, without any border.
        s = one(s,
            '''            stage
                .modifier(CardEdge(on: cards && !browser.prefs.splitView))''',
            """            stage
                .modifier(CardEdge(on: cards && !browser.prefs.splitView))
                .clipShape(AdaptiveChromePageCorners(radius:
                    AdaptiveChrome.roundedTop && !cards && !browser.prefs.sidebar && !browser.prefs.splitView && fullscreenTab == nil
                    ? Metrics.cardRadius : 0))""", app)
        changes['App.swift'] = s
    if 'topCornersOnly: AdaptiveChrome.roundedTop' not in s:
        s = one(s,
            'Page(tab: tab, corner: cards ? Metrics.cardRadius : 0, browser: browser)',
            '''Page(tab: tab,
                 corner: cards || (AdaptiveChrome.roundedTop && !browser.prefs.sidebar && fullscreenTab == nil) ? Metrics.cardRadius : 0,
                 topCornersOnly: AdaptiveChrome.roundedTop && !cards && !browser.prefs.sidebar && fullscreenTab == nil,
                 browser: browser)''', app)
        changes['App.swift'] = s

    # Native AppKit rounding: SwiftUI-only clipping can leave WKWebView square.
    # Preserve the card's four-corner behavior and round only the top corners
    # of an edge-to-edge page beneath the horizontal tab bar.
    stage = paths['Stage.swift']; s = changes['Stage.swift']
    if 'topCornersOnly: Bool' not in s:
        s = one(s,
            '    var corner: CGFloat = 0\n    /// The window, for a tab showing',
            '    var corner: CGFloat = 0\n    var topCornersOnly: Bool = false\n    /// The window, for a tab showing', stage)
        s = one(s,
            'WebStage(page: !tab.isWeb || tab.asleep || tab.floating ? nil : tab.web, corner: corner)',
            'WebStage(page: !tab.isWeb || tab.asleep || tab.floating ? nil : tab.web, corner: corner, topCornersOnly: topCornersOnly)', stage)
        s = one(s,
            'struct WebStage: NSViewRepresentable {\n    let page: NSView?\n    var corner: CGFloat = 0',
            'struct WebStage: NSViewRepresentable {\n    let page: NSView?\n    var corner: CGFloat = 0\n    var topCornersOnly: Bool = false', stage)
        s = one(s,
            '        view.corner = corner\n        view.show(page)',
            '        view.topCornersOnly = topCornersOnly\n        view.corner = corner\n        view.show(page)', stage)
        s = one(s,
            '''    var corner: CGFloat = 0 {
        didSet {
            guard corner != oldValue else { return }
            wantsLayer = true
            layer?.cornerRadius = corner
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = corner > 0
        }
    }''',
            '''    var corner: CGFloat = 0 {
        didSet { if corner != oldValue { updateCornerMask() } }
    }
    var topCornersOnly = false {
        didSet { if topCornersOnly != oldValue { updateCornerMask() } }
    }

    private func updateCornerMask() {
        wantsLayer = true
        layer?.cornerRadius = corner
        layer?.cornerCurve = .continuous
        // Account for layers whose Y axis is inverted by AppKit hosting.
        // Never select the bottom two corners for the top-only page style.
        if topCornersOnly {
            layer?.maskedCorners = layer?.isGeometryFlipped == true
                ? [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                : [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else {
            layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        layer?.masksToBounds = corner > 0
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if corner > 0 { updateCornerMask() }
    }''', stage)
        s = one(s,
            '''    override func layout() {
        super.layout()
        settle()
    }''',
            '''    override func layout() {
        super.layout()
        if corner > 0 { updateCornerMask() }
        settle()
    }''', stage)
        changes['Stage.swift'] = s

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
        .modifier(AdaptiveChromeStyle(browser: browser, greys: .white, diagnostic: true, shadeSearch: false))
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
    if 'actualAdaptive?.searchScrim' not in s:
        s = one(s, 'struct Omnibox: View {',
            '''@MainActor
struct Omnibox: View {
    @Environment(\\.adaptiveChromePalette) private var adaptive
    @Environment(\\.colorScheme) private var inheritedScheme
    @ObservedObject private var adaptiveLive: AdaptiveChromeLive
    private var actualAdaptive: AdaptiveChromePalette? { adaptiveLive.palette ?? adaptive }''', omnibox)
        s = one(s,
            '        self.typing = browser.typing\n        self.over = over',
            '        self.typing = browser.typing\n        _adaptiveLive = ObservedObject(wrappedValue: AdaptiveChromeLive.shared(for: browser))\n        self.over = over', omnibox)
        s = one(s,
            '        .allowsHitTesting(browser.fieldShowing)',
            '''        .allowsHitTesting(browser.fieldShowing)
        .environment(\\.adaptiveChromePalette, actualAdaptive)
        .environment(\\.colorScheme, actualAdaptive.map { $0.dark ? ColorScheme.dark : .light } ?? inheritedScheme)''', omnibox)
        s = one(s,
            '                        .fill(Palette.ground.opacity(0.74))',
            '                        .fill(actualAdaptive?.searchScrim ?? Palette.ground.opacity(0.74))', omnibox)
        s = one(s,
            '                        .fill(Palette.ground)',
            '                        .fill(actualAdaptive?.searchField ?? Palette.ground)', omnibox)
        s = one(s,
            '                        refused ? Color.red.opacity(0.35) : Palette.hairline,',
            '                        refused ? Color.red.opacity(0.35) : (actualAdaptive?.hairline ?? Palette.hairline),', omnibox)
        s = one(s,
            '        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))',
            '        .background(actualAdaptive?.searchField ?? Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))', omnibox)
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

    settings = paths['Settings.swift']; s = changes['Settings.swift']
    if 'AdaptiveSettingsPanel(browser: browser)' not in s:
        s = one(s,
            '''        case .keyboard:
            groups(of: page)''',
            '''        case .appearance:
            groups(of: page)
            GroupBlock(title: "Search Adaptive", icon: "paintbrush.pointed") {
                Card { AdaptiveSettingsPanel(browser: browser) }
            }
            GroupBlock(title: "Mod updates", icon: "arrow.triangle.2.circlepath") {
                Card { AdaptiveUpdateSettingsPanel() }
            }
        case .keyboard:
            groups(of: page)''', settings)
        changes['Settings.swift'] = s

    # Keep upstream release checks on by default; block binary replacement.
    updater = paths['Updater.swift']; s = changes['Updater.swift']
    if 'AdaptiveChrome.updateChecksEnabled' not in s:
        s = one(s,
            '        self.say = say\n        Swap.sweep()',
            '        self.say = say\n        if AdaptiveChrome.installed && !AdaptiveChrome.updateChecksEnabled { return }\n        Swap.sweep()', updater)
        s = one(s,
            '    private func checkIfDue() {',
            '    private func checkIfDue() {\n        if AdaptiveChrome.installed && !AdaptiveChrome.updateChecksEnabled { return }', updater)
        s = one(s,
            '            done(found)\n            guard !installsOnItsOwn else { take(found); return }',
            '''            done(found)
            if AdaptiveChrome.installed {
                if case .waiting(let known) = stage, known == found { return }
                stage = .waiting(found)
                say?("Search \\(found.version) is available — rebuild Search Adaptive with update-and-build.sh")
                return
            }
            guard !installsOnItsOwn else { take(found); return }''', updater)
        s = one(s,
            '    func checkByHand() {',
            '''    func checkByHand() {
        if AdaptiveChrome.installed, case .waiting(let known) = stage {
            say?("Search \\(known.version) is available — rebuild with update-and-build.sh")
            return
        }''', updater)
        s = one(s,
            '    func install() {',
            '''    func install() {
        if AdaptiveChrome.installed {
            say?("Rebuild Search Adaptive using update-and-build.sh to preserve adaptive colors")
            return
        }''', updater)
        s = one(s,
            '    private func take(_ release: Release) {',
            '    private func take(_ release: Release) {\n        if AdaptiveChrome.installed { return }', updater)
        changes['Updater.swift'] = s

    modules = ['AdaptiveChrome.swift', 'AdaptiveSettings.swift']
    for module in modules:
        if not (kit / module).is_file():
            raise RuntimeError(f"Missing {kit / module}")
    # All anchors passed, now write changes atomically per file.
    for name, content in changes.items():
        path = paths[name]
        if path.read_text(encoding='utf8') != content:
            path.write_text(content, encoding='utf8')
    for module in modules:
        shutil.copy2(kit / module, root / module)
    print('Applied Search Adaptive Chrome v0.7 (8 integration files + 2 modules).')
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