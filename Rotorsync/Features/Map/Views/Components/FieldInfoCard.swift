import SwiftUI

struct FieldInfoCard: View {
    let field: FieldData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.name)
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 16) {
                compactInfo(label: "Area", value: String(format: "%.1f ac", field.acres))
                
                if let prodDupli = field.prodDupli, !prodDupli.isEmpty {
                    compactInfo(label: "Prod Dupli", value: prodDupli)
                }
            }
            
            if let product = field.productList, !product.isEmpty {
                compactInfo(label: "Product", value: product)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func compactInfo(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}
