import SwiftUI

struct DeviceActionSheet: View {
    let device: Device
    var onOpenInMaps: () -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text(device.displayName)
                .font(.headline)
                .padding(.top, 5)
            
            Divider()
            
            Button {
                driveToDevice()
            } label: {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                    Text("Drive To")
                }
            }
            
            Button("Open in Google Maps") {
                onOpenInMaps()
                dismiss()
            }
            
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        }
        .padding()
    }
    
    private func driveToDevice() {
        guard let lat = device.latitude, let lon = device.longitude else { return }
        
        let googleNavURL = URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving")!
        
        if UIApplication.shared.canOpenURL(googleNavURL) {
            UIApplication.shared.open(googleNavURL)
        } else {
            let appleNavURL = URL(string: "maps://?daddr=\(lat),\(lon)&dirflg=d")!
            UIApplication.shared.open(appleNavURL)
        }
        dismiss()
    }
}
