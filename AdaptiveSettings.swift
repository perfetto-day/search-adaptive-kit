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
                let tags: [GitRef] = try await fetch("\(base)/tags?per_page=100")
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
            } catch {
                status = "GitHub check failed: \(error.localizedDescription)"
            }
            checking = false
            refreshInstalled()
        }
    }

    private func fetch<T: Decodable>(_ address: String) async throws -> T {
        let url = URL(string: address)!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "SearchAdaptiveGitHub", code: 1, userInfo: [NSLocalizedDescriptionKey: "GitHub API response was not 200"])
        }
        return try JSONDecoder().decode(T.self, from: data)
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

@MainActor
struct AdaptiveSettingsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var options = AdaptivePreferences.shared
    @ObservedObject private var updater = AdaptiveModUpdater.shared
    @State private var confirmBuild = false
    @State private var confirmInstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Adaptive website colors", isOn: $options.enabled)
            Toggle("Adaptive search overlay", isOn: $options.searchTint)
            Toggle("Round page top corners", isOn: $options.roundedTop)
            Toggle("Show color diagnostics", isOn: $options.debug)
            Toggle("Check official Search releases", isOn: $options.updateChecks)
            Text("These switches control the same preferences as toggle-mode.command. Reload open pages after enabling colors; restart for corner geometry.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)

            Divider()
            Text("Search Adaptive updates").font(.system(size: 13, weight: .semibold))
            Text("Installed: \(updater.installedDescription)")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            Button("Check GitHub branches and tags") { updater.checkGitHub() }
                .disabled(updater.checking || updater.building)
            if !updater.references.isEmpty {
                Picker("GitHub revision", selection: $updater.selectedID) {
                    ForEach(updater.references) { entry in
                        Text("\(entry.kind): \(entry.title)").tag(entry.id)
                    }
                }
                .pickerStyle(.menu)
                HStack(spacing: 8) {
                    Button("Download & Build") { confirmBuild = true }
                        .disabled(updater.building || updater.selected == nil)
                    if updater.staged {
                        Button("Install & Restart") { confirmInstall = true }
                            .disabled(updater.building)
                    }
                }
            }
            Text(updater.status)
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            if updater.building { ProgressView().controlSize(.small) }
            Text("Only this project's GitHub repository is supported. Building a selected commit executes its source code on this Mac. Never choose a revision you do not trust. Installation is a separate confirmation; a failed build preserves your current app.")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .toggleStyle(.switch)
        .font(.system(size: 12))
        .padding(14)
        .confirmationDialog("Build and run code from GitHub?", isPresented: $confirmBuild) {
            Button("Download & Build \(updater.selected?.title ?? "")") { updater.downloadAndBuild() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected commit's build scripts will execute locally. Review the source before continuing; no update is installed until you approve it separately.")
        }
        .confirmationDialog("Replace Search Adaptive and restart?", isPresented: $confirmInstall) {
            Button("Install & Restart") { updater.installAndRestart() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The staged build will replace only Search Adaptive.app after this app quits. A backup is kept during installation.")
        }
    }
}