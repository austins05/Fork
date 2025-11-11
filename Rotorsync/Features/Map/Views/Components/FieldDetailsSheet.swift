import SwiftUI

struct FieldDetailsSheet: View {
    let field: FieldData
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Field Name with formatted order ID
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Field Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        formatFieldName(field.name)
                            .font(.body)
                    }
                    detailRow(title: "Req. Acres", value: String(format: "%.1f ac", field.acres))
                    
                    if let nominalAcres = field.nominalAcres, nominalAcres > 0 {
                        detailRow(title: "Nominal Acres", value: String(format: "%.1f ac", nominalAcres))
                    }
                    
                    if let crop = field.crop, !crop.isEmpty {
                        detailRow(title: "Crop Type", value: crop)
                    }
                    
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

    // Format field name to make last 3 digits of order ID bold and bigger
    private func formatFieldName(_ name: String) -> Text {
        // Pattern: match # followed by digits, extract last 3 digits to make bold and bigger
        // Example: "#37665 1/3" -> "#376" + "65" (bold+bigger) + " 1/3"

        if let range = name.range(of: "#\\d+", options: .regularExpression) {
            let orderIdWithHash = String(name[range])
            let orderIdDigits = orderIdWithHash.dropFirst() // Remove #

            if orderIdDigits.count >= 3 {
                let lastThreeIndex = orderIdDigits.index(orderIdDigits.endIndex, offsetBy: -3)
                let beforeLastThree = orderIdDigits[..<lastThreeIndex]
                let lastThree = orderIdDigits[lastThreeIndex...]

                let beforeOrderId = String(name[..<range.lowerBound])
                let afterOrderId = String(name[range.upperBound...])

                return Text(beforeOrderId + "#" + beforeLastThree)
                    + Text(lastThree)
                        .fontWeight(.heavy)
                        .font(.system(size: 19))
                    + Text(afterOrderId)
            }
        }

        // Fallback: return name as-is if pattern doesn't match
        return Text(name)
    }
}
