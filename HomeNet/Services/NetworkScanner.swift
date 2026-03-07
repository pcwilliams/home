import Foundation
import Network

actor NetworkScanner {
    struct NetworkInfo: Sendable {
        let localIP: String
        let gatewayIP: String
        let subnetMask: String
        let baseAddress: UInt32
        let broadcastAddress: UInt32
    }

    func getNetworkInfo() -> NetworkInfo? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var localIP: String?
        var subnetMask: String?

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = current {
            let name = String(cString: addr.pointee.ifa_name)
            let family = addr.pointee.ifa_addr.pointee.sa_family

            if name == "en0" && family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr.pointee.ifa_addr, socklen_t(MemoryLayout<sockaddr_in>.size),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    localIP = String(cString: hostname)
                }

                var maskname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr.pointee.ifa_netmask, socklen_t(MemoryLayout<sockaddr_in>.size),
                               &maskname, socklen_t(maskname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    subnetMask = String(cString: maskname)
                }
            }
            current = addr.pointee.ifa_next
        }

        guard let ip = localIP, let mask = subnetMask else { return nil }

        let ipParts = ip.split(separator: ".").compactMap { UInt32($0) }
        let maskParts = mask.split(separator: ".").compactMap { UInt32($0) }
        guard ipParts.count == 4, maskParts.count == 4 else { return nil }

        let ipNum = (ipParts[0] << 24) | (ipParts[1] << 16) | (ipParts[2] << 8) | ipParts[3]
        let maskNum = (maskParts[0] << 24) | (maskParts[1] << 16) | (maskParts[2] << 8) | maskParts[3]

        let networkAddr = ipNum & maskNum
        let broadcastAddr = networkAddr | ~maskNum
        let gatewayAddr = networkAddr + 1

        let gatewayIP = "\(gatewayAddr >> 24 & 0xFF).\(gatewayAddr >> 16 & 0xFF).\(gatewayAddr >> 8 & 0xFF).\(gatewayAddr & 0xFF)"

        return NetworkInfo(
            localIP: ip,
            gatewayIP: gatewayIP,
            subnetMask: mask,
            baseAddress: networkAddr + 1,
            broadcastAddress: broadcastAddr
        )
    }

    /// Streams discovered IPs one at a time as each host responds.
    func scanSubnetStream(networkInfo: NetworkInfo) -> AsyncStream<String> {
        let totalHosts = networkInfo.broadcastAddress - networkInfo.baseAddress
        let maxHosts = min(totalHosts, 254)

        let allIPs: [String] = (UInt32(0)..<maxHosts).compactMap { offset in
            let ip = networkInfo.baseAddress + offset
            let ipString = "\(ip >> 24 & 0xFF).\(ip >> 16 & 0xFF).\(ip >> 8 & 0xFF).\(ip & 0xFF)"
            return ipString == networkInfo.localIP ? nil : ipString
        }

        let batchSize = 25

        return AsyncStream { continuation in
            Task {
                for batchStart in stride(from: 0, to: allIPs.count, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, allIPs.count)
                    let batch = Array(allIPs[batchStart..<batchEnd])

                    await withTaskGroup(of: Void.self) { group in
                        for ip in batch {
                            group.addTask {
                                let reachable = await self.probeHost(ip)
                                if reachable {
                                    continuation.yield(ip)
                                }
                            }
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    private func probeHost(_ ip: String) async -> Bool {
        let ports: [UInt16] = [80, 443, 22, 548, 445, 62078, 8080, 5000, 7000, 8443, 53, 5353, 631, 9090, 554]

        return await withTaskGroup(of: Bool.self) { group in
            for port in ports {
                group.addTask {
                    await self.checkPort(host: ip, port: port, timeout: 1.5)
                }
            }

            for await result in group {
                if result {
                    group.cancelAll()
                    return true
                }
            }
            return false
        }
    }

    private func checkPort(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
            let params = NWParameters.tcp
            params.requiredInterfaceType = .wifi
            let connection = NWConnection(to: endpoint, using: params)
            let gate = ContinuationGate()

            let timeoutWork = DispatchWorkItem { [gate] in
                if gate.tryResume() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            connection.stateUpdateHandler = { [gate] state in
                switch state {
                case .ready:
                    timeoutWork.cancel()
                    if gate.tryResume() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    timeoutWork.cancel()
                    if gate.tryResume() {
                        continuation.resume(returning: false)
                    }
                case .waiting:
                    timeoutWork.cancel()
                    if gate.tryResume() {
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            connection.start(queue: DispatchQueue.global(qos: .utility))
        }
    }

    func resolveHostname(for ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            let parts = ip.split(separator: ".").compactMap { UInt8($0) }
            guard parts.count == 4 else {
                continuation.resume(returning: nil)
                return
            }

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_addr.s_addr = UInt32(parts[0]) | (UInt32(parts[1]) << 8) | (UInt32(parts[2]) << 16) | (UInt32(parts[3]) << 24)

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    getnameinfo(sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size),
                                &hostname, socklen_t(hostname.count), nil, 0, 0)
                }
            }

            if result == 0 {
                let name = String(cString: hostname)
                if name != ip {
                    continuation.resume(returning: name)
                    return
                }
            }
            continuation.resume(returning: nil)
        }
    }

    func identifyOpenPorts(_ ip: String) async -> [UInt16] {
        let commonPorts: [UInt16] = [
            22, 53, 80, 443, 445, 548, 554, 631, 3000, 3689,
            5000, 5353, 7000, 7100, 8080, 8443, 8888, 9090,
            49152, 62078
        ]

        return await withTaskGroup(of: (UInt16, Bool).self) { group in
            for port in commonPorts {
                group.addTask {
                    let open = await self.checkPort(host: ip, port: port, timeout: 2.0)
                    return (port, open)
                }
            }

            var openPorts: [UInt16] = []
            for await (port, isOpen) in group {
                if isOpen {
                    openPorts.append(port)
                }
            }
            return openPorts.sorted()
        }
    }
}

/// Thread-safe gate that ensures a continuation is resumed exactly once.
/// Used by NWConnection handlers where multiple state callbacks can fire.
final class ContinuationGate: @unchecked Sendable {
    private var _resumed = false
    private let lock = NSLock()

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _resumed { return false }
        _resumed = true
        return true
    }
}

