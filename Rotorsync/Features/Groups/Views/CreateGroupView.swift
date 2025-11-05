import SwiftUI

struct CreateGroupView: View {
    @State private var groupName = ""
    @State private var groupDescription = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var onGroupCreated: () -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group Name", text: $groupName)
                        .autocapitalization(.words)
                    
                    TextField("Description (optional)", text: $groupDescription, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Group Details")
                } footer: {
                    Text("Create a group to collaborate and share pins with your team")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        createGroup()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                                .bold()
                        }
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }
    
    private func createGroup() {
        let name = groupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        isCreating = true
        errorMessage = nil
        
        Task {
            do {
                let group = try await PinSyncService.shared.createGroup(
                    name: name,
                    description: groupDescription.isEmpty ? nil : groupDescription
                )
                
                await MainActor.run {
                    isCreating = false
                    onGroupCreated()
                    dismiss()
                }
                
                print("✅ Group created: \(group.name)")
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                }
                print("❌ Failed to create group: \(error)")
            }
        }
    }
}

#Preview {
    CreateGroupView(onGroupCreated: {})
}
