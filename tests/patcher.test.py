"""Self-contained non-macOS tests for the overlay's safety and idempotence.

Fixture includes the specific upstream anchors. The complete production Search
source still needs a macOS Swift/Xcode compile (this test doesn't replace it).
"""
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from apply_mod import apply

KIT = Path(__file__).resolve().parents[1]
SOURCES = {
'Tab.swift': '''    func didCommit() {
        popupGesture.clear()
    }
    @Published private(set) var cover: NSImage?
    void test() {
        controller.add(dusk, contentWorld: Web.world, name: DuskRelay.name)
        add(ScrollRelay.script, .atDocumentEnd, mainFrameOnly: true, in: Web.world)
        let controller = web.configuration.userContentController
        Web.release(controller)
        controller.removeAllUserScripts()
    }
''',
'App.swift': '''let tint = (fullscreenTab != nil ? Color.black : cards ? Palette.frame : Palette.ground)
            Omnibox(browser: browser, over: !(browser.active?.isBlank ?? true))
            Page(tab: tab, corner: cards ? Metrics.cardRadius : 0, browser: browser)
            stage
                .modifier(CardEdge(on: cards && !browser.prefs.splitView))
                .padding(.leading, sideOnRight ? farGap + panelRoom : 0)
                TabBar(browser: browser)
                    .transition(.move(edge: .top).combined(with: .opacity))
            .overlay { field }''',
'Side.swift': '''struct SideBar: View {
        .environment(\\.greys, greys)
        .frame(width: width)
                landing ? greys.hover : onFrame ? Palette.frame : Palette.ground
if !onFrame { Rectangle().fill(Palette.hairline).frame(width: 1) }
}
private struct SideRow: View, Equatable {
    @Environment(\\.greys) private var greys
    private var colour: Color {
        if live { return Palette.ink }
        let colour = hovering ? Palette.ink.opacity(0.7) : Palette.muted
        return putAway ? colour.opacity(0.45) : colour
    }
}
struct Door: View {
    @Environment(\\.greys) private var greys
                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.7) : Palette.muted))
}
struct Quiet: View {
    @Environment(\\.greys) private var greys
            .foregroundStyle(hovering ? Palette.ink.opacity(0.7) : Palette.faint)
}
''',
'TabBar.swift': '''struct TabBar: View {
        .animation(Motion.settle, value: browser.tabs.map(\\.id))
    }

    // MARK: - the spaces, one above the other
}
private struct TabPill: View, Equatable {
    @Environment(\\.tabShortcutNumbers) private var shortcutNumbers
    private var ground: some View {
        Rectangle().fill(pinned ? Palette.pinLive : Palette.wash)
            .fill(Palette.wash)
            .fill(Palette.hover)
            .fill(Palette.wash.opacity(0.55))
    }
    private var colour: Color {
        if live { return Palette.ink }
        return hovering ? Palette.ink.opacity(0.7) : Palette.muted
    }
}
/// The address, inside its own tab.
''',
'Omnibox.swift': '''struct Omnibox: View {
    init() {
        self.typing = browser.typing
        self.over = over
    }
    var body: some View {
        Text("x")
        .allowsHitTesting(browser.fieldShowing)
    }
                        .fill(Palette.ground.opacity(0.74))
                        .fill(Palette.ground)
                        refused ? Color.red.opacity(0.35) : Palette.hairline,
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    struct Row: View {
                    .foregroundStyle(Palette.ink)
                    .foregroundStyle(Palette.muted)
                    .fill(Palette.wash)
                    .fill(Palette.hover)
    }
}
private struct SiteIcon: View {
                .foregroundStyle(Palette.muted)
}
private struct SiteChip: View {
                .foregroundStyle(Palette.ink)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
}
private struct SiteOfferRow: View {
                .foregroundStyle(Palette.ink)
                .foregroundStyle(Palette.muted)
                .strokeBorder(Palette.hairline, lineWidth: 1)
                .fill(Palette.hover)
}
/// The breath under the field:
struct AddressField: NSViewRepresentable {
        field.textColor = Palette.NS.ink
        field.placeholderAttributedString = Self.placeholder(words)
    private static func placeholder(_ words: String) -> NSAttributedString {
                .foregroundColor: NSColor(Palette.ink.opacity(0.3)),
    }
    func updateNSView(_ field: Field, context: Context) {
        let coordinator = context.coordinator
        coordinator.browser = browser
        field.placeholderAttributedString = Self.placeholder(words)
    }
}
''',
'Updater.swift': '''    func checkIfDue(then say: @escaping (String) -> Void) {
        self.say = say
        Swap.sweep()
    }
    private func checkIfDue() {
    }
    func checkByHand() {
    }
    func check(then done: @escaping (Release?) -> Void) {
            done(found)
            guard !installsOnItsOwn else { take(found); return }
    }
    func install() {
    }
    private func take(_ release: Release) {
    }
''',
 'Settings.swift': '''    @ViewBuilder
    private func section(_ page: Page) -> some View {
        switch page {
        case .keyboard:
            groups(of: page)
        default:
            groups(of: page)
        }
    }
''',
'Stage.swift': '''struct Page: View {
    var corner: CGFloat = 0
    /// The window, for a tab showing one of Search's own pages
    var browser: Browser?
    func body() {
        WebStage(page: !tab.isWeb || tab.asleep || tab.floating ? nil : tab.web, corner: corner)
    }
}
struct WebStage: NSViewRepresentable {
    let page: NSView?
    var corner: CGFloat = 0
    func updateNSView(_ view: StageView, context: Context) {
        view.corner = corner
        view.show(page)
    }
}
final class StageView: NSView {
    var corner: CGFloat = 0 {
        didSet {
            guard corner != oldValue else { return }
            wantsLayer = true
            layer?.cornerRadius = corner
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = corner > 0
        }
    }
    override func layout() {
        super.layout()
        settle()
    }
}
'''
}


def write_fixture(root):
    src = root/'Sources'/'Search'
    src.mkdir(parents=True)
    for name,data in SOURCES.items(): (src/name).write_text(data)
    return src


def check():
    with TemporaryDirectory() as t:
        repo=Path(t)/'repo'
        src=write_fixture(repo)
        apply(repo,KIT)
        first={p.name:p.read_bytes() for p in src.glob('*.swift')}
        assert 'AdaptiveChromeStyle' in first['Side.swift'].decode()
        assert 'actualAdaptive?.searchScrim' in first['Omnibox.swift'].decode()
        assert 'AdaptiveChromeLive.shared' in first['Omnibox.swift'].decode()
        assert 'AdaptiveChromeSearchContext' in first['App.swift'].decode()
        assert 'AdaptiveChromePalette' in first['AdaptiveChrome.swift'].decode()
        assert 'shade: AdaptiveChrome.parse(shade)' in first['Tab.swift'].decode()
        assert 'Search Adaptive v0.7' in first['Tab.swift'].decode()
        assert 'AdaptiveSettingsPanel(browser: browser)' in first['Settings.swift'].decode()
        assert 'Card { AdaptiveSettingsPanel(browser: browser) }' in first['Settings.swift'].decode()
        assert 'Card { AdaptiveUpdateSettingsPanel() }' in first['Settings.swift'].decode()
        assert 'AdaptiveChromeTopEdge' not in first['App.swift'].decode()
        assert '.padding(.top, AdaptiveChrome.roundedTop' not in first['App.swift'].decode()
        assert 'SettingRow(icon: "paintbrush"' in first['AdaptiveSettings.swift'].decode()
        assert 'Switch(on: $options.enabled)' in first['AdaptiveSettings.swift'].decode()
        assert 'AdaptiveChromeTopShade' in first['App.swift'].decode()
        assert 'AdaptiveSettings' in first['AdaptiveSettings.swift'].decode()
        assert 'topCornersOnly' in first['Stage.swift'].decode()
        assert 'layerMinXMaxYCorner' in first['Stage.swift'].decode()
        assert 'isGeometryFlipped' in first['Stage.swift'].decode()
        assert 'if corner > 0 { updateCornerMask() }' in first['Stage.swift'].decode()
        assert 'AdaptiveChromePageCorners' in first['App.swift'].decode()
        assert 'AdaptiveChromeTopCornerCutouts(browser: browser)' in first['App.swift'].decode()
        # The cutouts must be hosted by TabBar, which Search paints above
        # WKWebView; a stage-attached overlay is invisible on some pages.
        app_source = first['App.swift'].decode()
        assert '.clipShape(AdaptiveChromePageCorners(radius:' in app_source
        assert 'TabBar(browser: browser)\n                    .overlay(alignment: .bottom)' in app_source
        assert '.offset(y: Metrics.cardRadius)' in app_source
        assert app_source.index('AdaptiveChromeTopCornerCutouts(browser: browser)') > app_source.index('TabBar(browser: browser)')
        assert 'ROUND DEBUG' in first['AdaptiveChrome.swift'].decode()
        assert 'if options.debug { Color.pink }' in first['AdaptiveChrome.swift'].decode()
        assert 'struct AdaptiveChromeCornerCutoutShape: Shape' in first['AdaptiveChrome.swift'].decode()
        assert 'AdaptiveChromeSurface(browser: browser, fallback: Palette.ground)' in first['AdaptiveChrome.swift'].decode()
        assert '.padding(.top, chrome.height)' not in first['App.swift'].decode()
        assert 'AdaptiveChromePageCorners: Shape' in first['AdaptiveChrome.swift'].decode()
        assert 'browser.peekInFront' in first['AdaptiveChrome.swift'].decode()
        assert 'Color.black.opacity(0.22)' in first['AdaptiveChrome.swift'].decode()
        assert 'updateChecksEnabled' in first['Updater.swift'].decode()
        assert 'Rebuild Search Adaptive' in first['Updater.swift'].decode()
        assert 'if AdaptiveChrome.installed' in first['Updater.swift'].decode()
        apply(repo,KIT)
        second={p.name:p.read_bytes() for p in src.glob('*.swift')}
        assert first==second,'Second application changed the source'
    with TemporaryDirectory() as t:
        repo=Path(t)/'repo'
        src=write_fixture(repo)
        (src/'Updater.swift').write_text('changed upstream declaration')
        before={p.name:p.read_bytes() for p in src.glob('*.swift')}
        try:apply(repo,KIT)
        except RuntimeError:pass
        else:raise AssertionError('Broken upstream anchor did not fail')
        after={p.name:p.read_bytes() for p in src.glob('*.swift')}
        assert before==after,'Partially wrote sources before failing'
    print('PASS: idempotent patch, all hooks inserted, fail-closed on upstream drift')

if __name__=='__main__':check()