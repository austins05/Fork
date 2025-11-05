import SwiftUI
import Combine
import CoreData

@main
struct RotorSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let persistenceController = PersistenceController.shared
    
    @StateObject private var appState = AppState()
        
    var body: some Scene {
        WindowGroup {
            if appState.isLoggedIn {
                TabView {
                    HomeView()
                        .tabItem {
                            Image(systemName: "house.fill")
                            Text("Home")
                        }
                    
                    MonitorView()
                        .tabItem {
                            Image(systemName: "eye.fill")
                            Text("Monitor")
                        }
                    
                    MapView()
                        .tabItem {
                            Image(systemName: "map.fill")
                            Text("Map")
                        }
                    
                    FieldMapsManagementView()
                        .tabItem {
                            Image(systemName: "map.circle.fill")
                            Text("Field Maps")
                        }
                    
                    SettingsView()
                        .tabItem {
                            Image(systemName: "gearshape.fill")
                            Text("Settings")
                        }
                }
                .environmentObject(appState)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
            } else {
                LoginView()
                    .environmentObject(appState)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var isLoggedIn = false
    
    init() {
        isLoggedIn = KeychainService.getToken() != nil && isSessionValid()
    }
    
    func isSessionValid() -> Bool {
        guard let expirationDate = UserDefaults.standard.object(forKey: "sessionExpiration") as? Date else {
            return false
        }
        return Date() < expirationDate
    }
}
