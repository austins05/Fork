import SwiftUI
import CoreLocation

struct GroupPinsView: View {
    let group: APIGroup
    
    @State private var pins: [APIPin] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPin: APIPin?
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            if isLoading && pins.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading pins...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 60)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if pins.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No pins in this group")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Pins shared to this group will appear here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 60)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(pins, id: \.id) { pin in
                    Button {
                        selectedPin = pin
                    } label: {
                        GroupPinRowView(pin: pin)
                    }
                }
            }
        }
        .navigationTitle("Group Pins")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPins()
        }
        .refreshable {
            loadPins()
        }
        .sheet(item: $selectedPin) { pin in
            GroupPinDetailSheet(pin: pin)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private func loadPins() {
        isLoading = true
        Task {
            do {
                let loadedPins = try await PinSyncService.shared.getGroupPins(groupId: group.id)
                await MainActor.run {
                    pins = loadedPins
                    isLoading = false
                }
                print("✅ Loaded \(loadedPins.count) pins for group: \(group.name)")
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load pins: \(error.localizedDescription)"
                    isLoading = false
                }
                print("❌ Failed to load pins: \(error)")
            }
        }
    }
}
