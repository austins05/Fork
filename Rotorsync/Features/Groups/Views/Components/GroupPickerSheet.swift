import SwiftUI

struct GroupPickerSheet: View {
    let groups: [APIGroup]
    let isLoading: Bool
    let onSelect: (APIGroup) -> Void
    
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    // Show loading state
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading groups...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 60)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if groups.isEmpty {
                    // Show empty state only when not loading
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text("No groups available")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Create a group first to share pins")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 60)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else {
                    // Show groups
                    ForEach(groups, id: \.id) { group in
                        Button {
                            onSelect(group)
                        } label: {
                            HStack(spacing: 12) {
                                // Group Icon
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                    
                                    Image(systemName: "person.3.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 18))
                                }
                                
                                // Group Info
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    if let description = group.description, !description.isEmpty {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
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
                                
                                // Chevron
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("Select Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
