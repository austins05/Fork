import SwiftUI

struct GroupManagementView: View {
    @State private var groups: [APIGroup] = []
    @State private var isLoading = false
    @State private var showCreateGroup = false
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading && groups.isEmpty {
                    ProgressView("Loading groups...")
                } else if groups.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Groups Yet")
                            .font(.title2)
                            .bold()
                        
                        Text("Create a group to collaborate with your team")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button {
                            showCreateGroup = true
                        } label: {
                            Label("Create Your First Group", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                } else {
                    List {
                        ForEach(groups, id: \.id) { group in
                            NavigationLink {
                                GroupDetailView(group: group, onGroupUpdated: {
                                    loadGroups()
                                })
                            } label: {
                                GroupRowView(group: group)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateGroup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                loadGroups()
            }
            .refreshable {
                loadGroups()
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView(onGroupCreated: {
                    loadGroups()
                })
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
    }
    
    private func loadGroups() {
        isLoading = true
        Task {
            do {
                let loadedGroups = try await PinSyncService.shared.getUserGroups()
                await MainActor.run {
                    groups = loadedGroups
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load groups: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    GroupManagementView()
}
