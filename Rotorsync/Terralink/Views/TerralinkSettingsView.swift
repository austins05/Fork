//
//  TerralinkSettingsView.swift
//  Rotorsync - Terralink Settings
//

import Foundation
import SwiftUI
import Combine

// MARK: - Settings View
struct TerralinkSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                ContractorDashSettingsTab()
                    .tabItem {
                        Label("Dash Borders", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .tag(0)

                NotificationSettingsTab()
                    .tabItem {
                        Label("Notifications", systemImage: "bell.fill")
                    }
                    .tag(1)
            }
            .navigationTitle("Terralink Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// MARK: - Contractor Dash Tab
struct ContractorDashSettingsTab: View {
    @ObservedObject var settingsManager = ContractorDashSettingsManager.shared
    @StateObject private var viewModel = FieldMapsTableViewModel()
    @State private var newContractorName = ""
    @State private var newDashColor = "Red"
    @State private var showSuggestions = false
    @FocusState private var isTextFieldFocused: Bool

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
        .task {
            await viewModel.loadInitialData()
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

// MARK: - Notification Settings Tab
struct NotificationSettingsTab: View {
    @StateObject private var configManager = NotificationConfigManager()

    var body: some View {
        Form {
            Section(header: Text("Custom Messages"),
                    footer: Text("Use {contractor} for contractor name and {createdTime} for order creation time")) {
                CustomMessageEditor(
                    title: "Reference Fields",
                    type: "reference_field",
                    message: $configManager.referenceFieldMessage,
                    onSave: { configManager.saveCustomMessage(type: "reference_field", message: $0) }
                )

                CustomMessageEditor(
                    title: "Exclusion Zones",
                    type: "exclusion_zone",
                    message: $configManager.exclusionZoneMessage,
                    onSave: { configManager.saveCustomMessage(type: "exclusion_zone", message: $0) }
                )

                CustomMessageEditor(
                    title: "No-Go Zones",
                    type: "nogo_zone",
                    message: $configManager.nogoZoneMessage,
                    onSave: { configManager.saveCustomMessage(type: "nogo_zone", message: $0) }
                )

                CustomMessageEditor(
                    title: "Zero Area",
                    type: "zero_area",
                    message: $configManager.zeroAreaMessage,
                    onSave: { configManager.saveCustomMessage(type: "zero_area", message: $0) }
                )
            }

            Section(header: Text("Notification Rules")) {
                Toggle("Reference Fields (outlines)", isOn: $configManager.outlines)
                    .onChange(of: configManager.outlines) { _ in
                        configManager.updateRules()
                    }
                Toggle("Exclusion Zones", isOn: $configManager.exclusion)
                    .onChange(of: configManager.exclusion) { _ in
                        configManager.updateRules()
                    }
                Toggle("No-Go Zones", isOn: $configManager.nogo)
                    .onChange(of: configManager.nogo) { _ in
                        configManager.updateRules()
                    }
                Toggle("Zero Area Orders", isOn: $configManager.zeroArea)
                    .onChange(of: configManager.zeroArea) { _ in
                        configManager.updateRules()
                    }
            }

            Section(header: Text("Always-Notify Emails")) {
                ForEach(configManager.alwaysNotifyEmails, id: \.self) { email in
                    HStack {
                        Text(email)
                        Spacer()
                        Button(action: {
                            configManager.removeAlwaysNotify(email: email)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }

                AddEmailView(onAdd: { email in
                    configManager.addAlwaysNotify(email: email)
                })
            }

            Section(header: Text("Contractor Emails")) {
                ForEach(Array(configManager.contractorEmails.keys.sorted()), id: \.self) { contractor in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(contractor)
                                .font(.headline)
                            Text(configManager.contractorEmails[contractor] ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            configManager.removeContractorEmail(contractor: contractor)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }

                AddContractorEmailView(onAdd: { contractor, email in
                    configManager.setContractorEmail(contractor: contractor, email: email)
                })
            }

            Section(header: Text("Monitor Control")) {
                HStack {
                    Text("Status:")
                    Spacer()
                    Text(configManager.monitorRunning ? "Running" : "Stopped")
                        .foregroundColor(configManager.monitorRunning ? .green : .red)
                        .bold()
                }

                if configManager.monitorRunning {
                    Button("Stop Monitor") {
                        configManager.stopMonitor()
                    }
                    .foregroundColor(.red)
                } else {
                    Button("Start Monitor") {
                        configManager.startMonitor()
                    }
                    .foregroundColor(.green)
                }

                Button("Reset Monitor") {
                    configManager.resetMonitor()
                }
            }
        }
        .task {
            await configManager.loadConfig()
        }
    }
}

// MARK: - Add Email View
struct AddEmailView: View {
    @State private var newEmail = ""
    var onAdd: (String) -> Void

    var body: some View {
        HStack {
            TextField("email@example.com", text: $newEmail)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .keyboardType(.emailAddress)

            Button(action: {
                if !newEmail.isEmpty && newEmail.contains("@") {
                    onAdd(newEmail)
                    newEmail = ""
                }
            }) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }
}

// MARK: - Add Contractor Email View
struct AddContractorEmailView: View {
    @State private var contractor = ""
    @State private var email = ""
    @State private var isExpanded = false
    var onAdd: (String, String) -> Void

    var body: some View {
        VStack {
            Button(action: {
                isExpanded.toggle()
            }) {
                HStack {
                    Text("Add Contractor Email")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
            }

            if isExpanded {
                VStack(spacing: 8) {
                    TextField("Contractor Name", text: $contractor)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    TextField("email@example.com", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)

                    Button(action: {
                        if !contractor.isEmpty && !email.isEmpty && email.contains("@") {
                            onAdd(contractor, email)
                            contractor = ""
                            email = ""
                            isExpanded = false
                        }
                    }) {
                        Text("Add")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Custom Message Editor
struct CustomMessageEditor: View {
    let title: String
    let type: String
    @Binding var message: String
    let onSave: (String) -> Void
    @State private var isExpanded = false
    @State private var editedMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                isExpanded.toggle()
                if isExpanded {
                    editedMessage = message
                }
            }) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if !message.isEmpty {
                        Text("✓")
                            .foregroundColor(.green)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
            }

            if isExpanded {
                VStack(spacing: 8) {
                    TextEditor(text: $editedMessage)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )

                    Text("Variables: {contractor}, {createdTime}")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Button("Save") {
                            message = editedMessage
                            onSave(editedMessage)
                            isExpanded = false
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Clear") {
                            editedMessage = ""
                            message = ""
                            onSave("")
                            isExpanded = false
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)

                        Button("Cancel") {
                            isExpanded = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Notification Config Manager
@MainActor
class NotificationConfigManager: ObservableObject {
    @Published var outlines = true
    @Published var exclusion = true
    @Published var nogo = true
    @Published var zeroArea = false
    @Published var alwaysNotifyEmails: [String] = []
    @Published var contractorEmails: [String: String] = [:]
    @Published var monitorRunning = false
    @Published var referenceFieldMessage = ""
    @Published var exclusionZoneMessage = ""
    @Published var nogoZoneMessage = ""
    @Published var zeroAreaMessage = ""

    private let baseURL = "https://jobs.rotorsync.com/api/notifications"

    func loadConfig() async {
        do {
            guard let url = URL(string: "\(baseURL)/config") else { return }
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseData = json["data"] as? [String: Any] {

                if let rules = responseData["notificationRules"] as? [String: Bool] {
                    outlines = rules["outlines"] ?? true
                    exclusion = rules["exclusion"] ?? true
                    nogo = rules["nogo"] ?? true
                    zeroArea = rules["zeroArea"] ?? false
                }

                alwaysNotifyEmails = responseData["alwaysNotify"] as? [String] ?? []
                contractorEmails = responseData["contractorEmails"] as? [String: String] ?? [:]
            }

            await loadMonitorStatus()
            await loadCustomMessages()
        } catch {
            print("Failed to load config: \(error)")
        }
    }

    func loadCustomMessages() async {
        do {
            guard let url = URL(string: "\(baseURL)/custom-messages") else { return }
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messages = json["data"] as? [String: String] {
                referenceFieldMessage = messages["reference_field"] ?? ""
                exclusionZoneMessage = messages["exclusion_zone"] ?? ""
                nogoZoneMessage = messages["nogo_zone"] ?? ""
                zeroAreaMessage = messages["zero_area"] ?? ""
            }
        } catch {
            print("Failed to load custom messages: \(error)")
        }
    }

    func saveCustomMessage(type: String, message: String) {
        Task {
            do {
                if message.isEmpty {
                    // Delete message
                    guard let url = URL(string: "\(baseURL)/custom-message/\(type)") else { return }
                    var request = URLRequest(url: url)
                    request.httpMethod = "DELETE"
                    let (_, _) = try await URLSession.shared.data(for: request)
                } else {
                    // Save message
                    guard let url = URL(string: "\(baseURL)/custom-message") else { return }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["type": type, "message": message])
                    let (_, _) = try await URLSession.shared.data(for: request)
                }
            } catch {
                print("Failed to save custom message: \(error)")
            }
        }
    }

    func loadMonitorStatus() async {
        do {
            guard let url = URL(string: "\(baseURL)/monitor/status") else { return }
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let statusData = json["data"] as? [String: Any] {
                monitorRunning = statusData["running"] as? Bool ?? false
            }
        } catch {
            print("Failed to load monitor status: \(error)")
        }
    }

    func updateRules() {
        Task {
            do {
                guard let url = URL(string: "\(baseURL)/config") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "notificationRules": [
                        "outlines": outlines,
                        "exclusion": exclusion,
                        "nogo": nogo,
                        "zeroArea": zeroArea
                    ]
                ]

                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, _) = try await URLSession.shared.data(for: request)
            } catch {
                print("Failed to update rules: \(error)")
            }
        }
    }

    func addAlwaysNotify(email: String) {
        Task {
            do {
                guard let url = URL(string: "\(baseURL)/always-notify") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])

                let (_, _) = try await URLSession.shared.data(for: request)
                await loadConfig()
            } catch {
                print("Failed to add email: \(error)")
            }
        }
    }

    func removeAlwaysNotify(email: String) {
        Task {
            do {
                let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
                guard let url = URL(string: "\(baseURL)/always-notify/\(encodedEmail)") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"

                let (_, _) = try await URLSession.shared.data(for: request)
                await loadConfig()
            } catch {
                print("Failed to remove email: \(error)")
            }
        }
    }

    func setContractorEmail(contractor: String, email: String) {
        Task {
            do {
                guard let url = URL(string: "\(baseURL)/contractor-email") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["contractor": contractor, "email": email])

                let (_, _) = try await URLSession.shared.data(for: request)
                await loadConfig()
            } catch {
                print("Failed to set contractor email: \(error)")
            }
        }
    }

    func removeContractorEmail(contractor: String) {
        Task {
            do {
                let encodedContractor = contractor.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? contractor
                guard let url = URL(string: "\(baseURL)/contractor-email/\(encodedContractor)") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"

                let (_, _) = try await URLSession.shared.data(for: request)
                await loadConfig()
            } catch {
                print("Failed to remove contractor email: \(error)")
            }
        }
    }

    func startMonitor() {
        Task {
            do {
                guard let url = URL(string: "\(baseURL)/monitor/start") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"

                let (_, _) = try await URLSession.shared.data(for: request)
                await loadMonitorStatus()
            } catch {
                print("Failed to start monitor: \(error)")
            }
        }
    }

    func stopMonitor() {
        Task {
            do {
                guard let url = URL(string: "\(baseURL)/monitor/stop") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"

                let (_, _) = try await URLSession.shared.data(for: request)
                await loadMonitorStatus()
            } catch {
                print("Failed to stop monitor: \(error)")
            }
        }
    }

    func resetMonitor() {
        Task {
            do {
                guard let url = URL(string: "\(baseURL)/monitor/reset") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"

                let (_, _) = try await URLSession.shared.data(for: request)
            } catch {
                print("Failed to reset monitor: \(error)")
            }
        }
    }
}
