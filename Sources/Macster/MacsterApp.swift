import AppKit
import SwiftUI

@main
struct MacsterApp: App {
    @StateObject private var controller = PowerController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(width: 420, height: 450)
                .fixedSize()
                .onAppear {
                    controller.refresh()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
