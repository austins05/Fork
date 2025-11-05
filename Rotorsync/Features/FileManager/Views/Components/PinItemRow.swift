import SwiftUI

struct PinItemRow: View {
    let pin: PinEntity
    let onTap: () -> Void
    let onShare: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Pin icon with group indicator overlay
            ZStack(alignment: .topTrailing) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
                
                // Group indicator badge
                if pin.serverPinId != nil {
                    ZStack {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 16, height: 16)
                        
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                    }
                    .offset(x: 4, y: -4)
                }
            }
            .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onTap) {
                    HStack {
                        Text(pin.name ?? "Unknown Pin")
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        Image(systemName: pin.iconName ?? "mappin")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                HStack {
                    Text(String(format: "%.6f, %.6f", pin.latitude, pin.longitude))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if pin.serverPinId != nil {
                        Text("• Shared")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 6)
    }
}
