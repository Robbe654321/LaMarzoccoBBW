import SwiftUI
import BrewByWeightCore

@main
struct BrewByWeightApp: App {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var dashboardViewModel = BrewDashboardViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsViewModel)
                .environmentObject(dashboardViewModel)
        }
    }
}
