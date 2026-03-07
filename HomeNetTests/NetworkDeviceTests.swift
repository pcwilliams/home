import Testing
import Foundation
import SwiftUI
@testable import HomeNet

@Suite("Network Device Model")
struct NetworkDeviceTests {

    // MARK: - Display name

    @Test func displayNameStripsLocalSuffix() {
        let device = NetworkDevice(ipAddress: "192.168.1.5", hostname: "MacBook-Pro.local.")
        #expect(device.displayName == "MacBook-Pro")
    }

    @Test func displayNameStripsLocalWithoutDot() {
        let device = NetworkDevice(ipAddress: "192.168.1.5", hostname: "iPhone.local")
        #expect(device.displayName == "iPhone")
    }

    @Test func displayNameFallsBackToIP() {
        let device = NetworkDevice(ipAddress: "192.168.1.5")
        #expect(device.displayName == "192.168.1.5")
    }

    // MARK: - Gateway detection

    @Test func routerCategoryIsGateway() {
        let device = NetworkDevice(ipAddress: "192.168.1.1", category: .router)
        #expect(device.isGateway == true)
    }

    @Test func nonRouterIsNotGateway() {
        let device = NetworkDevice(ipAddress: "192.168.1.5", category: .computer)
        #expect(device.isGateway == false)
    }

    // MARK: - Equality includes visible properties

    @Test func devicesWithSameIPButDifferentHostnameAreNotEqual() {
        let a = NetworkDevice(ipAddress: "192.168.1.5", hostname: nil)
        var b = NetworkDevice(ipAddress: "192.168.1.5", hostname: "MacBook.local")
        b = NetworkDevice(ipAddress: "192.168.1.5", hostname: "MacBook.local")
        #expect(a != b)
    }

    @Test func devicesWithSameIPButDifferentCategoryAreNotEqual() {
        let a = NetworkDevice(ipAddress: "192.168.1.5", category: .unknown)
        let b = NetworkDevice(ipAddress: "192.168.1.5", category: .computer)
        #expect(a != b)
    }

    @Test func devicesWithSameIPAndPropertiesAreEqual() {
        let a = NetworkDevice(ipAddress: "192.168.1.5", hostname: "test", category: .computer)
        let b = NetworkDevice(ipAddress: "192.168.1.5", hostname: "test", category: .computer)
        #expect(a == b)
    }

    @Test func devicesWithDifferentServicesAreNotEqual() {
        let a = NetworkDevice(ipAddress: "192.168.1.5")
        let services = [DiscoveredService(type: "_http._tcp", name: "Web")]
        let b = NetworkDevice(ipAddress: "192.168.1.5", services: services)
        #expect(a != b)
    }

    // MARK: - Hash uses IP (so Set<NetworkDevice> works for dedup)

    @Test func hashBasedOnIP() {
        let a = NetworkDevice(ipAddress: "192.168.1.5", hostname: "one")
        let b = NetworkDevice(ipAddress: "192.168.1.5", hostname: "two")
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - Device category properties

    @Test func allCategoriesHaveIcons() {
        for category in DeviceCategory.allCases {
            #expect(!category.icon.isEmpty)
        }
    }

    @Test func allCategoriesHaveSwiftUIColors() {
        for category in DeviceCategory.allCases {
            // swiftUIColor returns a Color value — verify it's accessible
            _ = category.swiftUIColor
        }
    }

    // MARK: - Stale state

    @Test func deviceStartsNotStale() {
        let device = NetworkDevice(ipAddress: "192.168.1.5")
        #expect(!device.isStale)
    }

    @Test func staleDeviceChangesEquality() {
        let fresh = NetworkDevice(ipAddress: "192.168.1.5")
        var stale = NetworkDevice(ipAddress: "192.168.1.5")
        stale.isStale = true
        #expect(fresh != stale)
    }

    @Test func staleDeviceCanBeUnstaled() {
        var device = NetworkDevice(ipAddress: "192.168.1.5")
        device.isStale = true
        #expect(device.isStale)
        device.isStale = false
        device.lastSeen = Date()
        #expect(!device.isStale)
    }
}
