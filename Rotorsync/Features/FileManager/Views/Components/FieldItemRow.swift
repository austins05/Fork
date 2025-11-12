import SwiftUI

struct FieldItemRow: View {
    let field: FieldEntity
    let onTap: () -> Void
    let onShare: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "crop.rotate")
                .foregroundColor(.green)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onTap) {
                    Text(field.name ?? "Unknown Field")
                        .font(.body)
                        .foregroundColor(.primary)
                }
                .buttonStyle(PlainButtonStyle())
                
                HStack {
                    Text(String(format: "%.2f ac", field.acres))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    let category = field.category ?? ""
                    if !category.isEmpty {
                        Text("• \(category)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 6)
    }
}
