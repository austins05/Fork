import SwiftUI
import CoreLocation

struct FieldDetailsSheet: View {
    let field: FieldData
    let onDismiss: () -> Void

    @State private var showOrderCompletion = false
    @State private var isLoadingWeather = false
    @State private var weatherData: WeatherData?
    @State private var weatherError: String?
    @State private var fetchedNominalAcres: Double?

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
                    detailRow(title: "Req. Acres", value: String(format: "%.2f ac", field.acres))
                    
                    if let nominalAcres = field.nominalAcres, nominalAcres > 0 {
                        detailRow(title: "Nominal Acres", value: String(format: "%.2f ac", nominalAcres))
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
                // Tabula button (only show for Tabula-sourced fields)
                if field.source == .tabula {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 12) {
                            Button(action: {
                                openInTabula()
                            }) {
                                Image("tabula-icon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.black, lineWidth: 1.5)
                                    )
                            }

                            Button(action: loadWeatherAndShowCompletion) {
                                if isLoadingWeather {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.7)
                                        .frame(width: 24, height: 24)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                        .foregroundColor(.green)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.black, lineWidth: 1.5)
                                        )
                                }
                            }
                            .disabled(isLoadingWeather)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Dismiss") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showOrderCompletion) {
            if let weather = weatherData,
               let groundCrew = getUserName() {
                let _ = print("📊 [FieldDetails] Opening OrderCompletion with fetchedNominalAcres: \(fetchedNominalAcres ?? 0), field.acres: \(field.acres)")
                OrderCompletionView(
                    jobId: field.name,
                    fieldName: field.name,
                    groundCrew: groundCrew,
                    windSpeed: weather.windSpeed,
                    windDirection: weather.windDirection,
                    nominalAcres: fetchedNominalAcres,
                    onComplete: {
                        // Optional: Refresh data or perform any cleanup
                        print("✅ Order completed!")
                    }
                )
            }
        }
    }

    private func loadWeatherAndShowCompletion() {
        guard !field.coordinates.isEmpty else {
            weatherError = "No coordinates available for this field"
            return
        }

        // Calculate center of field
        let lats = field.coordinates.map { $0.latitude }
        let lons = field.coordinates.map { $0.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            weatherError = "Invalid field coordinates"
            return
        }

        let centerCoordinate = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        isLoadingWeather = true
        weatherError = nil

        Task {
            do {
                // Fetch weather and job details in parallel
                async let weatherTask = WeatherService.shared.fetchWeather(for: centerCoordinate)
                async let nominalAcresTask = fetchNominalAcres()

                let (weather, nominalAcres) = try await (weatherTask, nominalAcresTask)

                await MainActor.run {
                    weatherData = weather
                    fetchedNominalAcres = nominalAcres
                    isLoadingWeather = false
                    showOrderCompletion = true
                    print("🌤️ Weather loaded: \(weather.windSpeed) mph, \(weather.windDirection)")
                    print("📊 Nominal acres loaded: \(nominalAcres ?? 0)")
                }
            } catch {
                await MainActor.run {
                    isLoadingWeather = false
                    weatherError = "Failed to load data: \(error.localizedDescription)"
                    print("❌ Data load failed: \(error)")
                }
            }
        }
    }

    private func fetchNominalAcres() async throws -> Double? {
        // Only fetch from detail endpoint if this is a Tabula field with a jobId
        guard field.source == .tabula, let jobId = field.jobId else {
            print("⚠️ Not a Tabula field or no jobId, using field.nominalAcres: \(field.nominalAcres ?? 0)")
            return field.nominalAcres
        }

        print("📡 Fetching job details for jobId: \(jobId)")
        let url = URL(string: "https://jobs.rotorsync.com/api/field-maps/\(jobId)")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("❌ Failed to fetch job details")
            return field.nominalAcres
        }

        // Parse the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobData = json["data"] as? [String: Any],
              let areaNominal = jobData["area_nominal"] as? Double else {
            print("❌ Failed to parse area_nominal from response")
            return field.nominalAcres
        }

        // Convert hectares to acres
        let nominalAcres = areaNominal * 2.47105
        print("✅ Fetched area_nominal: \(areaNominal) ha = \(nominalAcres) acres")
        return nominalAcres
    }

    private func getUserName() -> String? {
        guard let userData = UserDefaults.standard.data(forKey: "userData"),
              let user = try? JSONDecoder().decode(User.self, from: userData) else {
            return nil
        }
        return user.name
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
}
