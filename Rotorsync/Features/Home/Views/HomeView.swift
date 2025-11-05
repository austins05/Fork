import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var mqttManager = MQTTManager.shared
    
    @State private var connectionStatus = "Disconnected"

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Welcome
                VStack(spacing: 12) {
                    Text("Welcome to RotorSync!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if let user = getUserData() {
                        VStack(spacing: 8) {
                            Text("Hello, \(user.name ?? "User")!")
                                .font(.title2)
                            Text("Role: \(user.role ?? "—")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if let serial = user.serialNumber?.name {
                                Text("Device: \(serial)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 20)

                // MQTT Card
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundColor(statusColor)
                        
                        Text("MQTT Live Tracking")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Toggle("", isOn: $mqttManager.isConnected)
                            .labelsHidden()
                    }
                    
                    Divider()
                    
                    HStack {
                        Circle().fill(statusColor).frame(width: 12, height: 12)
                        Text(connectionStatus)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ConnectionDetailRow(icon: "server.rack", label: "Host", value: "ws.rotorsync.com")
                        ConnectionDetailRow(icon: "number", label: "Port", value: "443")
                        ConnectionDetailRow(icon: "person.fill", label: "Username", value: "app")
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)).shadow(radius: 5))
                .padding(.horizontal)

                // Logout
                Button {
                    MQTTManager.shared.disconnect()
                    KeychainService.deleteToken()
                    UserDefaults.standard.removeObject(forKey: "userData")
                    appState.isLoggedIn = false
                } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: mqttManager.isConnected) { _ in
            connectionStatus = mqttManager.isConnected ? "Connected" : "Disconnected"
        }
    }
    
    private var statusColor: Color {
        mqttManager.isConnected ? .green : .red
    }
    
    private func getUserData() -> User? {
        guard let data = UserDefaults.standard.data(forKey: "userData"),
              let user = try? JSONDecoder().decode(User.self, from: data) else { return nil }
        return user
    }
}

struct ConnectionDetailRow: View {
    let icon: String
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(.secondary).frame(width: 20)
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.medium)
        }
    }
}
