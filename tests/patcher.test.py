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
            Omnibox(browser: browser, over: !(browser.active?.isBlank ?? true))''',
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
    }
    func checkByHand() {
    }
    func check(then done: @escaping (Release?) -> Void) {
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
        assert 'adaptive?.searchScrim' in first['Omnibox.swift'].decode()
        assert 'AdaptiveChromeSearchContext' in first['App.swift'].decode()
        assert 'AdaptiveChromePalette' in first['AdaptiveChrome.swift'].decode()
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