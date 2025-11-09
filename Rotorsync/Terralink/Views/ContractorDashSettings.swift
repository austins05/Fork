//
//  ContractorDashSettings.swift
//  Rotorsync - Contractor Dash Border Settings
//

import Foundation
import SwiftUI
import Combine

// Model for contractor dash border settings
struct ContractorDashSetting: Identifiable, Codable {
    var id = UUID()
    var contractorName: String
    var dashColor: String  // Hex color
}

// Settings manager
class ContractorDashSettingsManager: ObservableObject {
    static let shared = ContractorDashSettingsManager()

    @Published var settings: [ContractorDashSetting] = []

    private let settingsKey = "ContractorDashSettings"

    private init() {
        loadSettings()
    }

    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode([ContractorDashSetting].self, from: data) {
            settings = decoded
        }
    }

    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }

    func addSetting(contractorName: String, dashColor: String) {
        let newSetting = ContractorDashSetting(contractorName: contractorName, dashColor: dashColor)
        settings.append(newSetting)
        saveSettings()
    }

    func removeSetting(at index: Int) {
        settings.remove(at: index)
        saveSettings()
    }

    func getDashColor(for contractorName: String) -> String? {
        settings.first(where: { $0.contractorName.lowercased() == contractorName.lowercased() })?.dashColor
    }
}

// Settings view
struct ContractorDashSettingsView: View {
    @ObservedObject var settingsManager = ContractorDashSettingsManager.shared
    @StateObject private var viewModel = FieldMapsTableViewModel()
    @State private var newContractorName = ""
    @State private var newDashColor = "Red"
    @State private var showSuggestions = false
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.presentationMode) var presentationMode

    let availableColors = [
        "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "Black", "White"
    ]

    var contractorSuggestions: [String] {
        let allContractors = Array(Set(viewModel.fieldMaps.compactMap { $0.contractor }))
            .filter { !$0.isEmpty }
            .sorted()

        if newContractorName.isEmpty {
            return allContractors
        }

        return allContractors
            .filter { $0.localizedCaseInsensitiveContains(newContractorName) }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Add new setting
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add Contractor Dash Border")
                        .font(.headline)
                        .padding(.bottom, 4)

                    // Search field with suggestions
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Search Contractor Name", text: $newContractorName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .focused($isTextFieldFocused)
                            .onChange(of: newContractorName) { _ in
                                showSuggestions = !contractorSuggestions.isEmpty
                            }
                            .onChange(of: isTextFieldFocused) { focused in
                                showSuggestions = focused && !contractorSuggestions.isEmpty
                            }

                        // Suggestions list
                        if showSuggestions && isTextFieldFocused {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(contractorSuggestions, id: \.self) { contractor in
                                        Button(action: {
                                            newContractorName = contractor
                                            showSuggestions = false
                                            isTextFieldFocused = false
                                        }) {
                                            Text(contractor)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(Color(.systemBackground))
                                        }
                                        .buttonStyle(PlainButtonStyle())

                                        if contractor != contractorSuggestions.last {
                                            Divider()
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                        }
                    }

                    HStack {
                        Text("Dash Color:")
                        Picker("Color", selection: $newDashColor) {
                            ForEach(availableColors, id: \.self) { color in
                                Text(color).tag(color)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    Button(action: {
                        if !newContractorName.isEmpty {
                            let hexColor = colorNameToHex(newDashColor)
                            settingsManager.addSetting(contractorName: newContractorName, dashColor: hexColor)
                            newContractorName = ""
                            newDashColor = "Red"
                        }
                    }) {
                        Text("Add Contractor")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(.systemGray6))

                Divider()

                // List of existing settings
                List {
                    ForEach(Array(settingsManager.settings.enumerated()), id: \.element.id) { index, setting in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(setting.contractorName)
                                    .font(.headline)
                                Text("Dash Color")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Rectangle()
                                .fill(Color(hex: setting.dashColor))
                                .frame(width: 40, height: 20)
                                .cornerRadius(4)

                            Button(action: {
                                settingsManager.removeSetting(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Contractor Dash Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .task {
                await viewModel.loadInitialData()
            }
        }
    }

    func colorNameToHex(_ colorName: String) -> String {
        let colorMap: [String: String] = [
            "Red": "#FF0000", "Orange": "#FF8C00", "Yellow": "#FFFF00",
            "Green": "#00FF00", "Teal": "#00FFFF", "Blue": "#0000FF",
            "Purple": "#9966FF", "Pink": "#FF69B4", "Black": "#000000", "White": "#FFFFFF"
        ]
        return colorMap[colorName] ?? "#FF0000"
    }
}
