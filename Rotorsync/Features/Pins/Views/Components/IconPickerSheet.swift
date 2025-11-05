import SwiftUI

struct IconPickerSheet: View {
    @Binding var selectedIcon: String
    let icons: [String]
    let onIconSelected: (String) -> Void
    
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5), spacing: 20) {
                    ForEach(icons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                            onIconSelected(icon)
                            dismiss()
                        } label: {
                            Image(systemName: icon)
                                .font(.title)
                                .foregroundColor(selectedIcon == icon ? .blue : .gray)
                                .frame(width: 44, height: 44)
                                .background(selectedIcon == icon ? Color.blue.opacity(0.2) : Color.clear)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
