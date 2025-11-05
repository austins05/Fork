import Foundation

enum DeviceAssetType {
    case baler, bulldozer, chaser, drone, fixedWing, fuelTruck,
         helicopter, jet, motorbike, nurseTruck, quadBike,
         sideBySide, sprayTruck, spreaderTruck, telehandler,
         tractor, tractorTrailer, truck, ute, other

    init?(rawValue: String) {
        let normalized = rawValue.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "baler":               self = .baler
        case "bulldozer":           self = .bulldozer
        case "chaser":              self = .chaser
        case "drone":               self = .drone
        case "fixedwing":           self = .fixedWing
        case "fueltruck":           self = .fuelTruck
        case "helicopter":          self = .helicopter
        case "jet":                 self = .jet
        case "motorbike":           self = .motorbike
        case "nursetruck":          self = .nurseTruck
        case "quadbike":            self = .quadBike
        case "sidebyside":          self = .sideBySide
        case "spraytruck":          self = .sprayTruck
        case "spreadertruck":       self = .spreaderTruck
        case "telehandler":         self = .telehandler
        case "tractor":             self = .tractor
        case "tractortrailer":      self = .tractorTrailer
        case "truck":               self = .truck
        case "ute":                 self = .ute
        default:                    self = .other
        }
    }

    var systemImageName: String {
        switch self {
        case .baler:          return "leaf.arrow.triangle.circlepath"
        case .bulldozer:      return "hammer.fill"
        case .chaser, .sideBySide, .ute:
            return "car.fill"
        case .drone:          return "drone.fill"
        case .fixedWing:      return "airplane"
        case .fuelTruck:      return "fuelpump.fill"
        case .helicopter:     return "helicopter.fill"
        case .jet:            return "airplane.departure"
        case .motorbike:      return "figure.motorcycle"
        case .nurseTruck, .sprayTruck, .spreaderTruck, .truck:
            return "truck.box.fill"
        case .quadBike:       return "bolt.fill"
        case .telehandler:    return "gearshape.fill"
        case .tractor:        return "figure.roll"
        case .tractorTrailer: return "box.truck.fill"
        case .other:          return "circle.fill"
        }
    }
}
