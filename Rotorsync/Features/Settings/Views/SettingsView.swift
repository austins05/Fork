import SwiftUI

struct SettingsView: View {
    @State private var navigationSettings = NavigationSettings.load()
    @AppStorage("flightMode") private var flightMode: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Avoid Highways", isOn: $navigationSettings.avoidHighways)
                        .onChange(of: navigationSettings.avoidHighways) { oldValue, newValue in
                            navigationSettings.save()
                        }

                    Toggle("Voice Guidance", isOn: $navigationSettings.voiceGuidanceEnabled)
                        .onChange(of: navigationSettings.voiceGuidanceEnabled) { oldValue, newValue in
                            navigationSettings.save()
                        }
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Avoid Highways will prefer routes that avoid interstates and 4-lane highways. Voice Guidance enables spoken turn-by-turn directions.")
                }

                Section {
                    HStack {
                        Text("🚁")
                            .font(.title2)
                        Toggle("Flight Mode", isOn: $flightMode)
                    }
                } header: {
                    Text("Map Display")
                } footer: {
                    Text("Flight Mode shows a projection ray on the map indicating where you will be in 5, 10, and 15 minutes based on your current heading and speed.")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0 (25)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Bundle ID")
                        Spacer()
                        Text("com.rotorsync")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
