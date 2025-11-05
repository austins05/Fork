import SwiftUI

struct GroupPinRowView: View {
    let pin: APIPin
    
    var body: some View {
        HStack(spacing: 12) {
            // Pin Icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: pin.iconName)
                    .foregroundColor(.red)
                    .font(.system(size: 18))
            }
            
            // Pin Info
            VStack(alignment: .leading, spacing: 4) {
                Text(pin.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack {
                    Text(String(format: "%.6f, %.6f", pin.latitude, pin.longitude))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let creator = pin.creator {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle.fill")
                            .font(.caption2)
                        Text(creator.name)
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}
