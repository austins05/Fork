import Foundation
import CoreLocation

struct KMLPin: Identifiable {
    let id = UUID()
    let name: String
    let description: String?
    let coordinate: CLLocationCoordinate2D
}

class KMLParser {
    static func parse(data: Data) throws -> [KMLPin] {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Invalid KML file", code: -1)
        }
        
        var pins: [KMLPin] = []
        let parser = XMLParser(data: data)
        let delegate = KMLParserDelegate()
        parser.delegate = delegate
        
        if parser.parse() {
            pins = delegate.pins
        } else if let error = parser.parserError {
            throw error
        }
        
        return pins
    }
}

class KMLParserDelegate: NSObject, XMLParserDelegate {
    var pins: [KMLPin] = []
    
    private var currentElement = ""
    private var currentName = ""
    private var currentDescription: String?
    private var currentCoordinates = ""
    private var insidePlacemark = false
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "Placemark" {
            insidePlacemark = true
            currentName = ""
            currentDescription = nil
            currentCoordinates = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if insidePlacemark {
            switch currentElement {
            case "name":
                currentName += trimmed
            case "description":
                if currentDescription == nil {
                    currentDescription = trimmed
                } else {
                    currentDescription! += trimmed
                }
            case "coordinates":
                currentCoordinates += trimmed
            default:
                break
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Placemark" {
            insidePlacemark = false
            
            // Parse coordinates (format: longitude,latitude,altitude)
            let coords = currentCoordinates
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .first?
                .split(separator: ",")
            
            if let coords = coords, coords.count >= 2,
               let lon = Double(coords[0]),
               let lat = Double(coords[1]) {
                
                let pin = KMLPin(
                    name: currentName.isEmpty ? "Unnamed Pin" : currentName,
                    description: currentDescription,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
                pins.append(pin)
            }
        }
    }
}
