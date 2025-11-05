import SwiftUI

struct FolderRow: View {
    let folder: FolderEntity
    
    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name ?? "Unknown")
                    .font(.headline)
                
                Text("\(folder.allItemsCount) item\(folder.allItemsCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if folder.name == "Temporary Pins" {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
