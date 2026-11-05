import AppKit
import MacRemoteKit
import SwiftUI

/// Picks an app to give its own buttons: one that is running, or any app on disk.
@MainActor
enum AppChooser {
    struct Candidate: Identifiable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    /// Running apps with a Dock icon, not already added, by name.
    static func running(excluding overrides: AppOverrides) -> [Candidate] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> Candidate? in
                guard let id = app.bundleIdentifier, id != own, !overrides.contains(id),
                      seen.insert(id).inserted else { return nil }
                return Candidate(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Asks for an app in Applications and adds it.
    static func chooseFromDisk(into engine: RemoteEngine) {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        add(Candidate(bundleID: id, name: name), into: engine)
    }

    static func add(_ app: Candidate, into engine: RemoteEngine) {
        engine.appOverrides.add(bundleID: app.bundleID, name: app.name)
    }

    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct AppsPage: View {
    @EnvironmentObject private var engine: RemoteEngine

    var body: some View {
        if engine.appOverrides.apps.isEmpty {
            VStack(spacing: Space.lg) {
                EmptyState(title: "No Apps",
                           symbol: "macwindow.on.rectangle",
                           message: "Make a button do something else while one app is in front, like Play/Pause sending Space to a video player that ignores the media key.")
                    .frame(maxHeight: nil)
                AddAppMenu(engine: engine)
                    .fixedSize()
                Spacer()
            }
        } else {
            Page {
                ForEach(engine.appOverrides.apps) { app in
                    AppCard(engine: engine, app: app)
                }
                AddAppMenu(engine: engine)
                    .fixedSize()
            }
        }
    }
}

/// "Add App": running apps first, then any app on disk.
struct AddAppMenu: View {
    @ObservedObject var engine: RemoteEngine

    var body: some View {
        Menu("Add App") {
            let running = AppChooser.running(excluding: engine.appOverrides)
            if !running.isEmpty {
                Section("Running") {
                    ForEach(running) { app in
                        Button(app.name) { AppChooser.add(app, into: engine) }
                    }
                }
            }
            Button("Choose App…") { AppChooser.chooseFromDisk(into: engine) }
        }
        .help("Give an app its own buttons (Shift-Command-A)")
    }
}

private struct AppCard: View {
    @ObservedObject var engine: RemoteEngine
    let app: AppOverride

    var body: some View {
        Card(footer: "These buttons apply in both modes while \(app.name) is in front. Other buttons do what the Buttons page says.") {
            HStack(spacing: Space.sm) {
                if let icon = AppChooser.icon(for: app.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: Space.xxl, height: Space.xxl)
                } else {
                    Image(systemName: Symbol.named("app"))
                        .frame(width: Space.xxl, height: Space.xxl)
                }
                Text(app.name).font(.headline)
                Spacer()
                Menu("Add Button") {
                    ForEach(RemoteButton.allCases.map(RemoteKey.init).filter { app.action(for: $0) == nil }) { key in
                        Button(key.title) {
                            engine.appOverrides.set(engine.profile.action(for: key, in: engine.mode),
                                                    for: key, app: app.bundleID)
                        }
                    }
                }
                .fixedSize()
                Button("Remove App") { engine.appOverrides.remove(app: app.bundleID) }
                    .help("Use the Buttons page again while \(app.name) is in front")
            }
            .padding(.vertical, Space.sm)
            ForEach(app.keys) { key in
                CardDivider()
                Row(title: key.title, symbol: key.symbol) {
                    Picker("Action", selection: Binding(
                        get: { engine.appOverrides.action(for: key, app: app.bundleID) ?? .none },
                        set: { engine.appOverrides.set($0, for: key, app: app.bundleID) }
                    )) {
                        ActionChoices()
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        engine.appOverrides.remove(key, app: app.bundleID)
                    } label: {
                        Image(systemName: Symbol.named("minus.circle"))
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(key.title) from \(app.name)")
                }
            }
        }
    }
}
