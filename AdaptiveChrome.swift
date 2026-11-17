// Search Adaptive Chrome v0.6 — single optional module, no upstream Design.swift edits.
// All color and modal-overlay information stays on the Mac.
import AppKit
import Combine
import SwiftUI
import WebKit

struct AdaptiveChromeReport: Equatable {
    var hex: String = ""
    var dim: Double = 0
    var shade: String = "#000000"
    var source: String = "none"
    var snapshot: Bool = false
}

@MainActor
enum AdaptiveChrome {
    static let installed = true // Never install a stock Search binary over our app.
    static let kitVersion = "v0.6"
    static let colorTransition: Animation = .easeInOut(duration: 0.24)
    static let settingsKey = "adaptive.chrome.enabled"
    // Notifications about official Search releases are on by default. Never
    // install an official binary over the modified application.
    static let updateChecksKey = "adaptive.chrome.updateChecks"
    static var updateChecksEnabled: Bool {
        Store.settings.object(forKey: updateChecksKey) as? Bool ?? true
    }
    static var debug: Bool { AdaptivePreferences.shared.debug }
    static var enabled: Bool { AdaptivePreferences.shared.enabled }
    static var searchTint: Bool { AdaptivePreferences.shared.searchTint }
    static var roundedTop: Bool { AdaptivePreferences.shared.roundedTop }

    nonisolated static func parse(_ hex: String) -> NSColor? {
        guard hex.count == 7, hex.first == "#",
              let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255,
                       green: CGFloat((v >> 8) & 255) / 255,
                       blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    nonisolated static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ x: CGFloat) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    nonisolated static func dark(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        return luminance < 0.22
    }

    nonisolated static func mix(_ base: NSColor, _ other: NSColor, amount: CGFloat) -> Color {
        guard let a = base.usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return Color(nsColor: base) }
        let t = min(1, max(0, amount)), u = 1 - t
        return Color(nsColor: NSColor(srgbRed: a.redComponent * u + b.redComponent * t,
                                      green: a.greenComponent * u + b.greenComponent * t,
                                      blue: a.blueComponent * u + b.blueComponent * t, alpha: 1))
    }

    // Adjust HSL lightness while preserving the site's hue, rather than washing
    // colorful dark surfaces towards neutral grey/white. Used for chrome UI
    // accents only: the chrome background remains the unmodified page color.
    nonisolated static func tone(_ base: NSColor, lightness deltaL: Double, saturation multiplier: Double = 1) -> Color {
        guard let rgb = base.usingColorSpace(.sRGB) else { return Color(nsColor: base) }
        let r = Double(rgb.redComponent), g = Double(rgb.greenComponent), b = Double(rgb.blueComponent)
        let upper = max(r, max(g, b)), lower = min(r, min(g, b)), spread = upper - lower
        let light = (upper + lower) / 2
        let saturation = spread == 0 ? 0 : spread / (1 - abs(2 * light - 1))
        var hue = 0.0
        if spread > 0.00001 {
            if upper == r { hue = ((g - b) / spread).truncatingRemainder(dividingBy: 6) }
            else if upper == g { hue = (b - r) / spread + 2 }
            else { hue = (r - g) / spread + 4 }
        }
        hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        let targetL = min(0.985, max(0.015, light + deltaL))
        let targetS = min(0.95, max(0, saturation * multiplier))
        let chroma = (1 - abs(2 * targetL - 1)) * targetS
        let x = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let minChannel = targetL - chroma / 2
        let pair: (Double, Double, Double)
        switch hue {
        case ..<60: pair = (chroma, x, 0)
        case ..<120: pair = (x, chroma, 0)
        case ..<180: pair = (0, chroma, x)
        case ..<240: pair = (0, x, chroma)
        case ..<300: pair = (x, 0, chroma)
        default: pair = (chroma, 0, x)
        }
        return Color(nsColor: NSColor(srgbRed: pair.0 + minChannel,
                                      green: pair.1 + minChannel,
                                      blue: pair.2 + minChannel, alpha: 1))
    }

    // Sample a tiny strip only if CSS cannot identify painted backgrounds.
    // Reading a full-page snapshot here would make busy pages stutter.
    nonisolated static func sample(_ image: CGImage) -> String? {
        let width = 64, height = 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var buckets: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for i in 0..<(width * height) {
            let r = Int(pixels[4*i]), g = Int(pixels[4*i+1]), b = Int(pixels[4*i+2])
            let key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)
            let old = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (old.n+1, old.r+r, old.g+g, old.b+b)
        }
        guard let bucket = buckets.values.max(by: { $0.n < $1.n }), bucket.n > 0 else { return nil }
        return String(format: "#%02x%02x%02x", bucket.r/bucket.n, bucket.g/bucket.n, bucket.b/bucket.n)
    }
}

// The whole UI uses a *tinted* palette, not merely a light/dark switch.
struct AdaptiveChromePalette {
    let background: Color
    let active: Color
    let hover: Color
    let tile: Color
    let pin: Color
    let ink: Color
    let muted: Color
    let hairline: Color
    let searchScrim: Color
    let searchField: Color
    let inkNS: NSColor
    let dark: Bool

    init(_ base: NSColor) {
        let dark = AdaptiveChrome.dark(base)
        self.dark = dark
        // Exactly the detected page-top color: never tone the ground itself.
        background = Color(nsColor: base)
        active = AdaptiveChrome.tone(base, lightness: dark ? 0.068 : -0.045, saturation: 0.94)
        hover = AdaptiveChrome.tone(base, lightness: dark ? 0.042 : -0.027, saturation: 0.95)
        tile = AdaptiveChrome.tone(base, lightness: dark ? 0.026 : -0.015, saturation: 0.95)
        pin = AdaptiveChrome.tone(base, lightness: dark ? 0.088 : -0.065, saturation: 0.92)
        inkNS = dark ? NSColor.white : NSColor.black
        ink = Color(nsColor: inkNS).opacity(dark ? 0.92 : 0.87)
        muted = Color(nsColor: inkNS).opacity(dark ? 0.62 : 0.58)
        hairline = AdaptiveChrome.tone(base, lightness: dark ? 0.11 : -0.105, saturation: 0.9)
        // On light pages, a gentle neutral shadow leaves the input visibly white.
        // Omnibox should shade in the SAME direction as the visible page, not
        // follow a user-selected browser appearance unrelated to the website.
        searchScrim = dark ? Color.black.opacity(0.60) : Color.black.opacity(0.12)
        // In a light theme the page is already lightened by the search scrim.
        // The input must remain a brighter *surface* (not a grey tone of it).
        searchField = dark
            ? AdaptiveChrome.tone(base, lightness: 0.105, saturation: 0.68)
            : AdaptiveChrome.mix(base, .white, amount: 0.96)
    }

    var greys: Greys { Greys(wash: active, hover: hover, tile: tile, pinLive: pin) }
}

private struct AdaptiveChromePaletteKey: EnvironmentKey {
    static let defaultValue: AdaptiveChromePalette? = nil
}
extension EnvironmentValues {
    var adaptiveChromePalette: AdaptiveChromePalette? {
        get { self[AdaptiveChromePaletteKey.self] }
        set { self[AdaptiveChromePaletteKey.self] = newValue }
    }
}

// Follows the active tab without putting the entire tab strip behind an `if`.
// SwiftUI therefore retains its view identity on new tab/close/switch.
@MainActor
final class AdaptiveChromeLive: ObservableObject {
    @Published private(set) var report = AdaptiveChromeReport()
    // A single observer per Browser is shared by the toolbar, sidebar and
    // Omnibox. Separate StateObjects could race when the new-tab field opens:
    // the toolbar would retain the dark page while the search field reset to
    // Search's neutral light appearance.
    private final class OwnerBox {
        weak var browser: Browser?
        init(_ browser: Browser) { self.browser = browser }
    }
    private static var models: [ObjectIdentifier: (owner: OwnerBox, live: AdaptiveChromeLive)] = [:]
    private static var remembered: [ObjectIdentifier: AdaptiveChromeReport] = [:]

    static func shared(for browser: Browser) -> AdaptiveChromeLive {
        models = models.filter { $0.value.owner.browser != nil }
        let id = ObjectIdentifier(browser)
        if let existing = models[id], existing.owner.browser === browser { return existing.live }
        let live = AdaptiveChromeLive()
        live.follow(browser.active, browser: browser)
        models[id] = (OwnerBox(browser), live)
        return live
    }
    private weak var watched: Tab?
    private var browserID: ObjectIdentifier?
    private var subscription: AnyCancellable?

    func follow(_ tab: Tab?, browser: Browser) {
        let id = ObjectIdentifier(browser)
        let changedTab = watched !== tab || browserID != id
        if changedTab {
            subscription = nil
            watched = tab
            browserID = id
        }
        // Retain only the background: an old modal must NOT continue shading
        // the new-tab search or the new page.
        let current = tab?.adaptiveChromeReport ?? AdaptiveChromeReport()
        if !current.hex.isEmpty {
            Self.remembered[id] = AdaptiveChromeReport(hex: current.hex, source: "remembered")
        }
        let next: AdaptiveChromeReport
        if !current.hex.isEmpty { next = current }
        else if browser.fieldShowing, let cached = Self.remembered[id] { next = cached }
        else { next = current }
        if report != next { withAnimation(AdaptiveChrome.colorTransition) { report = next } }

        if changedTab {
            subscription = tab?.$adaptiveChromeReport.dropFirst().sink { [weak self, weak browser] next in
                guard let self, let browser else { return }
                self.followReport(next, browser: browser)
            }
        }
    }

    private func followReport(_ next: AdaptiveChromeReport, browser: Browser) {
        let id = ObjectIdentifier(browser)
        if !next.hex.isEmpty {
            Self.remembered[id] = AdaptiveChromeReport(hex: next.hex, source: "remembered")
        }
        let resolved: AdaptiveChromeReport
        if !next.hex.isEmpty { resolved = next }
        else if browser.fieldShowing, let cached = Self.remembered[id] { resolved = cached }
        else { resolved = next }
        if report != resolved { withAnimation(AdaptiveChrome.colorTransition) { report = resolved } }
    }

    var palette: AdaptiveChromePalette? {
        guard AdaptiveChrome.enabled, let color = AdaptiveChrome.parse(report.hex) else { return nil }
        return AdaptiveChromePalette(color)
    }
    var dim: Double { AdaptiveChrome.enabled ? min(0.85, max(0, report.dim)) : 0 }
    var shade: Color { Color(nsColor: AdaptiveChrome.parse(report.shade) ?? NSColor.black) }
}

@MainActor
struct AdaptiveChromeSurface: View {
    @ObservedObject var browser: Browser
    let fallback: Color
    @ObservedObject private var live: AdaptiveChromeLive
    @ObservedObject private var options = AdaptivePreferences.shared

    init(browser: Browser, fallback: Color) {
        self.browser = browser
        self.fallback = fallback
        _live = ObservedObject(wrappedValue: AdaptiveChromeLive.shared(for: browser))
    }

    var body: some View {
        (live.palette?.background ?? fallback)
            .animation(AdaptiveChrome.colorTransition, value: live.report.hex)
            .onAppear { live.follow(browser.active, browser: browser) }
            .onChange(of: browser.activeID) { _, _ in live.follow(browser.active, browser: browser) }
            .onChange(of: browser.fieldShowing) { _, _ in live.follow(browser.active, browser: browser) }
    }
}

// Stable modifier. It updates color, hover colors and contrast in-place.
// The modal overlay is painted *over* native controls, as sites shade their own UI.
@MainActor
struct AdaptiveChromeStyle: ViewModifier {
    @ObservedObject var browser: Browser
    let greys: Greys
    let diagnostic: Bool
    let shadeSearch: Bool
    init(browser: Browser, greys: Greys, diagnostic: Bool = false, shadeSearch: Bool = true) {
        self.browser = browser
        self.greys = greys
        self.diagnostic = diagnostic
        self.shadeSearch = shadeSearch
        _live = ObservedObject(wrappedValue: AdaptiveChromeLive.shared(for: browser))
    }
    @Environment(\.colorScheme) private var inheritedScheme
    @ObservedObject private var live: AdaptiveChromeLive
    @ObservedObject private var options = AdaptivePreferences.shared

    func body(content: Content) -> some View {
        content
            .environment(\.greys, live.palette?.greys ?? greys)
            .environment(\.adaptiveChromePalette, live.palette)
            .environment(\.colorScheme, live.palette.map { $0.dark ? ColorScheme.dark : .light } ?? inheritedScheme)
            .overlay {
                if live.dim > 0.01 {
                    live.shade.opacity(live.dim).allowsHitTesting(false)
                }
            }
            .overlay {
                // Search already shades the WebView; match that exact tint on
                // the native chrome too. Keep the overlay mounted for a fade.
                (live.palette?.searchScrim ?? (inheritedScheme == .dark ? Color.black.opacity(0.60) : Color.white.opacity(0.60)))
                    .opacity(shadeSearch && options.enabled && options.enabled && options.searchTint && browser.fieldShowing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.20), value: browser.fieldShowing)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                if diagnostic && AdaptiveChrome.debug {
                    Text("\(live.report.source): \(live.report.hex.isEmpty ? "—" : live.report.hex)  shade \(Int(live.dim * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.black.opacity(0.75), in: Capsule())
                        .padding(.trailing, 8)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { live.follow(browser.active, browser: browser) }
            .onChange(of: browser.activeID) { _, _ in live.follow(browser.active, browser: browser) }
            .onChange(of: browser.fieldShowing) { _, _ in live.follow(browser.active, browser: browser) }
    }
}


// A faint, top-only outline makes the native rounding visible even when the
// WebKit page has exactly the same background color as the adjacent toolbar.
struct AdaptiveChromeTopEdge: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = min(10, rect.width / 3)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: radius))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: radius, y: 0), radius: radius)
        path.addLine(to: CGPoint(x: max(radius, rect.maxX - radius), y: 0))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: 0), tangent2End: CGPoint(x: rect.maxX, y: radius), radius: radius)
        return path
    }
}

// Covers the *entire* top strip after Search has composed its tabs, icons and
// buttons, but before the omnibox is presented. Unlike a TabBar background it
// therefore shades tab glyphs and hover states as well as the strip itself.
@MainActor
struct AdaptiveChromeTopShade: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var live: AdaptiveChromeLive
    @ObservedObject private var options = AdaptivePreferences.shared
    @Environment(\.colorScheme) private var scheme

    init(browser: Browser) {
        self.browser = browser
        _live = ObservedObject(wrappedValue: AdaptiveChromeLive.shared(for: browser))
    }
    var body: some View {
        (live.palette?.searchScrim ?? (scheme == .dark ? Color.black.opacity(0.60) : Color.white.opacity(0.60)))
            .opacity(options.enabled && options.searchTint && browser.fieldShowing ? 1 : 0)
            .animation(.easeInOut(duration: 0.20), value: browser.fieldShowing)
            .allowsHitTesting(false)
            .onAppear { live.follow(browser.active, browser: browser) }
            .onChange(of: browser.activeID) { _, _ in live.follow(browser.active, browser: browser) }
    }
}

// The omnibox shares the active page palette, without shading the entire
// overlay view. It must be mounted even when the page has no color yet.
@MainActor
struct AdaptiveChromeSearchContext: ViewModifier {
    @ObservedObject var browser: Browser
    @Environment(\.colorScheme) private var inheritedScheme
    @ObservedObject private var live: AdaptiveChromeLive
    @ObservedObject private var options = AdaptivePreferences.shared

    init(browser: Browser) {
        self.browser = browser
        _live = ObservedObject(wrappedValue: AdaptiveChromeLive.shared(for: browser))
    }

    func body(content: Content) -> some View {
        content
            .environment(\.adaptiveChromePalette, live.palette)
            .environment(\.colorScheme, live.palette.map { $0.dark ? ColorScheme.dark : .light } ?? inheritedScheme)
            .onAppear { live.follow(browser.active, browser: browser) }
            .onChange(of: browser.activeID) { _, _ in live.follow(browser.active, browser: browser) }
            .onChange(of: browser.fieldShowing) { _, _ in live.follow(browser.active, browser: browser) }
    }
}

// Local WebKit-only bridge: only {color, dim, source, snapshot} is passed.
final class AdaptiveChromeRelay: NSObject, WKScriptMessageHandler {
    static let name = "searchAdaptiveChrome"
    weak var tab: Tab?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { tab?.receiveAdaptiveChrome(body) }
    }

    static let script = #"""
    (() => {
      if (globalThis.__searchAdaptiveChromeV2) return;
      globalThis.__searchAdaptiveChromeV2 = true;
      const sender = globalThis.webkit?.messageHandlers?.searchAdaptiveChrome;
      if (!sender || !document.documentElement) return;
      const fractions = [0.01, 0.09, 0.22, 0.5, 0.78, 0.91, 0.99];
      let scheduled = false, last = '';
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 1;
      const ctx = canvas.getContext('2d', {willReadFrequently:true});
      const colors = new Map();
      function rgba(css) {
        if (!ctx || !css || css === 'transparent') return null;
        if (colors.has(css)) return colors.get(css);
        let result = null;
        try {
          // Canvas converts modern CSS colors (including P3/oklch) to sRGB.
          if (CSS.supports('color', css)) {
            ctx.clearRect(0, 0, 1, 1);
            ctx.fillStyle = css;
            ctx.fillRect(0, 0, 1, 1);
            const p = ctx.getImageData(0,0,1,1).data;
            if (p[3] > 1) result = [p[0], p[1], p[2], p[3]/255];
          }
        } catch (_) {}
        if (colors.size > 96) colors.clear();
        colors.set(css, result);
        return result;
      }
      function hex(v) {
        return '#' + v.slice(0,3).map(x => Math.max(0,Math.min(255,Math.round(x))).toString(16).padStart(2,'0')).join('');
      }
      function composite(top, behind) {
        if (!top) return behind;
        if (!behind) return top;
        const ta = top[3], ba = behind[3];
        const a = ta + ba * (1-ta);
        if (a < .001) return null;
        return [0,1,2].map(i => (top[i]*ta + behind[i]*ba*(1-ta))/a).concat(a);
      }
      function backdrop() {
        let alpha = 0, color = '#000000';
        const w = innerWidth, h = innerHeight;
        const list = new Set();
        const pts = [[5,5],[w-5,5],[5,h-5],[w-5,h-5],[w/2,h/2],[w/2,8]];
        for (const [x,y] of pts) {
          for (const el of document.elementsFromPoint(Math.max(0,x),Math.max(0,y))) {
            if (!(el instanceof Element) || list.has(el)) continue;
            const s = getComputedStyle(el), r = el.getBoundingClientRect();
            const c = rgba(s.backgroundColor);
            if (s.position === 'fixed' && r.width >= w*0.88 && r.height >= h*0.85 &&
                c && c[3]*Number(s.opacity) > .07 && c[3]*Number(s.opacity) < .91 &&
                s.pointerEvents !== 'none') {
              list.add(el);
              const amount = c[3]*Number(s.opacity);
              if (amount > alpha) { alpha = amount; color = hex(c); }
            }
          }
        }
        for (const dialog of document.querySelectorAll('dialog[open]')) {
          try {
            if (!dialog.matches(':modal')) continue;
            const c = rgba(getComputedStyle(dialog,'::backdrop').backgroundColor);
            if (c && c[3] > alpha) { alpha = c[3]; color = hex(c); }
          } catch (_) {}
        }
        return {list, alpha: Math.min(0.78, alpha), color};
      }
      function sampleAt(x, y, skipped) {
        let stack = document.elementsFromPoint(x,y);
        let el = stack.find(item => item instanceof Element && !skipped.has(item) &&
          !item.closest('dialog[open], [role="dialog"][aria-modal="true"]'));
        if (!el) el = document.body || document.documentElement;
        let sum = null, complex = false, depth = 0;
        for (; el && depth < 24; el = el.parentElement, depth++) {
          const st = getComputedStyle(el);
          if (st.display === 'none' || st.visibility === 'hidden') continue;
          const c = rgba(st.backgroundColor);
          if (st.backgroundImage && st.backgroundImage !== 'none' && el.getBoundingClientRect().width > innerWidth * .65) complex = true;
          if (c) {
            const opacity = Number(st.opacity);
            const next = [c[0],c[1],c[2],c[3] * (Number.isFinite(opacity) ? opacity : 1)];
            sum = composite(sum, next);
          }
          if (sum?.[3] >= .995) break;
        }
        return {c: sum && sum[3] > .85 ? sum : null, complex};
      }
      function pick() {
        const w = Math.max(1,document.documentElement.clientWidth), h = Math.max(1,innerHeight);
        const shaded = backdrop(), samples = [];
        let complex = false;
        const ys = [1, 4, 10, 22].map(y => Math.min(h-1,Math.max(0,y)));
        for (const y of ys) for (const f of fractions) {
          const item = sampleAt(Math.round((w-1)*f),y,shaded.list);
          complex ||= item.complex;
          if (item.c) samples.push(item.c);
        }
        // A dominant cluster, not a single colored button/pixel.
        let best = null, votes = 0;
        for (const s of samples) {
          const similar = samples.filter(c => Math.abs(c[0]-s[0])+Math.abs(c[1]-s[1])+Math.abs(c[2]-s[2]) < 55);
          if (similar.length > votes) { best = similar; votes = similar.length; }
        }
        if (best && votes >= 5 && votes >= samples.length * .38) {
          return {color:hex([0,1,2].map(i => best.reduce((a,c)=>a+c[i],0)/best.length)),dim:shaded.alpha,shade:shaded.color,source:'dom',snapshot:shaded.alpha < .01};
        }
        // Prefer the real CSS canvas to meta theme-color; a site may declare
        // its accent (bright cyan) as theme-color on a nearly black page.
        for (const el of [document.body,document.documentElement]) {
          if (!el) continue;
          const c = rgba(getComputedStyle(el).backgroundColor);
          if (c && c[3] > .95) return {color:hex(c),dim:shaded.alpha,shade:shaded.color,source:'body',snapshot:false};
        }
        return {color:'',dim:shaded.alpha,shade:shaded.color,source:complex?'gradient':'snapshot',snapshot:!shaded.alpha};
      }
      function read() {
        scheduled = false;
        try {
          const r = pick(), key = JSON.stringify(r);
          if (key !== last) {last = key; sender.postMessage(r);}
        } catch (_) {}
      }
      function schedule() {
        if (scheduled) return;
        scheduled = true;
        setTimeout(read, 95);
      }
      addEventListener('scroll', schedule, {passive:true});
      addEventListener('resize',schedule,{passive:true});
      addEventListener('pageshow',schedule);
      addEventListener('popstate',schedule);
      document.addEventListener('DOMContentLoaded',schedule,{once:true});
      new MutationObserver(schedule).observe(document.documentElement,{
        subtree:true, childList:true, attributes:true,
        attributeFilter:['class','style','open','data-state','aria-modal','aria-hidden']
      });
      schedule();
    })();
    """#
}