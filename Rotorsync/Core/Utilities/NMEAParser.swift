//
//  NMEAParser.swift
//  Rotorsync
//
//  Created for TCP GPS support
//

import Foundation
import CoreLocation

/// Parses NMEA sentences from TCP GPS sources
class NMEAParser {
    
    /// GPS data extracted from NMEA sentences
    struct GPSData {
        var coordinate: CLLocationCoordinate2D
        var altitude: CLLocationDistance
        var timestamp: Date
        var speed: CLLocationSpeed
        var course: CLLocationDirection
        var horizontalAccuracy: CLLocationAccuracy
        var isValid: Bool // Whether GPS has a valid fix
        
        /// Convert to CLLocation for compatibility with existing code
        func toCLLocation() -> CLLocation {
            print("[GPSData] Converting to CLLocation:")
            print("  coordinate: \(coordinate.latitude), \(coordinate.longitude)")
            print("  speed: \(speed) m/s")
            print("  course: \(course)°")
            print("  altitude: \(altitude) m")
            
            let location = CLLocation(
                coordinate: coordinate,
                altitude: altitude,
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: horizontalAccuracy,
                course: course,
                speed: speed,
                timestamp: timestamp
            )
            
            print("[GPSData] CLLocation created:")
            print("  location.speed: \(location.speed) m/s")
            print("  location.course: \(location.course)°")
            print("  speed >= 0? \(location.speed >= 0)")
            
            return location
        }
    }
    
    /// Parse an NMEA sentence and return GPS data if valid
    /// - Parameter nmeaSentence: Raw NMEA sentence string (e.g., "$GPRMC,...")
    /// - Returns: GPSData if parsing succeeds, nil otherwise
    func parse(_ nmeaSentence: String) -> GPSData? {
        // CRITICAL: Use components(separatedBy:) instead of split() to preserve empty fields!
        let parts = nmeaSentence.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ",")
        guard parts.count > 0 else { return nil }
        
        let sentenceType = parts[0]
        
        // Support both GP (GPS) and GN (GNSS - multi-constellation) prefixes
        if sentenceType.hasSuffix("GPRMC") || sentenceType.hasSuffix("GNRMC") {
            return parseGPRMC(parts)
        } else if sentenceType.hasSuffix("GPGGA") || sentenceType.hasSuffix("GNGGA") {
            return parseGPGGA(parts)
        }
        
        return nil
    }
    
    // MARK: - Private Parsing Methods
    
    /// Parse GPRMC (Recommended Minimum) sentence
    /// Format: $GPRMC,time,status,lat,N/S,lon,E/W,speed,course,date,magvar,E/W,mode*checksum
    private func parseGPRMC(_ parts: [String]) -> GPSData? {
        guard parts.count >= 9 else { 
            print("[NMEA] GPRMC: Not enough fields (\(parts.count))")
            return nil 
        }
        
        // Check if data is valid (A = active, V = void)
        let isValid = (parts[2] == "A")
        if !isValid {
            print("[NMEA] GPRMC: Status is VOID (no GPS fix)")
        }
        
        // Parse position
        let latitude = parseLatitude(parts[3], direction: parts[4])
        let longitude = parseLongitude(parts[5], direction: parts[6])
        
        guard let lat = latitude, let lon = longitude else { 
            print("[NMEA] GPRMC: Failed to parse lat/lon")
            return nil 
        }
        
        // Parse speed (field 7) - in KNOTS
        // Handle empty field
        let speedString = parts[7].trimmingCharacters(in: .whitespaces)
        let speedKnots = speedString.isEmpty ? 0.0 : (Double(speedString) ?? 0.0)
        let speedMPS = speedKnots * 0.514444 // Convert knots to m/s
        print("[NMEA] GPRMC: Speed field = '\(parts[7])' -> \(speedKnots) knots = \(speedMPS) m/s = \(speedMPS * 2.23694) mph")
        
        // Parse course (field 8) - in DEGREES
        let courseString = parts[8].trimmingCharacters(in: .whitespaces)
        let course = courseString.isEmpty ? -1.0 : (Double(courseString) ?? -1.0)
        print("[NMEA] GPRMC: Course field = '\(parts[8])' -> \(course)°")
        
        print("[NMEA] GPRMC: ✅ Parsed - Lat: \(lat), Lon: \(lon), Speed: \(speedKnots)kts (\(speedMPS)m/s), Course: \(course)°")
        
        return GPSData(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0, // GPRMC doesn't include altitude
            timestamp: Date(),
            speed: speedMPS, // m/s
            course: course >= 0 ? course : -1, // -1 indicates invalid course
            horizontalAccuracy: 10.0, // Estimate, GPRMC doesn't provide accuracy
            isValid: isValid
        )
    }
    
    /// Parse GPGGA (Global Positioning System Fix Data) sentence
    /// Format: $GPGGA,time,lat,N/S,lon,E/W,quality,numSV,HDOP,alt,M,sep,M,diffAge,diffStation*checksum
    private func parseGPGGA(_ parts: [String]) -> GPSData? {
        guard parts.count >= 10 else { 
            print("[NMEA] GPGGA: Not enough fields (\(parts.count))")
            return nil 
        }
        
        let latitude = parseLatitude(parts[2], direction: parts[3])
        let longitude = parseLongitude(parts[4], direction: parts[5])
        let altitudeString = parts[9].trimmingCharacters(in: .whitespaces)
        let altitude = altitudeString.isEmpty ? 0.0 : (Double(altitudeString) ?? 0.0)
        let hdopString = parts[8].trimmingCharacters(in: .whitespaces)
        let hdop = hdopString.isEmpty ? 1.0 : (Double(hdopString) ?? 1.0)
        let quality = Int(parts[6]) ?? 0 // 0=invalid, 1=GPS, 2=DGPS, etc.
        
        guard let lat = latitude, let lon = longitude else { 
            print("[NMEA] GPGGA: Failed to parse lat/lon")
            return nil 
        }
        
        // Estimate accuracy from HDOP (lower is better, typical range 1-20)
        let accuracy = hdop * 5.0 // Rough conversion to meters
        
        print("[NMEA] GPGGA: Parsed - Lat: \(lat), Lon: \(lon), Alt: \(altitude)m, Quality: \(quality), HDOP: \(hdop)")
        
        return GPSData(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: altitude,
            timestamp: Date(),
            speed: 0, // GPGGA doesn't include speed
            course: -1, // GPGGA doesn't include course, -1 indicates invalid
            horizontalAccuracy: accuracy,
            isValid: quality > 0
        )
    }
    
    /// Parse latitude from NMEA format
    /// Format: DDMM.MMMM where DD = degrees, MM.MMMM = minutes
    private func parseLatitude(_ value: String, direction: String) -> Double? {
        guard value.count >= 4, !value.isEmpty else { return nil }
        
        let degrees = Double(value.prefix(2)) ?? 0
        let minutes = Double(value.dropFirst(2)) ?? 0
        var latitude = degrees + (minutes / 60.0)
        
        if direction == "S" { latitude = -latitude }
        
        return latitude
    }
    
    /// Parse longitude from NMEA format
    /// Format: DDDMM.MMMM where DDD = degrees, MM.MMMM = minutes
    private func parseLongitude(_ value: String, direction: String) -> Double? {
        guard value.count >= 5, !value.isEmpty else { return nil }
        
        let degrees = Double(value.prefix(3)) ?? 0
        let minutes = Double(value.dropFirst(3)) ?? 0
        var longitude = degrees + (minutes / 60.0)
        
        if direction == "W" { longitude = -longitude }
        
        return longitude
    }
}
