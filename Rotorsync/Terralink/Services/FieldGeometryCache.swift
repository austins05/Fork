//
//  FieldGeometryCache.swift
//  Rotorsync - Local cache for field geometries
//
//  Caches field boundary and spray line geometry for instant import
//

import Foundation
import CoreLocation

class FieldGeometryCache {
    static let shared = FieldGeometryCache()

    private let fileManager = FileManager.default
    private let cacheDirectoryName = "FieldGeometryCache"

    private var cacheDirectory: URL {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = urls[0].appendingPathComponent(cacheDirectoryName)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        return cacheDir
    }

    private init() {}

    // MARK: - Cache Storage

    struct CachedGeometry: Codable {
        let fieldId: Int
        let boundaries: [[[String: Double]]]  // Array of boundary polygons
        let sprayLines: [[[String: Double]]]?  // Array of LineString coordinates
        let cachedAt: Date
    }

    /// Cache geometry for a field (supports multiple boundaries)
    func cacheGeometry(fieldId: Int, boundaries: [[CLLocationCoordinate2D]], sprayLines: [[CLLocationCoordinate2D]]?) {
        let boundariesDict = boundaries.map { boundary in
            boundary.map { ["lat": $0.latitude, "lng": $0.longitude] }
        }
        let sprayLinesDict = sprayLines?.map { line in
            line.map { ["lat": $0.latitude, "lng": $0.longitude] }
        }

        let cached = CachedGeometry(
            fieldId: fieldId,
            boundaries: boundariesDict,
            sprayLines: sprayLinesDict,
            cachedAt: Date()
        )

        let fileURL = cacheDirectory.appendingPathComponent("\(fieldId).json")

        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: fileURL)
            print("✅ Cached geometry for field \(fieldId) - \(boundaries.count) boundaries")
        } catch {
            print("❌ Failed to cache geometry for field \(fieldId): \(error)")
        }
    }

    /// Retrieve cached geometry for a field
    func getCachedGeometry(fieldId: Int) -> (boundaries: [[CLLocationCoordinate2D]], sprayLines: [[CLLocationCoordinate2D]]?)? {
        let fileURL = cacheDirectory.appendingPathComponent("\(fieldId).json")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let cached = try JSONDecoder().decode(CachedGeometry.self, from: data)

            // Convert back to CLLocationCoordinate2D
            let boundaries = cached.boundaries.map { boundary in
                boundary.compactMap { dict -> CLLocationCoordinate2D? in
                    guard let lat = dict["lat"], let lng = dict["lng"] else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
            }

            let sprayLines = cached.sprayLines?.map { line in
                line.compactMap { dict -> CLLocationCoordinate2D? in
                    guard let lat = dict["lat"], let lng = dict["lng"] else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
            }

            print("✅ Retrieved cached geometry for field \(fieldId) - \(boundaries.count) boundaries")
            return (boundaries, sprayLines)
        } catch {
            print("❌ Failed to retrieve cached geometry for field \(fieldId): \(error)")
            return nil
        }
    }

    /// Check if geometry is cached for a field
    func isCached(fieldId: Int) -> Bool {
        let fileURL = cacheDirectory.appendingPathComponent("\(fieldId).json")
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Clear all cached geometry
    func clearCache() {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            print("✅ Cleared geometry cache (\(files.count) files)")
        } catch {
            print("❌ Failed to clear cache: \(error)")
        }
    }

    /// Clear cache for specific field
    func clearCache(fieldId: Int) {
        let fileURL = cacheDirectory.appendingPathComponent("\(fieldId).json")
        try? fileManager.removeItem(at: fileURL)
        print("✅ Cleared cache for field \(fieldId)")
    }

    /// Get cache statistics
    func getCacheStats() -> (count: Int, totalSize: Int64) {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: Int64 = 0

            for file in files {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if let fileSize = attributes[.size] as? Int64 {
                    totalSize += fileSize
                }
            }

            return (files.count, totalSize)
        } catch {
            return (0, 0)
        }
    }
}
