import SwiftUI

struct GroupDetailView: View {
    let group: APIGroup
    var onGroupUpdated: () -> Void
    
    @State private var showImportKML = false
    @State private var members: [GroupMember] = []
    @State private var isLoading = false
    @State private var showAddMember = false
    @State private var showDeleteConfirmation = false
    @State private var memberToRemove: GroupMember?
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) var dismiss
    
    private var currentUserRole: String {
        group.members?.first?.role ?? "member"
    }
    
    private var isAdmin: Bool {
        let role = currentUserRole.lowercased()
        return role == "owner" || role == "admin"
    }
    
    var body: some View {
        List {
            // Group Info Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "person.3.fill")
                                .font(.title)
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.title2)
                                .bold()
                            
                            if let description = group.description, !description.isEmpty {
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Stats
                    if let count = group._count {
                        HStack(spacing: 20) {
                            StatView(icon: "person.2", value: "\(count.members)", label: "Members")
                            StatView(icon: "mappin", value: "\(count.pins)", label: "Pins")
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Members Section
            Section {
                if isLoading && members.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading members...")
                            .foregroundColor(.secondary)
                    }
                } else if members.isEmpty {
                    Text("No members yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(members) { member in
                        MemberRowView(
                            member: member,
                            currentUserRole: currentUserRole,
                            onRemove: {
                                memberToRemove = member
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Members")
                    Spacer()
                    if isAdmin {
                        Button {
                            showAddMember = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            
            Section {
                NavigationLink {
                    GroupPinsView(group: group)
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.red)
                        Text("View Pins")
                        Spacer()
                        if let count = group._count {
                            Text("\(count.pins)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Button {
                    showImportKML = true
                } label: {
                    Label("Import KML Pins", systemImage: "square.and.arrow.down")
                        .foregroundColor(.blue)
                }
            } header: {
                Text("Content")
            }
            
            // Actions Section (only for admins/owners)
            if isAdmin {
                Section {
                    Button {
                        // TODO: Implement edit group
                    } label: {
                        Label("Edit Group Details", systemImage: "pencil")
                    }
                    
                    if currentUserRole.lowercased() == "owner" {
                        Button(role: .destructive) {
                            // TODO: Implement delete group
                        } label: {
                            Label("Delete Group", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Group Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadMembers()
        }
        .refreshable {
            loadMembers()
        }
        .sheet(isPresented: $showAddMember) {
            AddMemberView(groupId: group.id, onMemberAdded: {
                loadMembers()
                onGroupUpdated()
            })
        }
        .sheet(isPresented: $showImportKML) {
            ImportKMLView(group: group) {
                onGroupUpdated()
            }
        }
        .alert("Remove Member", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                memberToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let member = memberToRemove {
                    removeMember(member)
                }
            }
        } message: {
            if let member = memberToRemove {
                Text("Are you sure you want to remove \(member.user.name) from this group?")
            }
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
    
    private func loadMembers() {
        isLoading = true
        Task {
            do {
                let data = try await PinSyncService.shared.getGroupMembers(groupId: group.id)
                let decoder = JSONDecoder()
                let loadedMembers = try decoder.decode([GroupMember].self, from: data)
                
                await MainActor.run {
                    members = loadedMembers.sorted { member1, member2 in
                        let roleOrder = ["owner": 0, "admin": 1, "member": 2]
                        let role1 = roleOrder[member1.role.lowercased()] ?? 3
                        let role2 = roleOrder[member2.role.lowercased()] ?? 3
                        return role1 < role2
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load members: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func removeMember(_ member: GroupMember) {
        Task {
            do {
                try await PinSyncService.shared.removeMember(groupId: group.id, userId: member.userId)
                await MainActor.run {
                    loadMembers()
                    onGroupUpdated()
                    memberToRemove = nil
                }
                print("✅ Member removed successfully")
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to remove member: \(error.localizedDescription)"
                    memberToRemove = nil
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(
            group: APIGroup(
                id: "1",
                name: "Farm Team",
                description: "Main operations",
                createdAt: "",
                updatedAt: "",
                members: [APIGroup.MemberInfo(role: "owner")],
                _count: APIGroup.CountInfo(members: 5, pins: 12)
            ),
            onGroupUpdated: {}
        )
    }
}
