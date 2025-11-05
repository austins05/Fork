import SwiftUI

struct GroupRowView: View {
    let group: APIGroup
    
    var body: some View {
        HStack(spacing: 15) {
            // Group Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "person.3.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
            
            // Group Info
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                
                if let description = group.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Stats
                if let count = group._count {
                    HStack(spacing: 12) {
                        Label("\(count.members)", systemImage: "person.2")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        
                        Label("\(count.pins)", systemImage: "mappin")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            // Role Badge
            if let member = group.members?.first {
                Text(member.role.capitalized)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(roleBadgeColor(role: member.role))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func roleBadgeColor(role: String) -> Color {
        switch role.lowercased() {
        case "owner": return .purple
        case "admin": return .orange
        default: return .gray
        }
    }
}
