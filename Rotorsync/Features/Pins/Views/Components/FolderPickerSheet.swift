import SwiftUI

struct FolderPickerSheet: View {
    let folders: [FolderEntity]
    let currentFolder: FolderEntity?
    let onSelect: (FolderEntity) -> Void
    
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(folders.filter { ($0.name ?? "") != "Temporary Pins" }) { folder in
                    Button {
                        onSelect(folder)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.blue)
                            Text(folder.name ?? "Unknown")
                            Spacer()
                            if folder.id == currentFolder?.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                            Text("\(folder.allItemsCount) items")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
