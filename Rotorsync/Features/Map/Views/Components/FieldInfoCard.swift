import SwiftUI

struct FieldInfoCard: View {
    let field: FieldData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    formatFieldName(field.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // Crop info inline with name
                    if let crop = field.crop, !crop.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: cropIcon(for: crop))
                                .font(.system(size: 12))
                                .foregroundColor(cropColor(for: crop))
                            Text(crop)
                                .font(.system(size: 11))
                                .foregroundColor(cropColor(for: crop))
                                .fontWeight(.medium)
                        }
                    }
                }
                
                Spacer()
                
                // Tabula button (only show for Tabula-sourced fields)
                if field.source == .tabula {
                    Button(action: {
                        openInTabula()
                    }) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                    }
                }
            }
            
            HStack(spacing: 16) {
                compactInfo(label: "Req. Acres", value: String(format: "%.2f ac", field.acres))

                // Show nominal acres if there's a value greater than 0
                if let nominalAcres = field.nominalAcres, nominalAcres > 0 {
                    compactInfo(label: "Nominal Acres", value: String(format: "%.2f ac", nominalAcres))
                }

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
        .frame(maxWidth: 320)
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
    
    private func openInTabula() {
        let urlString = "https://test-api.tabula-online.com/goto_order/\(field.jobId ?? field.id)"
        print("🔗 Opening Tabula URL: \(urlString)")
        print("   field.id = \(field.id)")
        print("   field.jobId = \(String(describing: field.jobId))")
        print("   field.source = \(String(describing: field.source))")
        if let url = URL(string: urlString) {
            print("✅ URL created successfully, opening...")
            UIApplication.shared.open(url)
        } else {
            print("❌ Failed to create URL from: \(urlString)")
        }
    }
    
    // Crop icon mapping
    private func cropIcon(for crop: String) -> String {
        let cropLower = crop.lowercased()
        
        if cropLower.contains("corn") {
            return "leaf.fill"
        } else if cropLower.contains("soybean") || cropLower.contains("bean") {
            return "wand.and.rays"
        } else if cropLower.contains("pumpkin") {
            return "circle.fill"
        } else if cropLower.contains("wheat") {
            return "bolt.horizontal.fill"
        } else if cropLower.contains("pea") {
            return "wand.and.rays"
        } else if cropLower.contains("potato") {
            return "oval.fill"
        } else if cropLower.contains("hay") {
            return "rectangle.stack.fill"
        } else if cropLower.contains("timber") || cropLower.contains("tree") {
            return "tree.fill"
        } else if cropLower.contains("elderberr") {
            return "circle.grid.2x2.fill"
        } else {
            return "leaf"
        }
    }
    
    // Crop color mapping
    private func cropColor(for crop: String) -> Color {
        let cropLower = crop.lowercased()

        if cropLower.contains("corn") {
            return .yellow
        } else if cropLower.contains("soybean") || cropLower.contains("bean") {
            return .green
        } else if cropLower.contains("pumpkin") {
            return .orange
        } else if cropLower.contains("wheat") {
            return .brown
        } else if cropLower.contains("pea") {
            return .green
        } else if cropLower.contains("potato") {
            return .brown
        } else if cropLower.contains("hay") {
            return Color(red: 0.8, green: 0.7, blue: 0.4)
        } else if cropLower.contains("timber") || cropLower.contains("tree") {
            return Color(red: 0.4, green: 0.3, blue: 0.2)
        } else if cropLower.contains("elderberr") {
            return .purple
        } else {
            return .green
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
