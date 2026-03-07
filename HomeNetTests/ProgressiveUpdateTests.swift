import Testing
import Foundation
@testable import HomeNet

@Suite("Progressive Update Simulation")
struct ProgressiveUpdateTests {

    // Simulates the scan pipeline: devices arrive as bare IPs, then get
    // progressively enriched with hostnames, ports, services, and classification.
    // This verifies the data transformations work correctly at each stage.

    @Test func deviceStartsAsUnknownWithIPOnly() {
        let device = NetworkDevice(ipAddress: "192.168.1.42")
        #expect(device.category == .unknown)
        #expect(device.hostname == nil)
        #expect(device.displayName == "192.168.1.42")
        #expect(device.services.isEmpty)
        #expect(device.openPorts.isEmpty)
    }

    @Test func addingHostnameChangesDisplayName() {
        var device = NetworkDevice(ipAddress: "192.168.1.42")
        device.hostname = "MacBook-Pro.local"
        #expect(device.displayName == "MacBook-Pro")
    }

    @Test func addingHostnameTriggersReclassification() {
        var device = NetworkDevice(ipAddress: "192.168.1.42")
        #expect(device.category == .unknown)

        device.hostname = "MacBook-Pro.local"
        device.category = DeviceClassifier.classify(
            hostname: device.hostname,
            services: device.services,
            openPorts: device.openPorts,
            isGateway: false
        )
        #expect(device.category == .computer)
    }

    @Test func addingPortsRefinesClassification() {
        var device = NetworkDevice(ipAddress: "192.168.1.42")
        device.openPorts = [62078]
        device.category = DeviceClassifier.classify(
            hostname: nil,
            services: device.services,
            openPorts: device.openPorts,
            isGateway: false
        )
        #expect(device.category == .phone)
    }

    @Test func addingServicesOverridesPortClassification() {
        var device = NetworkDevice(ipAddress: "192.168.1.42")
        device.openPorts = [22]  // would suggest computer
        device.services = [DiscoveredService(type: "_printer._tcp", name: "Printer")]
        device.category = DeviceClassifier.classify(
            hostname: nil,
            services: device.services,
            openPorts: device.openPorts,
            isGateway: false
        )
        #expect(device.category == .printer)
    }

    @Test func fullProgressivePipeline() {
        // Stage 1: IP only
        var device = NetworkDevice(ipAddress: "192.168.1.50")
        #expect(device.category == .unknown)
        #expect(device.displayName == "192.168.1.50")

        // Stage 2: Hostname resolved
        device.hostname = "Living-Room-Sonos.local"
        device.category = DeviceClassifier.classify(
            hostname: device.hostname,
            services: device.services,
            openPorts: device.openPorts,
            isGateway: false
        )
        #expect(device.displayName == "Living-Room-Sonos")
        #expect(device.category == .speaker)

        // Stage 3: Ports scanned
        device.openPorts = [80, 443, 1400]

        // Stage 4: Bonjour service matched
        device.services = [
            DiscoveredService(type: "_sonos._tcp", name: "Living Room"),
            DiscoveredService(type: "_spotify-connect._tcp", name: "Sonos"),
        ]
        device.category = DeviceClassifier.classify(
            hostname: device.hostname,
            services: device.services,
            openPorts: device.openPorts,
            isGateway: false
        )
        #expect(device.category == .speaker)
        #expect(device.services.count == 2)
    }

    @Test func multipleDevicesProgressivelyEnriched() {
        // Simulate a batch of devices going through the pipeline
        var devices: [NetworkDevice] = [
            NetworkDevice(ipAddress: "192.168.1.1", category: .router),
            NetworkDevice(ipAddress: "192.168.1.10"),
            NetworkDevice(ipAddress: "192.168.1.20"),
            NetworkDevice(ipAddress: "192.168.1.30"),
        ]

        // All start unknown except router
        #expect(devices[0].category == .router)
        #expect(devices[1].category == .unknown)
        #expect(devices[2].category == .unknown)
        #expect(devices[3].category == .unknown)

        // Batch resolve: hostnames arrive
        let hostnames: [String?] = [nil, "MacBook-Pro.local", "iPhone.local", nil]
        let ports: [[UInt16]] = [[], [22, 548], [62078], [631]]

        for i in 1..<devices.count {
            devices[i].hostname = hostnames[i]
            devices[i].openPorts = ports[i]
            devices[i].category = DeviceClassifier.classify(
                hostname: devices[i].hostname,
                services: devices[i].services,
                openPorts: devices[i].openPorts,
                isGateway: false
            )
        }

        #expect(devices[0].category == .router)
        #expect(devices[1].category == .computer)
        #expect(devices[2].category == .phone)
        #expect(devices[3].category == .printer)
    }

    @Test func equalityChangesWhenDeviceIsEnriched() {
        let bare = NetworkDevice(ipAddress: "192.168.1.5")
        var enriched = NetworkDevice(ipAddress: "192.168.1.5")
        enriched.hostname = "server.local"
        enriched.category = .computer
        enriched.openPorts = [22, 80]

        // They should NOT be equal because visible properties differ
        #expect(bare != enriched)

        // But they should have the same hash (IP-based) for Set dedup
        #expect(bare.hashValue == enriched.hashValue)
    }

    @Test func bonjourServiceMatchingByName() {
        var device = NetworkDevice(ipAddress: "192.168.1.15", hostname: "HomePod-Mini.local")

        // Simulate Bonjour match: "HomePod Mini" service name contains "homepod"
        let bonjourName = "HomePod Mini"
        let cleanDeviceName = device.displayName.lowercased()  // "homepod-mini"
        let bonjourLower = bonjourName.lowercased()             // "homepod mini"

        // Check the matching logic works
        let matches = cleanDeviceName.contains("homepod") && bonjourLower.contains("homepod")
        #expect(matches)

        if matches {
            device.services = [
                DiscoveredService(type: "_airplay._tcp", name: bonjourName),
                DiscoveredService(type: "_raop._tcp", name: bonjourName),
            ]
        }

        device.category = DeviceClassifier.classify(
            hostname: device.hostname,
            services: device.services,
            openPorts: [],
            isGateway: false
        )
        #expect(device.category == .speaker)
    }

    @Test func probeResultsRefineUnknownDevice() {
        // Device starts as unknown — only has an IP and open port 80
        var device = NetworkDevice(ipAddress: "192.168.1.99", category: .unknown, openPorts: [80])
        #expect(device.category == .unknown)
        #expect(device.probeResults.isEmpty)

        // After probing, UPnP reveals it's a Sonos speaker
        device.probeResults = [
            ProbeEntry(source: "UPnP", label: "Manufacturer", value: "Sonos, Inc."),
            ProbeEntry(source: "UPnP", label: "Model", value: "Sonos One"),
            ProbeEntry(source: "UPnP", label: "Name", value: "Living Room"),
        ]

        // Reclassify with probe results
        device.category = DeviceClassifier.classify(
            hostname: device.hostname,
            services: device.services,
            openPorts: device.openPorts,
            isGateway: false,
            probeResults: device.probeResults
        )

        #expect(device.category == .speaker)
        #expect(device.displayName == "Living Room")
    }

    @Test func probeResultsChangeEquality() {
        let bare = NetworkDevice(ipAddress: "192.168.1.50")
        var probed = NetworkDevice(ipAddress: "192.168.1.50")
        probed.probeResults = [ProbeEntry(source: "HTTP :80", label: "Server", value: "nginx")]

        #expect(bare != probed)
    }
}
