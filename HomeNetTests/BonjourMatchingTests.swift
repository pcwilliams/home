import Testing
import Foundation
@testable import HomeNet

@Suite("Bonjour Name Matching")
struct BonjourMatchingTests {

    // MARK: - Hex prefix stripping

    @Test func stripRAOPHexPrefix() {
        #expect(stripBonjourHexPrefix("D0817AD9AF37@Paul's iMac Pro") == "Paul's iMac Pro")
    }

    @Test func stripShortHexPrefix() {
        #expect(stripBonjourHexPrefix("AABBCC@Device") == "Device")
    }

    @Test func leaveNonHexPrefixAlone() {
        #expect(stripBonjourHexPrefix("MacStudioServer") == "MacStudioServer")
    }

    @Test func leaveAtSignWithoutHexPrefix() {
        #expect(stripBonjourHexPrefix("user@hostname") == "user@hostname")
    }

    @Test func leaveEmptyString() {
        #expect(stripBonjourHexPrefix("") == "")
    }

    // MARK: - Name normalisation

    @Test func normaliseStripsLanSuffix() {
        #expect(NetworkViewModel.normaliseName("macstudiom1-7.lan") == "macstudiom1")
    }

    @Test func normaliseStripsLocalDotSuffix() {
        #expect(NetworkViewModel.normaliseName("MacBook-Pro.local.") == "macbook pro")
    }

    @Test func normaliseStripsLocalSuffix() {
        #expect(NetworkViewModel.normaliseName("iPhone.local") == "iphone")
    }

    @Test func normaliseStripsHomeArpaSuffix() {
        #expect(NetworkViewModel.normaliseName("hub.home.arpa") == "hub")
    }

    @Test func normaliseStripsParenthesisedSuffix() {
        #expect(NetworkViewModel.normaliseName("MacStudioM1 (920)") == "macstudiom1")
    }

    @Test func normaliseStripsDNSDisambiguationNumber() {
        #expect(NetworkViewModel.normaliseName("macstudiom1-7") == "macstudiom1")
    }

    @Test func normaliseStripsHexPrefixAndParens() {
        #expect(NetworkViewModel.normaliseName("D0817AD9AF37@Paul's iMac Pro (4979)") == "pauls imac pro")
    }

    @Test func normaliseHandlesCurlyApostrophe() {
        #expect(NetworkViewModel.normaliseName("Paul\u{2019}s iMac Pro") == "pauls imac pro")
    }

    @Test func normaliseCollapsesDashesAndSpaces() {
        #expect(NetworkViewModel.normaliseName("my-cool-device") == "my cool device")
    }

    // MARK: - namesMatch: real network scenarios from log

    @Test func macStudioHostnameMatchesBonjourName() {
        // hostname "macstudiom1-7.lan" should match Bonjour "MacStudioM1 (920)"
        #expect(NetworkViewModel.namesMatch("macstudiom1-7.lan", "MacStudioM1 (920)"))
    }

    @Test func macStudioHostnameMatchesDifferentInstance() {
        // Same Mac Studio, different Bonjour instance number
        #expect(NetworkViewModel.namesMatch("macstudiom1-7.lan", "MacStudioM1 (956)"))
    }

    @Test func ipadLanMatchesBonjour() {
        #expect(NetworkViewModel.namesMatch("ipad.lan", "iPad"))
    }

    @Test func ipadLanMatchesBonjourWithName() {
        #expect(NetworkViewModel.namesMatch("ipad.lan", "Paul's iPad Pro"))
    }

    @Test func macLocalMatchesBonjourName() {
        // hostname "mac.lan" vs Bonjour name "MXL197C7FQ" — these should NOT match
        // (MXL197C7FQ is a serial number, not related to "mac")
        #expect(!NetworkViewModel.namesMatch("mac.lan", "MXL197C7FQ"))
    }

    @Test func macStudioServerMatchesSelf() {
        #expect(NetworkViewModel.namesMatch("MacStudioServer", "MacStudioServer"))
    }

    @Test func imacProWithHexPrefixMatchesClean() {
        #expect(NetworkViewModel.namesMatch(
            "D0817AD9AF37@Paul's iMac Pro (4979)",
            "Paul's iMac Pro"))
    }

    @Test func hubHomeArpaDoesNotMatchRandomName() {
        #expect(!NetworkViewModel.namesMatch("hub.home.arpa", "Aries Kitchen"))
    }

    @Test func exactSameNameMatches() {
        #expect(NetworkViewModel.namesMatch("Living Room", "Living Room"))
    }

    @Test func dashesMatchSpaces() {
        #expect(NetworkViewModel.namesMatch("Family-Room-Apple-TV", "Family Room Apple TV"))
    }

    // MARK: - Display name: probe names preferred

    @Test func displayNamePrefersProbeNameOverIP() {
        let probes = [ProbeEntry(source: "AirPlay", label: "Name", value: "MacStudioServer")]
        let device = NetworkDevice(ipAddress: "192.168.1.173", probeResults: probes)
        #expect(device.displayName == "MacStudioServer")
    }

    @Test func displayNamePrefersProbeNameFromAnySource() {
        let probes = [ProbeEntry(source: "Chromecast", label: "Name", value: "Living Room Speaker")]
        let device = NetworkDevice(ipAddress: "192.168.1.50", probeResults: probes)
        #expect(device.displayName == "Living Room Speaker")
    }

    @Test func displayNamePrefersBonjourOverHostname() {
        let services = [
            DiscoveredService(type: "_airplay._tcp", name: "Paul's iMac Pro"),
            DiscoveredService(type: "_ssh._tcp", name: "Pauls-iMac-Pro"),
        ]
        let device = NetworkDevice(ipAddress: "192.168.1.50", hostname: "pauls-imac-pro.lan", services: services)
        #expect(device.displayName == "Paul's iMac Pro")
    }

    @Test func displayNameStripsHexPrefixFromBonjourName() {
        let services = [
            DiscoveredService(type: "_raop._tcp", name: "D0817AD9AF37@Paul's iMac Pro"),
        ]
        let device = NetworkDevice(ipAddress: "192.168.1.50", services: services)
        #expect(device.displayName == "Paul's iMac Pro")
    }

    @Test func displayNamePicksLongestBonjourName() {
        let services = [
            DiscoveredService(type: "_ssh._tcp", name: "mac"),
            DiscoveredService(type: "_companion-link._tcp", name: "Paul's iMac Pro (4979)"),
            DiscoveredService(type: "_raop._tcp", name: "D0817AD9AF37@Paul's iMac Pro (4979)"),
        ]
        let device = NetworkDevice(ipAddress: "192.168.1.50", services: services)
        // After hex stripping, both _companion-link and _raop give "Paul's iMac Pro (4979)"
        #expect(device.displayName == "Paul's iMac Pro (4979)")
    }

    @Test func displayNameFallsToHostnameWhenNoServices() {
        let device = NetworkDevice(ipAddress: "192.168.1.70", hostname: "macstudiom1-7.lan")
        #expect(device.displayName == "macstudiom1-7")
    }

    @Test func displayNameFallsToIPWhenNothing() {
        let device = NetworkDevice(ipAddress: "192.168.1.182")
        #expect(device.displayName == "192.168.1.182")
    }

    // MARK: - cleanHostname

    @Test func cleanHostnameStripsLocalDot() {
        #expect(cleanHostname("MacBook-Pro.local.") == "MacBook-Pro")
    }

    @Test func cleanHostnameStripsLocal() {
        #expect(cleanHostname("iPhone.local") == "iPhone")
    }

    @Test func cleanHostnameStripsLan() {
        #expect(cleanHostname("macstudiom1-7.lan") == "macstudiom1-7")
    }

    @Test func cleanHostnameStripsHomeArpa() {
        #expect(cleanHostname("hub.home.arpa") == "hub")
    }

    @Test func cleanHostnameLeavesPlainName() {
        #expect(cleanHostname("MyDevice") == "MyDevice")
    }

    // MARK: - Sleep proxy name handling

    @Test func sleepProxyNameNormalisesCleanly() {
        // Sleep proxy names like "70-35-60-63.1 Family Room Apple TV" have IP-like prefixes
        let normalised = NetworkViewModel.normaliseName("70-35-60-63.1 Family Room Apple TV")
        #expect(normalised.contains("family room apple tv"))
    }
}
