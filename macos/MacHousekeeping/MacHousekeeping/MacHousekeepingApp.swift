import SwiftUI

@main
struct MacHousekeepingApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppShellView(model: model)
                .background(Chrome.background)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear { model.scan() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Scan leftovers") { model.scan() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
