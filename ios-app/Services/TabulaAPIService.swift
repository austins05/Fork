//
//  TabulaAPIService.swift
//  Rotorsync - Terralink Integration
//
//  Service for communicating with Terralink backend API
//

import Foundation
import Combine

class TabulaAPIService: ObservableObject {
    static let shared = TabulaAPIService()
    // MARK: - Configuration

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

    // MARK: - Recent Jobs Methods

    /// Get recent field maps (last 20)
    func getRecentFieldMaps(limit: Int = 20) async throws -> [FieldMap] {
        guard var components = URLComponents(string: "\(self.baseURL)/field-maps/recent") else {
            throw APIError.invalidURL
        }
        
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let apiResponse = try JSONDecoder().decode(FieldMapsResponse.self, from: data)

        guard apiResponse.success else {
            throw APIError.apiError("Failed to fetch recent field maps")
        }

        return apiResponse.data
    }

    // MARK: - Customer Methods

    /// Search for customers by query string
    func searchCustomers(query: String, limit: Int = 50) async throws -> [Customer] {
        guard !query.isEmpty else {
            throw APIError.invalidInput("Search query cannot be empty")
        }

        guard var components = URLComponents(string: "\(self.baseURL)/customers/search") else {
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
        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(CustomerSearchResponse.self, from: data)

        guard apiResponse.success else {
            throw APIError.apiError("Request failed")
        }

        return apiResponse.data
    }

    /// Get customer details by ID
    func getCustomer(id: String) async throws -> Customer {
        guard let url = URL(string: "\(self.baseURL)/customers/\(id)") else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await self.session.data(for: request)

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
        guard let url = URL(string: "\(self.baseURL)/field-maps/customer/\(customerId)") else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await self.session.data(for: request)

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

        guard let url = URL(string: "\(self.baseURL)/field-maps/bulk") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["customerIds": customerIds]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await self.session.data(for: request)

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
        guard let url = URL(string: "\(self.baseURL)/field-maps/\(fieldId)") else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await self.session.data(for: request)

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
        guard var components = URLComponents(string: "\(self.baseURL)/field-maps/\(fieldId)/download") else {
            throw APIError.invalidURL
        }

        components.queryItems = [URLQueryItem(name: "format", value: format)]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return data
    }

    // MARK: - Health Check

    func checkHealth() async throws -> Bool {
        guard let url = URL(string: "\(self.baseURL)/../health") else {
            throw APIError.invalidURL
        }

        let request = URLRequest(url: url)
        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return (200...299).contains(httpResponse.statusCode)
    }
    
    /// Get field geometry (boundary coordinates) from backend
    func getFieldGeometry(fieldId: String, type: String = "worked") async throws -> [String: Any] {
        guard let url = URL(string: "\(self.baseURL)/field-maps/\(fieldId)/geometry?type=\(type)") else {
            throw APIError.invalidURL
        }
        
        let request = URLRequest(url: url)
        let (data, response) = try await self.session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        // Parse as generic JSON dictionary since GeoJSON structure can vary
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        return json
    }
    /// Get field geometry AND color from Tabula API  
    func getFieldGeometryWithColor(fieldId: String, type: String = "worked") async throws -> (geometry: [String: Any], color: String?) {
        guard let url = URL(string: "\(self.baseURL)/field-maps/\(fieldId)") else {
            throw APIError.invalidURL
        }
        
        let request = URLRequest(url: url)
        let (data, response) = try await self.session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fieldData = json["data"] as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        // Extract color
        let colorName = fieldData["color"] as? String
        print("🎨 Extracted color from API: \(colorName ?? "nil") for field \(fieldId)")
        
        // Now fetch geometry
        guard let geometryUrl = URL(string: "\(self.baseURL)/field-maps/\(fieldId)/geometry?type=\(type)") else {
            throw APIError.invalidURL
        }
        
        let geoRequest = URLRequest(url: geometryUrl)
        let (geoData, geoResponse) = try await self.session.data(for: geoRequest)
        
        guard let geoHttpResponse = geoResponse as? HTTPURLResponse,
              (200...299).contains(geoHttpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        guard let geometry = try? JSONSerialization.jsonObject(with: geoData) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        
        return (geometry, colorName)
    }
    
    /// Convert Tabula color names to hex codes
    func tabulaColorToHex(_ colorName: String?) -> String {
        guard let name = colorName?.lowercased() else {
            return "#3498db" // Default blue
        }
        
        switch name {
        case "red":
            return "#e74c3c"
        case "blue":
            return "#3498db"
        case "green":
            return "#2ecc71"
        case "yellow":
            return "#f1c40f"
        case "orange":
            return "#e67e22"
        case "purple":
            return "#9b59b6"
        case "pink":
            return "#ff6b9d"
        case "brown":
            return "#8b4513"
        case "gray", "grey":
            return "#95a5a6"
        case "black":
            return "#2c3e50"
        case "cyan":
            return "#1abc9c"
        case "magenta":
            return "#e91e63"
        case "lime":
            return "#8bc34a"
        case "indigo":
            return "#3f51b5"
        case "teal":
            return "#009688"
        default:
            return "#3498db" // Default blue
        }
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
