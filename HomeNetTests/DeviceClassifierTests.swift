import Testing
import Foundation
@testable import HomeNet

@Suite("Device Classifier")
struct DeviceClassifierTests {

    // MARK: - Gateway detection

    @Test func gatewayAlwaysClassifiesAsRouter() {
        let result = DeviceClassifier.classify(
            hostname: "myrouter.local",
            services: [],
            openPorts: [80, 443],
            isGateway: true
        )
        #expect(result == .router)
    }

    @Test func gatewayOverridesServiceHints() {
        let services = [DiscoveredService(type: "_printer._tcp", name: "Gateway")]
        let result = DeviceClassifier.classify(
            hostname: nil,
            services: services,
            openPorts: [],
            isGateway: true
        )
        #expect(result == .router)
    }

    // MARK: - Service-based classification

    @Test func printerServiceDetected() {
        let services = [DiscoveredService(type: "_printer._tcp", name: "HP LaserJet")]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .printer)
    }

    @Test func ippServiceDetected() {
        let services = [DiscoveredService(type: "_ipp._tcp", name: "Canon")]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .printer)
    }

    @Test func scannerServiceDetected() {
        let services = [DiscoveredService(type: "_scanner._tcp", name: "Epson Scanner")]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .printer)
    }

    @Test func chromecastDetected() {
        let services = [DiscoveredService(type: "_googlecast._tcp", name: "Living Room TV")]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .tv)
    }

    @Test func airplayAppleTVDetected() {
        let services = [DiscoveredService(type: "_airplay._tcp", name: "Apple TV")]
        let result = DeviceClassifier.classify(hostname: "Apple-TV.local", services: services, openPorts: [], isGateway: false)
        #expect(result == .tv)
    }

    @Test func airplayHomePodDetected() {
        let services = [DiscoveredService(type: "_airplay._tcp", name: "HomePod")]
        let result = DeviceClassifier.classify(hostname: "HomePod-Mini.local", services: services, openPorts: [], isGateway: false)
        #expect(result == .speaker)
    }

    @Test func sonosDetected() {
        let services = [DiscoveredService(type: "_sonos._tcp", name: "Sonos One")]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .speaker)
    }

    @Test func spotifyConnectDetected() {
        let services = [DiscoveredService(type: "_spotify-connect._tcp", name: "Kitchen Speaker")]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .speaker)
    }

    @Test func amazonEchoDetected() {
        let services = [DiscoveredService(type: "_amzn-wplay._tcp", name: "Echo Dot")]
        let result = DeviceClassifier.classify(hostname: "echo-dot.local", services: services, openPorts: [], isGateway: false)
        #expect(result == .speaker)
    }

    @Test func homekitDeviceDetected() {
        let services = [DiscoveredService(type: "_hap._tcp", name: "Hue Bridge")]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .smarthome)
    }

    @Test func threadMatterDetected() {
        let services = [DiscoveredService(type: "_meshcop._udp", name: "Thread Border Router")]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .smarthome)
    }

    @Test func companionLinkiPhoneDetected() {
        let services = [DiscoveredService(type: "_companion-link._tcp", name: "iPhone")]
        let result = DeviceClassifier.classify(hostname: "iPhone.local", services: services, openPorts: [], isGateway: false)
        #expect(result == .phone)
    }

    @Test func companionLinkMacDetected() {
        let services = [DiscoveredService(type: "_companion-link._tcp", name: "MacBook")]
        let result = DeviceClassifier.classify(hostname: "MacBook-Pro.local", services: services, openPorts: [], isGateway: false)
        #expect(result == .computer)
    }

    @Test func sshServiceDetected() {
        let services = [DiscoveredService(type: "_ssh._tcp", name: "server")]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .computer)
    }

    @Test func smbWithNASHostname() {
        let services = [DiscoveredService(type: "_smb._tcp", name: "DiskStation")]
        let result = DeviceClassifier.classify(hostname: "DiskStation.local", services: services, openPorts: [], isGateway: false)
        #expect(result == .storage)
    }

    // MARK: - Hostname-based classification

    @Test func iPhoneHostname() {
        let result = DeviceClassifier.classify(hostname: "Pauls-iPhone.local", services: [], openPorts: [], isGateway: false)
        #expect(result == .phone)
    }

    @Test func macBookHostname() {
        let result = DeviceClassifier.classify(hostname: "Pauls-MacBook-Pro.local", services: [], openPorts: [], isGateway: false)
        #expect(result == .computer)
    }

    @Test func galaxyHostname() {
        let result = DeviceClassifier.classify(hostname: "Galaxy-S24.local", services: [], openPorts: [], isGateway: false)
        #expect(result == .phone)
    }

    @Test func playstationHostname() {
        let result = DeviceClassifier.classify(hostname: "PS5-Console.local", services: [], openPorts: [], isGateway: false)
        #expect(result == .gaming)
    }

    @Test func synologyHostname() {
        let result = DeviceClassifier.classify(hostname: "synology-nas.local", services: [], openPorts: [], isGateway: false)
        #expect(result == .storage)
    }

    @Test func hueHostname() {
        let result = DeviceClassifier.classify(hostname: "hue-bridge.local", services: [], openPorts: [], isGateway: false)
        #expect(result == .smarthome)
    }

    @Test func epsonHostname() {
        let result = DeviceClassifier.classify(hostname: "EPSON-ET2850.local", services: [], openPorts: [], isGateway: false)
        #expect(result == .printer)
    }

    @Test func rokuHostname() {
        let result = DeviceClassifier.classify(hostname: "roku-tv.local", services: [], openPorts: [], isGateway: false)
        #expect(result == .tv)
    }

    // MARK: - Port-based classification

    @Test func ippPortSuggestsPrinter() {
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [631], isGateway: false)
        #expect(result == .printer)
    }

    @Test func iDevicePortSuggestsPhone() {
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [62078], isGateway: false)
        #expect(result == .phone)
    }

    @Test func sshPortSuggestsComputer() {
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [22], isGateway: false)
        #expect(result == .computer)
    }

    @Test func airplayPortSuggestsTV() {
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [7000], isGateway: false)
        #expect(result == .tv)
    }

    @Test func noInfoReturnsUnknown() {
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [], isGateway: false)
        #expect(result == .unknown)
    }

    // MARK: - Priority: services beat hostname beat ports

    @Test func serviceTakesPriorityOverHostname() {
        // Hostname says "MacBook" but it's advertising printer services
        let services = [DiscoveredService(type: "_printer._tcp", name: "MacBook Printer")]
        let result = DeviceClassifier.classify(hostname: "MacBook-Pro.local", services: services, openPorts: [], isGateway: false)
        #expect(result == .printer)
    }

    @Test func hostnameTakesPriorityOverPorts() {
        // Ports suggest printer (631), but hostname says PlayStation
        let result = DeviceClassifier.classify(hostname: "PS5-Console.local", services: [], openPorts: [631], isGateway: false)
        #expect(result == .gaming)
    }

    // MARK: - Refined icon

    @Test func macBookGetsLaptopIcon() {
        let device = NetworkDevice(ipAddress: "192.168.1.10", hostname: "MacBook-Pro.local", category: .computer)
        #expect(DeviceClassifier.refinedIcon(for: device) == "laptopcomputer")
    }

    @Test func iMacGetsDesktopIcon() {
        let device = NetworkDevice(ipAddress: "192.168.1.11", hostname: "iMac.local", category: .computer)
        #expect(DeviceClassifier.refinedIcon(for: device) == "desktopcomputer")
    }

    @Test func homepodGetsHomepodIcon() {
        let device = NetworkDevice(ipAddress: "192.168.1.12", hostname: "HomePod-Mini.local", category: .speaker)
        #expect(DeviceClassifier.refinedIcon(for: device) == "homepodmini")
    }

    @Test func appleTVGetsAppleTVIcon() {
        let device = NetworkDevice(ipAddress: "192.168.1.13", hostname: "Apple-TV.local", category: .tv)
        #expect(DeviceClassifier.refinedIcon(for: device) == "appletv")
    }

    // MARK: - Probe-based classification

    @Test func upnpMediaRendererClassifiesAsTV() {
        let probes = [ProbeEntry(source: "UPnP", label: "Device Type", value: "MediaRenderer:1")]
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [80], isGateway: false, probeResults: probes)
        #expect(result == .tv)
    }

    @Test func upnpPrinterClassifiesAsPrinter() {
        let probes = [ProbeEntry(source: "UPnP", label: "Device Type", value: "Printer:1")]
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [80], isGateway: false, probeResults: probes)
        #expect(result == .printer)
    }

    @Test func upnpManufacturerSonos() {
        let probes = [
            ProbeEntry(source: "UPnP", label: "Manufacturer", value: "Sonos, Inc."),
            ProbeEntry(source: "UPnP", label: "Model", value: "Sonos One"),
        ]
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [80], isGateway: false, probeResults: probes)
        #expect(result == .speaker)
    }

    @Test func httpServerPlexClassifiesAsTV() {
        let probes = [ProbeEntry(source: "HTTP :80", label: "Server", value: "Plex Media Server/1.32")]
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [80], isGateway: false, probeResults: probes)
        #expect(result == .tv)
    }

    @Test func httpPageTitleRouterClassifiesAsRouter() {
        let probes = [ProbeEntry(source: "HTTP :80", label: "Page Title", value: "Router Admin Panel")]
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [80], isGateway: false, probeResults: probes)
        #expect(result == .router)
    }

    @Test func probeManufacturerSynologyClassifiesAsStorage() {
        let probes = [ProbeEntry(source: "UPnP", label: "Manufacturer", value: "Synology")]
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [5000], isGateway: false, probeResults: probes)
        #expect(result == .storage)
    }

    @Test func probeManufacturerPhilipsHueClassifiesAsSmartHome() {
        let probes = [ProbeEntry(source: "UPnP", label: "Manufacturer", value: "Signify Netherlands B.V. (Philips Hue)")]
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [80], isGateway: false, probeResults: probes)
        #expect(result == .smarthome)
    }

    @Test func sshDropbearClassifiesAsSmartHome() {
        let probes = [ProbeEntry(source: "SSH", label: "Version", value: "SSH-2.0-dropbear_2020.81")]
        let result = DeviceClassifier.classify(hostname: nil, services: [], openPorts: [22], isGateway: false, probeResults: probes)
        #expect(result == .smarthome)
    }

    @Test func serviceTakesPriorityOverProbe() {
        // Service says printer, probe suggests TV — service should win
        let services = [DiscoveredService(type: "_printer._tcp", name: "test")]
        let probes = [ProbeEntry(source: "UPnP", label: "Device Type", value: "MediaRenderer:1")]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [80], isGateway: false, probeResults: probes)
        #expect(result == .printer)
    }

    @Test func upnpFriendlyNameUsedAsDisplayName() {
        let device = NetworkDevice(
            ipAddress: "192.168.1.50",
            hostname: "device-abc123.local",
            probeResults: [ProbeEntry(source: "UPnP", label: "Name", value: "Living Room Speaker")]
        )
        #expect(device.displayName == "Living Room Speaker")
    }

    // MARK: - TXT record / Apple model ID classification

    @Test func txtRecordMacBookProModelClassifiesAsComputer() {
        let services = [DiscoveredService(type: "_device-info._tcp", name: "test", txtRecords: ["model": "MacBookPro18,1"])]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .computer)
    }

    @Test func txtRecordAppleTVModelClassifiesAsTV() {
        let services = [DiscoveredService(type: "_airplay._tcp", name: "test", txtRecords: ["am": "AppleTV6,2"])]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .tv)
    }

    @Test func txtRecordHomePodModelClassifiesAsSpeaker() {
        let services = [DiscoveredService(type: "_raop._tcp", name: "test", txtRecords: ["am": "AudioAccessory5,1"])]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .speaker)
    }

    @Test func txtRecordIPhoneModelClassifiesAsPhone() {
        let services = [DiscoveredService(type: "_companion-link._tcp", name: "test", txtRecords: ["model": "iPhone15,3"])]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .phone)
    }

    @Test func txtRecordIPadModelClassifiesAsApple() {
        let services = [DiscoveredService(type: "_companion-link._tcp", name: "test", txtRecords: ["model": "iPad14,1"])]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .apple)
    }

    @Test func txtRecordModelIDTakesPriorityOverBonjourServiceType() {
        // _raop._tcp would normally classify as speaker, but model says it's a TV
        let services = [DiscoveredService(type: "_raop._tcp", name: "test", txtRecords: ["am": "AppleTV11,1"])]
        let result = DeviceClassifier.classify(hostname: nil, services: services, openPorts: [], isGateway: false)
        #expect(result == .tv)
    }

    @Test func classifyByAppleModelIDMacMini() {
        #expect(DeviceClassifier.classifyByAppleModelID("Macmini9,1") == .computer)
    }

    @Test func classifyByAppleModelIDAirportExpress() {
        #expect(DeviceClassifier.classifyByAppleModelID("AirPort10,1") == .router)
    }
}
