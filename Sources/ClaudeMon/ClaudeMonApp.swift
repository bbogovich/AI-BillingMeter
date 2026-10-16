import SwiftUI

@main
struct ClaudeMonApp: App {
    @State private var model = AppModel(snapshot: Snapshot.outputDirectory != nil)

    init() {
        if let dir = Snapshot.outputDirectory {
            Task { @MainActor in await Snapshot.run(to: dir) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("ClaudeMon Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let text = model.menuBarText
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            if !text.isEmpty { Text(text).monospacedDigit() }
        }
    }
}
