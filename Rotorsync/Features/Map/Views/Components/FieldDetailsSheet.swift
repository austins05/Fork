import SwiftUI

struct FieldDetailsSheet: View {
    let field: FieldData
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailRow(title: "Field Name", value: field.name)
                    detailRow(title: "Area", value: String(format: "%.1f ac", field.acres))
                    
                    if let prodDupli = field.prodDupli, !prodDupli.isEmpty {
                        detailRow(title: "Prod Dupli", value: prodDupli)
                    }
                    
                    if let productList = field.productList, !productList.isEmpty {
                        detailRow(title: "Product", value: productList)
                    }
                    
                    if let notes = field.notes, !notes.isEmpty {
                        detailRow(title: "Notes", value: notes)
                    }
                    
                    if let address = field.address, !address.isEmpty {
                        detailRow(title: "Address", value: address)
                    }
                    
                    if let category = field.category, !category.isEmpty {
                        detailRow(title: "Category", value: category)
                    }
                    
                    if let application = field.application, !application.isEmpty {
                        detailRow(title: "Application Rate", value: application)
                    }
                    
                    if let description = field.description, !description.isEmpty {
                        detailRow(title: "Description", value: description)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Field Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Dismiss") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.body)
        }
    }
}
