import SwiftUI

@main
struct CallmetApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("Callmet") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 860, minHeight: 640)
        }
    }
}
