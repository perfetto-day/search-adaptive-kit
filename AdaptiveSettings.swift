// Search Adaptive v0.6 — in-browser appearance controls and opt-in mod updates.
// No arbitrary URL or shell text from a website is executed. GitHub repository
// and remote names are fixed, and a user explicitly confirms each build.
import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AdaptivePreferences: ObservableObject {
    static let shared = AdaptivePreferences()
    private static let defaults = Store.settings
    private static func read(_ key: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
    @Published var enabled: Bool { didSet { Self.defaults.set(enabled, forKey: AdaptiveChrome.settingsKey) } }
    @Published var debug: Bool { didSet { Self.defaults.set(debug, forKey: "adaptive.chrome.debug") } }
    @Published var searchTint: Bool { didSet { Self.defaults.set(searchTint, forKey: "adaptive.chrome.searchTint") } }
    @Published var roundedTop: Bool { didSet { Self.defaults.set(roundedTop, forKey: "adaptive.chrome.roundedTop") } }
    @Published var updateChecks: Bool { didSet { Self.defaults.set(updateChecks, forKey: AdaptiveChrome.updateChecksKey) } }

    private init() {
        enabled = Self.read(AdaptiveChrome.settingsKey, fallback: false)
        debug = Self.read("adaptive.chrome.debug", fallback: false)
        searchTint = Self.read("adaptive.chrome.searchTint", fallback: true)
        roundedTop = Self.read("adaptive.chrome.roundedTop", fallback: true)
        updateChecks = Self.read(AdaptiveChrome.updateChecksKey, fallback: true)
    }
}

@MainActor
final class AdaptiveModUpdater: ObservableObject {
    static let shared = AdaptiveModUpdater()
    struct Reference: Hashable, Identifiable {
        let kind: String // branch or tag
        let name: String
        let sha: String
        var id: String { "\(kind):\(name)" }
        var title: String { "\(name) [\(String(sha.prefix(8)))]" }
    }
    private struct GitRef: Decodable {
        let name: String
        let commit: Commit
        struct Commit: Decodable { let sha: String }
    }
    private struct GitHubAPIError: Decodable {
        let message: String?
    }
    @Published private(set) var references: [Reference] = []
    @Published var selectedID = "branch:main"
    @Published private(set) var status = "Choose Check GitHub to list branches and tags."
    @Published private(set) var checking = false
    @Published private(set) var building = false
    @Published private(set) var staged = false
    @Published private(set) var installedSHA = ""

    private var activeProcess: Process?
    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SearchAdaptive", isDirectory: true)
    private init() { refreshInstalled() }

    var selected: Reference? { references.first { $0.id == selectedID } }
    var installedDescription: String {
        installedSHA.isEmpty ? "\(AdaptiveChrome.kitVersion) · local build" :
            "\(AdaptiveChrome.kitVersion) · \(String(installedSHA.prefix(10)))"
    }
    var logURL: URL { root.appendingPathComponent("mod-update.log") }

    private func refreshInstalled() {
        installedSHA = (try? String(contentsOf: root.appendingPathComponent("installed-mod.txt"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        staged = FileManager.default.fileExists(atPath: root.appendingPathComponent("Pending.app").path)
    }

    func checkGitHub() {
        guard !checking && !building else { return }
        checking = true
        status = "Checking perfetto-day/search-adaptive-kit on GitHub…"
        Task {
            do {
                let base = "https://api.github.com/repos/perfetto-day/search-adaptive-kit"
                let branches: [GitRef] = try await fetch("\(base)/branches?per_page=100")
                // Tags are optional. If their endpoint fails, still show the
                // valid branches instead of dropping the entire result.
                var tags: [GitRef] = []
                var tagsWarning: String?
                do { tags = try await fetch("\(base)/tags?per_page=100") }
                catch { tagsWarning = error.localizedDescription }
                let safe = { (name: String) in
                    !name.isEmpty && name.range(of: "^[A-Za-z0-9][A-Za-z0-9._/-]*$", options: .regularExpression) != nil
                        && !name.contains("..") && !name.contains("//") && !name.contains("@{")
                }
                let refs = branches.filter { safe($0.name) }.map { Reference(kind: "branch", name: $0.name, sha: $0.commit.sha) }
                    + tags.filter { safe($0.name) }.map { Reference(kind: "tag", name: $0.name, sha: $0.commit.sha) }
                references = refs.sorted { a, b in
                    if a.kind != b.kind { return a.kind == "branch" }
                    return a.name == "main" || (b.name != "main" && a.name < b.name)
                }
                if !references.contains(where: { $0.id == selectedID }) {
                    selectedID = references.first?.id ?? "branch:main"
                }
                status = references.isEmpty ? "GitHub returned no available refs." : "Found \(references.count) branches and tags. Select an exact revision."
                if let tagsWarning {
                    status += " Tags unavailable: \(tagsWarning)"
                }
            } catch {
                status = "GitHub check failed: \(error.localizedDescription)"
            }
            checking = false
            refreshInstalled()
        }
    }

    private func fetch<T: Decodable>(_ address: String) async throws -> T {
        guard let url = URL(string: address) else {
            throw NSError(domain: "SearchAdaptiveGitHub", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid GitHub API URL."])
        }
        // An explicit refresh shouldn't depend on a possibly stale 304 cache
        // response. GitHub also requires a descriptive User-Agent.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("SearchAdaptiveKit/\(AdaptiveChrome.kitVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "SearchAdaptiveGitHub", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub did not return an HTTP response."])
        }
        guard http.statusCode == 200 else {
            let reason = (try? JSONDecoder().decode(GitHubAPIError.self, from: data))?.message
            let message: String
            if http.statusCode == 429 || http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                if let raw = http.value(forHTTPHeaderField: "X-RateLimit-Reset"),
                   let reset = Double(raw) {
                    let minutes = max(1, Int(ceil((reset - Date().timeIntervalSince1970) / 60)))
                    message = "GitHub API rate limit (HTTP \(http.statusCode)); retry in about \(minutes) min."
                } else {
                    message = "GitHub API rate limit (HTTP \(http.statusCode)); retry later."
                }
            } else {
                message = "GitHub API HTTP \(http.statusCode): \(String((reason ?? "request failed").prefix(160)))"
            }
            throw NSError(domain: "SearchAdaptiveGitHub", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NSError(domain: "SearchAdaptiveGitHub", code: 3,
                          userInfo: [NSLocalizedDescriptionKey:
                            "GitHub returned unexpected JSON (HTTP 200): \(error.localizedDescription)"])
        }
    }

    func downloadAndBuild() {
        guard !building, let target = selected else { return }
        let script = root.appendingPathComponent("Tools/mod-update.command")
        guard FileManager.default.fileExists(atPath: script.path) else {
            status = "Updater helper not installed. Run ./update-and-build.sh from the v0.6 kit once."
            return
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            let log = try FileHandle(forWritingTo: logURL)
            try log.truncate(atOffset: 0)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, "build", target.kind, target.name, target.sha]
            process.standardOutput = log
            process.standardError = log
            building = true
            activeProcess = process
            staged = false
            status = "Downloading \(target.title) and compiling locally. See mod-update.log."
            process.terminationHandler = { [weak self] finished in
                let result = finished.terminationStatus
                try? log.close()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.building = false
                    self.activeProcess = nil
                    self.refreshInstalled()
                    self.status = result == 0 && self.staged
                        ? "Build finished. Review changes, then select Install & Restart."
                        : "Build failed (code \(result)). See mod-update.log. Existing app is unchanged."
                }
            }
            try process.run()
        } catch {
            building = false
            activeProcess = nil
            status = "Could not start update: \(error.localizedDescription)"
        }
    }

    func installAndRestart() {
        guard staged && !building else { return }
        let script = root.appendingPathComponent("Tools/mod-update.command")
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, "install", String(ProcessInfo.processInfo.processIdentifier)]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            status = "Installer could not be started: \(error.localizedDescription)"
        }
    }
}

// Use the same row, rule, switch, and pill as Search's own Settings.
// The parent SettingsPanel wraps these rows in Search's Card/GroupBlock.
@MainActor
struct AdaptiveSettingsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var options = AdaptivePreferences.shared

    var body: some View {
        VStack(spacing: 0) {
            SettingRow(icon: "paintbrush", title: "Adaptive website colors",
                       detail: "Match the tab bar and sidebar to the active website") {
                Switch(on: $options.enabled)
            }
            Rule()
            SettingRow(icon: "magnifyingglass", title: "Adaptive search overlay",
                       detail: "Keep the search field and dimmed toolbar consistent") {
                Switch(on: $options.searchTint)
            }
            Rule()
            SettingRow(icon: "square.on.square", title: "Round page top corners",
                       detail: "Gently round the page below horizontal tabs, without borders") {
                Switch(on: $options.roundedTop)
            }
            Rule()
            SettingRow(icon: "eyeglasses", title: "Show color diagnostics",
                       detail: "Show the page color source and sampled hex value") {
                Switch(on: $options.debug)
            }
            Rule()
            SettingRow(icon: "arrow.triangle.2.circlepath", title: "Check official Search releases",
                       detail: "Announce new versions without replacing this modified build") {
                Switch(on: $options.updateChecks)
            }
        }
    }
}

@MainActor
struct AdaptiveUpdateSettingsPanel: View {
    @ObservedObject private var updater = AdaptiveModUpdater.shared
    @State private var confirmBuild = false
    @State private var confirmInstall = false

    var body: some View {
        VStack(spacing: 0) {
            SettingRow(icon: "shippingbox", title: "Search Adaptive",
                       detail: "Installed: \(updater.installedDescription)",
                       more: "This mod is maintained separately from official Search releases.") {
                Pill("Check GitHub") { updater.checkGitHub() }
                    .disabled(updater.checking || updater.building)
            }
            if !updater.references.isEmpty {
                Rule()
                SettingRow(icon: "point.3.connected.trianglepath.dotted", title: "Choose a revision",
                           detail: "Select a branch or tag and review the exact Git commit", wide: true) {
                    VStack(alignment: .leading, spacing: 9) {
                        Picker("GitHub revision", selection: $updater.selectedID) {
                            ForEach(updater.references) { entry in
                                Text("\(entry.kind): \(entry.title)").tag(entry.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Pill("Download & Build", filled: true) { confirmBuild = true }
                                .disabled(updater.building || updater.selected == nil)
                            if updater.staged {
                                Pill("Install & Restart") { confirmInstall = true }
                                    .disabled(updater.building)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Rule()
            SettingRow(icon: "info.circle", title: "Update status",
                       detail: updater.status,
                       more: "A remote revision is compiled locally only after you approve it. Installation is a separate confirmation. Building untrusted code is unsafe.") {
                if updater.building || updater.checking {
                    ProgressView().controlSize(.small)
                } else {
                    Always(text: updater.staged ? "Ready to install" : "Manual")
                }
            }
        }
        .confirmationDialog("Build and run code from GitHub?", isPresented: $confirmBuild) {
            Button("Download & Build \(updater.selected?.title ?? "")") { updater.downloadAndBuild() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected commit's build scripts will execute locally. Review the source first. Nothing installs until you approve it separately.")
        }
        .confirmationDialog("Replace Search Adaptive and restart?", isPresented: $confirmInstall) {
            Button("Install & Restart") { updater.installAndRestart() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The staged build replaces Search Adaptive.app only after the current app quits. A backup is kept during installation.")
        }
    }
}