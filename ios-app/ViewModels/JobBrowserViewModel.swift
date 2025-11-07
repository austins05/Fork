//
//  JobBrowserViewModel.swift
//  Rotorsync - Tabula API Integration
//
//  ViewModel for browsing and managing Tabula jobs (field maps)
//

import Foundation
import SwiftUI
import Combine
import MapKit

@MainActor
class JobBrowserViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var jobs: [TabulaJob] = []
    @Published var selectedJob: TabulaJob?
    @Published var jobDetail: TabulaJobDetail?
    @Published var jobGeometry: GeoJSONFeatureCollection?

    @Published var isLoading = false
    @Published var isLoadingDetail = false
    @Published var isLoadingGeometry = false

    @Published var showError = false
    @Published var errorMessage = ""

    @Published var searchText = ""
    @Published var filterStatus: String = "all"

    // MARK: - Services

    private let apiService = TabulaAPIService()

    // MARK: - Computed Properties

    var filteredJobs: [TabulaJob] {
        var filtered = jobs

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { job in
                job.name.localizedCaseInsensitiveContains(searchText) ||
                job.customer.localizedCaseInsensitiveContains(searchText) ||
                job.orderNumber.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by status
        if filterStatus != "all" {
            filtered = filtered.filter { $0.status.lowercased() == filterStatus.lowercased() }
        }

        // Hide deleted jobs
        filtered = filtered.filter { !$0.deleted }

        return filtered.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    var statusOptions: [String] {
        let statuses = Set(jobs.map { $0.status.capitalized })
        return ["all"] + statuses.sorted()
    }

    // MARK: - Methods

    /// Load all jobs for the configured account
    func loadJobs() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Get jobs for default account (5429)
            let response = try await fetchJobs(accountId: "5429")
            jobs = response.data

            print("✅ Loaded \(jobs.count) jobs")

        } catch {
            errorMessage = "Failed to load jobs: \(error.localizedDescription)"
            showError = true
            print("❌ Error loading jobs: \(error)")
        }
    }

    /// Refresh jobs list
    func refreshJobs() async {
        await loadJobs()
    }

    /// Load detailed information for a job
    func loadJobDetail(for job: TabulaJob) async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            let url = URL(string: "\(apiService.baseURL)/field-maps/\(job.id)")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw APIError.invalidResponse
            }

            let apiResponse = try JSONDecoder().decode(JobDetailAPIResponse.self, from: data)
            jobDetail = apiResponse.data

            print("✅ Loaded job detail for: \(job.name)")

        } catch {
            errorMessage = "Failed to load job details: \(error.localizedDescription)"
            showError = true
            print("❌ Error loading job detail: \(error)")
        }
    }

    /// Load geometry (field boundaries) for a job
    func loadJobGeometry(for job: TabulaJob) async -> GeoJSONFeatureCollection? {
        isLoadingGeometry = true
        defer { isLoadingGeometry = false }

        do {
            let url = URL(string: "\(apiService.baseURL)/field-maps/\(job.id)/download?format=geojson")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw APIError.invalidResponse
            }

            let apiResponse = try JSONDecoder().decode(GeometryAPIResponse.self, from: data)
            jobGeometry = apiResponse.data

            print("✅ Loaded geometry for: \(job.name)")
            return apiResponse.data

        } catch {
            errorMessage = "Failed to load field boundaries: \(error.localizedDescription)"
            showError = true
            print("❌ Error loading geometry: \(error)")
            return nil
        }
    }

    /// Select a job and load its details
    func selectJob(_ job: TabulaJob) async {
        selectedJob = job

        // Load details and geometry in parallel
        async let detailTask = loadJobDetail(for: job)
        async let geometryTask = loadJobGeometry(for: job)

        await detailTask
        _ = await geometryTask
    }

    /// Clear selection
    func clearSelection() {
        selectedJob = nil
        jobDetail = nil
        jobGeometry = nil
    }

    // MARK: - Private Methods

    private func fetchJobs(accountId: String) async throws -> JobsAPIResponse {
        let url = URL(string: "\(apiService.baseURL)/field-maps/customer/\(accountId)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return try JSONDecoder().decode(JobsAPIResponse.self, from: data)
    }
}

// MARK: - API Error Extension

extension TabulaAPIService {
    var baseURL: String {
        "http://192.168.68.226:3000/api"
    }
}
