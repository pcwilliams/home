import Foundation
import SwiftUI

@MainActor
class NetworkViewModel: ObservableObject {
    @Published var devices: [NetworkDevice] = []
    @Published var isScanning = false
    @Published var isProbing = false
    @Published var scanProgress: Double = 0
    @Published var scanStatus: String = "Ready to scan"
    @Published var localIP: String = ""
    @Published var gatewayIP: String = ""
    @Published var subnetMask: String = ""
    @Published var lastScanDate: Date?

    private let scanner = NetworkScanner()
    private let bonjourBrowser = BonjourBrowser()
    private let prober = DeviceProber()
    private var scanTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var staleTimer: Task<Void, Never>?

    /// First scan: clears everything
    func startScan() {
        scanTask?.cancel()
        probeTask?.cancel()
        staleTimer?.cancel()
        scanTask = Task {
            await performScan(refresh: false)
        }
    }

    /// Refresh: keeps existing devices, marks them stale, re-verifies
    func refreshScan() {
        scanTask?.cancel()
        probeTask?.cancel()
        staleTimer?.cancel()
        scanTask = Task {
            await performScan(refresh: true)
        }
    }

    func stopScan() {
        scanTask?.cancel()
        probeTask?.cancel()
        staleTimer?.cancel()
        bonjourBrowser.stopBrowsing()
        isScanning = false
        isProbing = false
        scanStatus = "Scan stopped"
    }

    var hasScanned: Bool {
        lastScanDate != nil
    }

    private func performScan(refresh: Bool) async {
        isScanning = true
        scanProgress = 0

        if refresh {
            for i in devices.indices where !devices[i].isThisDevice {
                devices[i].isStale = true
            }
            scanStatus = "Refreshing network..."

            let staleStart = Date()
            staleTimer = Task {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self.devices.removeAll { $0.isStale && $0.lastSeen < staleStart && !$0.isThisDevice }
                self.updateStatusText()
            }
        } else {
            devices = []
            scanStatus = "Getting network info..."
        }

        guard let networkInfo = await scanner.getNetworkInfo() else {
            scanStatus = "Not connected to Wi-Fi"
            isScanning = false
            return
        }

        localIP = networkInfo.localIP
        gatewayIP = networkInfo.gatewayIP
        subnetMask = networkInfo.subnetMask

        // This device
        if let idx = devices.firstIndex(where: { $0.isThisDevice }) {
            devices[idx].lastSeen = Date()
            devices[idx].isStale = false
        } else {
            devices.append(NetworkDevice(
                ipAddress: networkInfo.localIP,
                hostname: getDeviceName(),
                category: .phone,
                isThisDevice: true
            ))
        }

        if Task.isCancelled { return }

        scanStatus = "Scanning network..."
        scanProgress = 0.05

        // Start Bonjour browsing in parallel (runs for 8s)
        async let bonjourResults = bonjourBrowser.browse(for: 8.0)

        // Resolve gateway immediately
        let gatewayHostname = await scanner.resolveHostname(for: networkInfo.gatewayIP)
        if let idx = devices.firstIndex(where: { $0.ipAddress == networkInfo.gatewayIP }) {
            devices[idx].hostname = gatewayHostname
            devices[idx].lastSeen = Date()
            devices[idx].isStale = false
        } else {
            devices.append(NetworkDevice(
                ipAddress: networkInfo.gatewayIP,
                hostname: gatewayHostname,
                category: .router
            ))
        }

        if Task.isCancelled { return }

        // Stream subnet scan results — devices appear as they respond
        var knownIPs: Set<String> = Set(devices.map(\.ipAddress))
        var newDeviceIndices: [Int] = []
        let stream = await scanner.scanSubnetStream(networkInfo: networkInfo)
        var scannedCount = 0

        for await ip in stream {
            if Task.isCancelled { return }
            scannedCount += 1

            if !knownIPs.contains(ip) {
                knownIPs.insert(ip)
                if let idx = devices.firstIndex(where: { $0.ipAddress == ip }) {
                    devices[idx].lastSeen = Date()
                    devices[idx].isStale = false
                } else {
                    devices.append(NetworkDevice(ipAddress: ip))
                    newDeviceIndices.append(devices.count - 1)
                }
            }

            scanProgress = min(0.05 + Double(scannedCount) * 0.001, 0.35)
            scanStatus = "Found \(devices.count - 1) hosts..."
        }

        if Task.isCancelled { return }

        scanProgress = 0.35
        scanStatus = "Resolving \(devices.count) devices..."

        // Collect Bonjour results
        let foundBonjourResults = await bonjourResults
        if Task.isCancelled { return }

        var bonjourDeviceMap: [String: [DiscoveredService]] = [:]
        for result in foundBonjourResults {
            let service = DiscoveredService(
                type: result.serviceType, name: result.name,
                txtRecords: result.txtRecords
            )
            // Normalise RAOP-style "HEXMAC@Name" keys so they merge with the clean name
            let key = stripBonjourHexPrefix(result.name)
            bonjourDeviceMap[key, default: []].append(service)
        }
        debugLog("Bonjour: \(foundBonjourResults.count) services, \(bonjourDeviceMap.count) unique names")
        for (name, svcs) in bonjourDeviceMap.sorted(by: { $0.key < $1.key }) {
            debugLog("  BJ key '\(name)' — \(svcs.map(\.type).joined(separator: ", "))")
        }

        // Pre-match: check existing devices (from previous scan) against new Bonjour results
        for i in devices.indices {
            guard let hostname = devices[i].hostname else { continue }
            let cleanName = cleanHostname(hostname)
            for (bonjourName, services) in bonjourDeviceMap {
                if Self.namesMatch(cleanName, bonjourName) {
                    debugLog("  Pre-match: '\(cleanName)' == '\(bonjourName)' → \(devices[i].ipAddress)")
                    mergeServices(into: i, newServices: services)
                    bonjourDeviceMap.removeValue(forKey: bonjourName)
                    break
                }
            }
        }

        // Identify all non-gateway, non-self devices — update per-device as each resolves
        let devicesToIdentify = devices.indices.filter {
            !devices[$0].isThisDevice && !devices[$0].isGateway
        }
        let totalToIdentify = devicesToIdentify.count

        let identifyBatchSize = 8
        var totalIdentified = 0
        for batchStart in stride(from: 0, to: devicesToIdentify.count, by: identifyBatchSize) {
            if Task.isCancelled { return }

            let batchEnd = min(batchStart + identifyBatchSize, devicesToIdentify.count)
            let batchIndices = Array(devicesToIdentify[batchStart..<batchEnd])

            await withTaskGroup(of: (Int, String?, [UInt16]).self) { group in
                for idx in batchIndices {
                    let ip = devices[idx].ipAddress
                    group.addTask {
                        async let hostname = self.scanner.resolveHostname(for: ip)
                        async let ports = self.scanner.identifyOpenPorts(ip)
                        return (idx, await hostname, await ports)
                    }
                }

                for await (idx, hostname, ports) in group {
                    devices[idx].hostname = hostname
                    devices[idx].openPorts = ports
                    devices[idx].lastSeen = Date()
                    devices[idx].isStale = false

                    let deviceIP = devices[idx].ipAddress
                    if let name = hostname {
                        let cleanName = cleanHostname(name)
                        var matched = false
                        for (bonjourName, services) in bonjourDeviceMap {
                            let isMatch = Self.namesMatch(cleanName, bonjourName)
                            if isMatch {
                                debugLog("  1st pass MATCH: '\(cleanName)' == '\(bonjourName)' → \(deviceIP)")
                                mergeServices(into: idx, newServices: services)
                                bonjourDeviceMap.removeValue(forKey: bonjourName)
                                matched = true
                                break
                            }
                        }
                        if !matched {
                            debugLog("  1st pass MISS: '\(cleanName)' (\(deviceIP)) — no Bonjour match")
                        }
                    } else {
                        debugLog("  1st pass: \(deviceIP) — no hostname")
                    }

                    devices[idx].category = DeviceClassifier.classify(
                        hostname: devices[idx].hostname,
                        services: devices[idx].services,
                        openPorts: devices[idx].openPorts,
                        isGateway: devices[idx].ipAddress == networkInfo.gatewayIP
                    )

                    totalIdentified += 1
                    scanProgress = 0.35 + (Double(totalIdentified) / Double(max(totalToIdentify, 1))) * 0.60
                    scanStatus = "Identified \(totalIdentified)/\(totalToIdentify) devices..."
                }
            }
        }

        if Task.isCancelled { return }

        // Match remaining Bonjour results to devices
        debugLog("=== Second pass: \(bonjourDeviceMap.count) unmatched Bonjour names ===")
        for (name, services) in bonjourDeviceMap {
            debugLog("  Trying '\(name)' (\(services.map(\.type).joined(separator: ", ")))")
            // Try matching by hostname
            let matchIdx = devices.firstIndex(where: {
                guard let h = $0.hostname else { return false }
                let clean = cleanHostname(h)
                return Self.namesMatch(clean, name)
            })
            if let idx = matchIdx {
                debugLog("    → hostname match → \(devices[idx].ipAddress)")
                mergeServices(into: idx, newServices: services)
                devices[idx].lastSeen = Date()
                devices[idx].isStale = false
            } else {
                // Resolve the Bonjour name to an IP and match by address
                let cleanName = stripBonjourHexPrefix(name)
                let resolvedName = cleanName.replacingOccurrences(of: " ", with: "-")
                let mDNSName = "\(resolvedName).local"
                debugLog("    No hostname match. Resolving '\(mDNSName)'...")
                let resolvedIP = await resolveNameToIP(mDNSName)
                debugLog("    Resolved to: \(resolvedIP ?? "nil")")

                if let ip = resolvedIP,
                   let idx = devices.firstIndex(where: { $0.ipAddress == ip }) {
                    debugLog("    → IP match → \(ip)")
                    mergeServices(into: idx, newServices: services)
                    devices[idx].lastSeen = Date()
                    devices[idx].isStale = false
                    devices[idx].category = DeviceClassifier.classify(
                        hostname: devices[idx].hostname,
                        services: devices[idx].services,
                        openPorts: devices[idx].openPorts,
                        isGateway: devices[idx].ipAddress == networkInfo.gatewayIP
                    )
                } else {
                    // Bonjour-only device — not found via port scan
                    // Try additional mDNS resolution strategies
                    var bestIP = resolvedIP
                    if bestIP == nil {
                        // Try without parenthesised suffix: "Name (1234)" → "Name"
                        let stripped = cleanName.replacingOccurrences(
                            of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
                        if stripped != cleanName {
                            let altName = stripped.replacingOccurrences(of: " ", with: "-") + ".local"
                            debugLog("    Trying alt: '\(altName)'...")
                            bestIP = await resolveNameToIP(altName)
                            debugLog("    Alt resolved to: \(bestIP ?? "nil")")
                        }
                    }
                    if let ip = bestIP,
                       let idx = devices.firstIndex(where: { $0.ipAddress == ip }) {
                        debugLog("    → alt IP match → \(ip)")
                        mergeServices(into: idx, newServices: services)
                        devices[idx].lastSeen = Date()
                        devices[idx].isStale = false
                    } else {
                        debugLog("    → CREATED bonjour-only device (ip=\(bestIP ?? "unknown"), name=\(cleanName))")
                        var device = NetworkDevice(ipAddress: bestIP ?? "unknown")
                        device.hostname = cleanName
                        device.services = services
                        device.category = DeviceClassifier.classify(
                            hostname: cleanName, services: services, openPorts: [], isGateway: false
                        )
                        devices.append(device)
                    }
                }
            }
        }

        // Deduplicate by IP — multiple Bonjour/scan paths can create entries for the same device
        let preDedup = devices.count
        deduplicateByIP(gatewayIP: networkInfo.gatewayIP)
        debugLog("Dedup: \(preDedup) → \(devices.count) devices")

        // Remove long-stale devices on refresh
        if refresh {
            let cutoff = Date().addingTimeInterval(-60)
            devices.removeAll { $0.isStale && $0.lastSeen < cutoff && !$0.isThisDevice }
        }

        debugLog("=== Final device list ===")
        for d in devices {
            debugLog("  \(d.ipAddress) | host='\(d.hostname ?? "nil")' | svc=\(d.services.count) | name='\(d.displayName)' | cat=\(d.category.rawValue)")
        }

        scanProgress = 1.0
        isScanning = false
        lastScanDate = Date()
        updateStatusText()

        // Background deep probing
        let gatewayIPCopy = networkInfo.gatewayIP
        probeTask = Task {
            await probeDevices(gatewayIP: gatewayIPCopy)
        }
    }

    private func probeDevices(gatewayIP: String) async {
        let devicesToProbe = devices.indices.filter {
            !devices[$0].isThisDevice && !devices[$0].openPorts.isEmpty && !devices[$0].isStale
        }
        guard !devicesToProbe.isEmpty else { return }

        isProbing = true
        let totalToProbe = devicesToProbe.count
        var totalProbed = 0
        scanStatus = "Probing \(totalToProbe) devices..."

        let probeBatchSize = 4
        for batchStart in stride(from: 0, to: devicesToProbe.count, by: probeBatchSize) {
            if Task.isCancelled { return }

            let batchEnd = min(batchStart + probeBatchSize, devicesToProbe.count)
            let batchIndices = Array(devicesToProbe[batchStart..<batchEnd])

            await withTaskGroup(of: (Int, [ProbeEntry]).self) { group in
                for idx in batchIndices {
                    let ip = devices[idx].ipAddress
                    let ports = devices[idx].openPorts
                    group.addTask {
                        let entries = await self.prober.probe(ip: ip, openPorts: ports)
                        return (idx, entries)
                    }
                }

                for await (idx, entries) in group {
                    guard idx < devices.count else { continue }
                    devices[idx].probeResults = entries

                    devices[idx].category = DeviceClassifier.classify(
                        hostname: devices[idx].hostname,
                        services: devices[idx].services,
                        openPorts: devices[idx].openPorts,
                        isGateway: devices[idx].ipAddress == gatewayIP,
                        probeResults: entries
                    )

                    totalProbed += 1
                    scanStatus = "Probed \(totalProbed)/\(totalToProbe) devices..."
                }
            }
        }

        isProbing = false
        updateStatusText()
    }

    private func updateStatusText() {
        let staleCount = devices.filter { $0.isStale }.count
        let activeCount = devices.count - staleCount
        let identifiedCount = devices.filter {
            $0.hostname != nil || !$0.services.isEmpty || !$0.probeResults.isEmpty
        }.count

        if staleCount > 0 {
            scanStatus = "\(activeCount) active · \(staleCount) unresponsive"
        } else if identifiedCount > 0 {
            scanStatus = "\(devices.count) devices · \(identifiedCount) identified"
        } else {
            scanStatus = "Found \(devices.count) devices"
        }
    }

    /// Forward-resolve an mDNS name (e.g. "Pauls-iMac-Pro.local") to an IP address
    private nonisolated func resolveNameToIP(_ name: String) async -> String? {
        await withCheckedContinuation { continuation in
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM

            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(name, nil, &hints, &result)
            defer { if result != nil { freeaddrinfo(result) } }

            guard status == 0, let addr = result else {
                continuation.resume(returning: nil)
                return
            }

            var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if let sockaddr = addr.pointee.ai_addr {
                sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    var sinAddr = sin.pointee.sin_addr
                    inet_ntop(AF_INET, &sinAddr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
                }
                let ip = String(cString: ipBuffer)
                if !ip.isEmpty && ip != "0.0.0.0" {
                    continuation.resume(returning: ip)
                    return
                }
            }
            continuation.resume(returning: nil)
        }
    }

    /// Compare a DNS hostname (e.g. "Pauls-iMac-Pro") with a Bonjour name (e.g. "Paul's iMac Pro")
    /// by normalising both to a common form: lowercase, strip suffixes, collapse whitespace/dashes.
    /// Exposed as internal for testing.
    nonisolated static func namesMatch(_ a: String, _ b: String) -> Bool {
        let na = normaliseName(a)
        let nb = normaliseName(b)
        return na == nb || na.contains(nb) || nb.contains(na)
    }

    nonisolated static func normaliseName(_ s: String) -> String {
        var result = stripBonjourHexPrefix(s).lowercased()
        // Strip domain suffixes
        for suffix in [".local.", ".local", ".lan", ".home.arpa"] {
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
            }
        }
        // Strip parenthesised suffixes like "(920)" or "(4979)"
        result = result.replacingOccurrences(
            of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        // Strip trailing DNS disambiguation numbers like "-7", "-2"
        result = result.replacingOccurrences(
            of: #"-\d+$"#, with: "", options: .regularExpression)
        // Normalise punctuation and whitespace
        return result
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Merge new Bonjour services into an existing device, avoiding duplicates by service type
    private func mergeServices(into idx: Int, newServices: [DiscoveredService]) {
        let existingTypes = Set(devices[idx].services.map(\.type))
        for service in newServices {
            if !existingTypes.contains(service.type) {
                devices[idx].services.append(service)
            }
        }
    }

    /// Merge duplicate devices that share the same real IP address.
    /// Keeps the richer device (more services) as the base and merges the sparser one into it.
    private func deduplicateByIP(gatewayIP: String) {
        var ipIndex: [String: Int] = [:]
        var toRemove: [Int] = []

        for i in devices.indices {
            let ip = devices[i].ipAddress
            // Skip non-real IPs — don't merge unrelated Bonjour-only devices
            guard ip != "unknown" else { continue }
            if let existing = ipIndex[ip] {
                // Pick the richer device as the keeper
                let keepIdx: Int
                let mergeIdx: Int
                if devices[i].services.count > devices[existing].services.count {
                    // The new one is richer — swap: keep new, merge old into it
                    keepIdx = i
                    mergeIdx = existing
                    ipIndex[ip] = i
                    // Move the old index to toRemove (remove previous entry if it was there)
                    toRemove.removeAll { $0 == existing }
                    toRemove.append(existing)
                } else {
                    keepIdx = existing
                    mergeIdx = i
                    toRemove.append(i)
                }

                // Merge services from the sparser device
                mergeServices(into: keepIdx, newServices: devices[mergeIdx].services)
                // Prefer whichever hostname exists
                if devices[keepIdx].hostname == nil {
                    devices[keepIdx].hostname = devices[mergeIdx].hostname
                }
                // Merge open ports
                let keepPorts = Set(devices[keepIdx].openPorts)
                for port in devices[mergeIdx].openPorts where !keepPorts.contains(port) {
                    devices[keepIdx].openPorts.append(port)
                }
                // Merge probe results
                if devices[keepIdx].probeResults.isEmpty && !devices[mergeIdx].probeResults.isEmpty {
                    devices[keepIdx].probeResults = devices[mergeIdx].probeResults
                }
                // Preserve isThisDevice flag
                if devices[mergeIdx].isThisDevice {
                    devices[keepIdx].isThisDevice = true
                }
                // Reclassify with combined info
                devices[keepIdx].category = DeviceClassifier.classify(
                    hostname: devices[keepIdx].hostname,
                    services: devices[keepIdx].services,
                    openPorts: devices[keepIdx].openPorts,
                    isGateway: ip == gatewayIP,
                    probeResults: devices[keepIdx].probeResults
                )
                debugLog("  Dedup: merged \(ip) — kept \(devices[keepIdx].services.count) svc, removed \(devices[mergeIdx].services.count) svc")
            } else {
                ipIndex[ip] = i
            }
        }

        // Remove duplicates in reverse order to preserve indices
        for i in toRemove.reversed() {
            devices.remove(at: i)
        }
    }

    private func getDeviceName() -> String {
        #if targetEnvironment(simulator)
        return "iPhone Simulator"
        #else
        return UIDevice.current.name
        #endif
    }

    var devicesByCategory: [(category: DeviceCategory, devices: [NetworkDevice])] {
        let grouped = Dictionary(grouping: devices) { $0.category }
        return DeviceCategory.allCases.compactMap { category in
            guard let categoryDevices = grouped[category], !categoryDevices.isEmpty else { return nil }
            return (category: category, devices: categoryDevices)
        }
    }

    // Flip to true for diagnostic logging, false for production
    private static let verbose = false

    private func debugLog(_ message: String) {
        if Self.verbose {
            print("[HomeNet] \(message)")
        }
    }
}
