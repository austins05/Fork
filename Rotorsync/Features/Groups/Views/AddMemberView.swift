import SwiftUI

struct AddMemberView: View {
    let groupId: String
    var onMemberAdded: () -> Void
    
    @State private var searchText = ""
    @State private var selectedRole = "member"
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    @Environment(\.dismiss) var dismiss
    
    private let roles = ["member", "admin"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("User ID or Email", text: $searchText)
                        .autocapitalization(.none)
                        .textContentType(.emailAddress)
                } header: {
                    Text("User Information")
                } footer: {
                    Text("Enter the user's ID or email address to add them to the group")
                }
                
                Section("Role") {
                    Picker("Select Role", selection: $selectedRole) {
                        ForEach(roles, id: \.self) { role in
                            Text(role.capitalized).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("Member")
                                .font(.subheadline)
                        } icon: {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 12, height: 12)
                        }
                        Text("Can view and create pins")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Label {
                            Text("Admin")
                                .font(.subheadline)
                        } icon: {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 12, height: 12)
                        }
                        Text("Can manage members and pins")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Role Permissions")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                if let success = successMessage {
                    Section {
                        Text(success)
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isAdding)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addMember()
                    } label: {
                        if isAdding {
                            ProgressView()
                        } else {
                            Text("Add")
                                .bold()
                        }
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                }
            }
        }
    }
    
    private func addMember() {
        let userId = searchText.trimmingCharacters(in: .whitespaces)
        guard !userId.isEmpty else { return }
        
        isAdding = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                try await PinSyncService.shared.addMember(
                    groupId: groupId,
                    userId: userId,
                    role: selectedRole
                )
                
                await MainActor.run {
                    isAdding = false
                    successMessage = "Member added successfully!"
                    onMemberAdded()
                }
                
                // Auto-dismiss after success
                try await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    dismiss()
                }
                
                print("Member added to group")
            } catch {
                await MainActor.run {
                    isAdding = false
                    errorMessage = error.localizedDescription
                }
                print("Failed to add member: \(error)")
            }
        }
    }
}

#Preview {
    AddMemberView(groupId: "123", onMemberAdded: {})
}
