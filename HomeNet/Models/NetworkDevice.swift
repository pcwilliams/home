import Foundation
import SwiftUI

// MARK: - Shared helpers

/// Strip RAOP-style "HEXMAC@" prefix from Bonjour names (e.g. "D0817AD9AF37@Paul's iMac Pro" → "Paul's iMac Pro")
func stripBonjourHexPrefix(_ name: String) -> String {
    guard let atIndex = name.firstIndex(of: "@") else { return name }
    let prefix = name[name.startIndex..<atIndex]
    if prefix.count >= 6 && prefix.allSatisfy(\.isHexDigit) {
        return String(name[name.index(after: atIndex)...])
    }
    return name
}

/// Strip domain suffixes (.local, .lan, .home.arpa) from a hostname for display
func cleanHostname(_ name: String) -> String {
    var result = name
    for suffix in [".local.", ".local", ".lan", ".home.arpa"] {
        if result.hasSuffix(suffix) {
            result = String(result.dropLast(suffix.count))
            break
        }
    }
    return result
}

// MARK: - DeviceCategory

enum DeviceCategory: String, CaseIterable, Codable {
    case router = "Router"
    case apple = "Apple"
    case computer = "Computer"
    case phone = "Phone"
    case speaker = "Speaker"
    case tv = "TV & Media"
    case printer = "Printer"
    case smarthome = "Smart Home"
    case gaming = "Gaming"
    case storage = "Storage"
    case unknown = "Unknown"

    var swiftUIColor: Color {
        switch self {
        case .router: return .blue
        case .apple: return .cyan
        case .computer: return .purple
        case .phone: return .indigo
        case .speaker: return .orange
        case .tv: return .pink
        case .printer: return .green
        case .smarthome: return .yellow
        case .gaming: return .red
        case .storage: return .teal
        case .unknown: return .gray
        }
    }

    var icon: String {
        switch self {
        case .router: return "wifi.router"
        case .apple: return "apple.logo"
        case .computer: return "laptopcomputer"
        case .phone: return "smartphone"
        case .speaker: return "hifispeaker"
        case .tv: return "tv"
        case .printer: return "printer"
        case .smarthome: return "lightbulb"
        case .gaming: return "gamecontroller"
        case .storage: return "externaldrive"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct DiscoveredService: Identifiable, Hashable, Codable {
    let id: UUID
    let type: String
    let name: String
    let port: Int?
    let txtRecords: [String: String]

    init(type: String, name: String, port: Int? = nil, txtRecords: [String: String] = [:]) {
        self.id = UUID()
        self.type = type
        self.name = name
        self.port = port
        self.txtRecords = txtRecords
    }
}

struct NetworkDevice: Identifiable, Hashable {
    let id: UUID
    var ipAddress: String
    var hostname: String?
    var category: DeviceCategory
    var services: [DiscoveredService]
    var openPorts: [UInt16]
    var probeResults: [ProbeEntry]
    var firstSeen: Date
    var lastSeen: Date
    var isThisDevice: Bool
    var isStale: Bool

    /// Display name priority: probe name → longest Bonjour name → cleaned hostname → IP
    var displayName: String {
        // 1. Probe-discovered friendly name (UPnP, AirPlay, Chromecast)
        if let probeName = probeResults.first(where: { $0.label == "Name" })?.value {
            return probeName
        }
        // 2. Longest Bonjour service name after stripping RAOP hex prefix
        let bestBonjourName = services
            .map { stripBonjourHexPrefix($0.name) }
            .filter { !$0.isEmpty }
            .max(by: { $0.count < $1.count })
        if let bonjourName = bestBonjourName {
            return bonjourName
        }
        // 3. Cleaned hostname (strips .local, .lan, .home.arpa suffixes)
        if let hostname = hostname {
            return cleanHostname(hostname)
        }
        // 4. Raw IP address
        return ipAddress
    }

    var subtitleText: String {
        // If displayName is already showing the IP, don't repeat it
        if displayName == ipAddress {
            return ""
        }
        return ipAddress
    }

    var manufacturer: String? {
        probeResults.first(where: { $0.label == "Manufacturer" })?.value
    }

    var model: String? {
        probeResults.first(where: { $0.label == "Model" })?.value
    }

    var isGateway: Bool {
        category == .router
    }

    init(ipAddress: String, hostname: String? = nil, category: DeviceCategory = .unknown,
         services: [DiscoveredService] = [], openPorts: [UInt16] = [],
         probeResults: [ProbeEntry] = [], isThisDevice: Bool = false) {
        self.id = UUID()
        self.ipAddress = ipAddress
        self.hostname = hostname
        self.category = category
        self.services = services
        self.openPorts = openPorts
        self.probeResults = probeResults
        self.firstSeen = Date()
        self.lastSeen = Date()
        self.isThisDevice = isThisDevice
        self.isStale = false
    }

    // Hash uses only IP so Set<NetworkDevice> deduplicates by address.
    // Equality checks all visible properties so SwiftUI re-renders when
    // hostname, category, services, or stale state change.
    func hash(into hasher: inout Hasher) {
        hasher.combine(ipAddress)
    }

    static func == (lhs: NetworkDevice, rhs: NetworkDevice) -> Bool {
        lhs.ipAddress == rhs.ipAddress
            && lhs.hostname == rhs.hostname
            && lhs.category == rhs.category
            && lhs.services == rhs.services
            && lhs.openPorts == rhs.openPorts
            && lhs.probeResults == rhs.probeResults
            && lhs.isStale == rhs.isStale
    }
}
