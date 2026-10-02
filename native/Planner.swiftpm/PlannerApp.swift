import SwiftUI

@main
struct PlannerApp: App {
    @StateObject private var model = PlannerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
