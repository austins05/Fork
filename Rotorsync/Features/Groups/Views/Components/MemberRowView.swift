import SwiftUI

struct MemberRowView: View {
    let member: GroupMember
    let currentUserRole: String
    let onRemove: () -> Void
    
    private var canRemove: Bool {
        let currentRole = currentUserRole.lowercased()
        let memberRole = member.role.lowercased()
        
        // Owner can remove anyone except themselves
        if currentRole == "owner" {
            return true
        }
        
        // Admin can remove members (but not owners or other admins)
        if currentRole == "admin" && memberRole == "member" {
            return true
        }
        
        return false
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Text(member.user.name.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundColor(.blue)
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 2) {
                Text(member.user.name)
                    .font(.headline)
                
                Text(member.user.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Role Badge
            Text(member.role.capitalized)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(roleBadgeColor(role: member.role))
                .foregroundColor(.white)
                .cornerRadius(8)
            
            // Remove Button
            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
    
    private func roleBadgeColor(role: String) -> Color {
        switch role.lowercased() {
        case "owner": return .purple
        case "admin": return .orange
        default: return .gray
        }
    }
}
