import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var dashboardViewModel: BrewDashboardViewModel

    var body: some View {
        TabView {
            NavigationStack {
                BrewDashboardView(viewModel: dashboardViewModel)
                    .navigationTitle("Dashboard")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            BrewStatusIndicator(status: dashboardViewModel.statusText)
                        }
                    }
            }
            .tabItem {
                Label("Dashboard", systemImage: "speedometer")
            }

            NavigationStack {
                SettingsView(viewModel: settingsViewModel)
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
        .task {
            dashboardViewModel.bind(to: settingsViewModel)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsViewModel())
        .environmentObject(BrewDashboardViewModel())
}
