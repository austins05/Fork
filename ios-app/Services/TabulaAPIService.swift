//
//  TabulaAPIService.swift
//  Rotorsync - Terralink Integration
//
//  Service for communicating with Terralink backend API
//

import Foundation
import Combine

class TabulaAPIService: ObservableObject {
    // MARK: - Configuration

    // TODO: Update this with the actual backend URL once deployed
    private let baseURL = "http://192.168.68.226:3000/api"

    private let session: URLSession
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Customer Methods

    /// Search for customers by query string
    func searchCustomers(query: String, limit: Int = 50) async throws -> [Customer] {
        guard !query.isEmpty else {
            throw APIError.invalidInput("Search query cannot be empty")
        }

        guard var components = URLComponents(string: "\(baseURL)/customers/search") else {
            throw APIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(CustomerSearchResponse.self, from: data)

        guard apiResponse.success else {
            throw APIError.apiError(apiResponse.error ?? "Unknown error")
        }

        return apiResponse.data
    }

    /// Get customer details by ID
    func getCustomer(id: String) async throws -> Customer {
        guard let url = URL(string: "\(baseURL)/customers/\(id)") else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let apiResponse = try JSONDecoder().decode(APIResponse<Customer>.self, from: data)

        guard let customer = apiResponse.data else {
            throw APIError.noData
        }

        return customer
    }

    // MARK: - Field Map Methods

    /// Get field maps for a single customer
    func getFieldMaps(customerId: String) async throws -> [FieldMap] {
        guard let url = URL(string: "\(baseURL)/field-maps/customer/\(customerId)") else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let apiResponse = try JSONDecoder().decode(FieldMapsResponse.self, from: data)

        guard apiResponse.success else {
            throw APIError.apiError("Failed to fetch field maps")
        }

        return apiResponse.data
    }

    /// Get field maps for multiple customers (bulk request)
    func getFieldMapsForCustomers(customerIds: [String]) async throws -> [FieldMap] {
        guard !customerIds.isEmpty else {
            throw APIError.invalidInput("Customer IDs cannot be empty")
        }

        guard let url = URL(string: "\(baseURL)/field-maps/bulk") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["customerIds": customerIds]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let apiResponse = try JSONDecoder().decode(FieldMapsResponse.self, from: data)

        guard apiResponse.success else {
            throw APIError.apiError("Failed to fetch field maps")
        }

        return apiResponse.data
    }

    /// Get detailed field map data
    func getFieldMapDetails(fieldId: String) async throws -> FieldMap {
        guard let url = URL(string: "\(baseURL)/field-maps/\(fieldId)") else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let apiResponse = try JSONDecoder().decode(APIResponse<FieldMap>.self, from: data)

        guard let fieldMap = apiResponse.data else {
            throw APIError.noData
        }

        return fieldMap
    }

    /// Download field map in specific format
    func downloadFieldMap(fieldId: String, format: String = "geojson") async throws -> Data {
        guard var components = URLComponents(string: "\(baseURL)/field-maps/\(fieldId)/download") else {
            throw APIError.invalidURL
        }

        components.queryItems = [URLQueryItem(name: "format", value: format)]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return data
    }

    // MARK: - Health Check

    func checkHealth() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/../health") else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return (200...299).contains(httpResponse.statusCode)
    }
}

// MARK: - API Error Types

enum APIError: LocalizedError {
    case invalidURL
    case invalidInput(String)
    case invalidResponse
    case noData
    case serverError(statusCode: Int)
    case apiError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .noData:
            return "No data received from server"
        case .serverError(let statusCode):
            return "Server error (status code: \(statusCode))"
        case .apiError(let message):
            return message
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
