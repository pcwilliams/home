@preconcurrency import Foundation
import Network

struct ProbeEntry: Hashable, Identifiable {
    let id = UUID()
    let source: String
    let label: String
    let value: String

    static func == (lhs: ProbeEntry, rhs: ProbeEntry) -> Bool {
        lhs.source == rhs.source && lhs.label == rhs.label && lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(source)
        hasher.combine(label)
        hasher.combine(value)
    }
}

actor DeviceProber {

    func probe(ip: String, openPorts: [UInt16]) async -> [ProbeEntry] {
        var entries: [ProbeEntry] = []

        // HTTP/HTTPS probing
        let httpPorts: [(UInt16, Bool)] = [
            (80, false), (443, true), (8080, false), (8443, true)
        ]
        await withTaskGroup(of: [ProbeEntry].self) { group in
            for (port, secure) in httpPorts where openPorts.contains(port) {
                group.addTask {
                    await self.probeHTTP(ip: ip, port: port, secure: secure)
                }
            }
            for await result in group {
                entries.append(contentsOf: result)
            }
        }

        // SSH banner
        if openPorts.contains(22) {
            if let banner = await grabBanner(ip: ip, port: 22, label: "SSH") {
                entries.append(ProbeEntry(source: "SSH", label: "Version", value: banner))
            }
        }

        // FTP banner
        if openPorts.contains(21) {
            if let banner = await grabBanner(ip: ip, port: 21, label: "FTP") {
                entries.append(ProbeEntry(source: "FTP", label: "Banner", value: banner))
            }
        }

        // SMTP banner
        if openPorts.contains(25) {
            if let banner = await grabBanner(ip: ip, port: 25, label: "SMTP") {
                entries.append(ProbeEntry(source: "SMTP", label: "Banner", value: banner))
            }
        }

        // RTSP (cameras, media servers)
        if openPorts.contains(554) {
            if let banner = await grabBanner(ip: ip, port: 554, label: "RTSP") {
                entries.append(ProbeEntry(source: "RTSP", label: "Banner", value: banner))
            }
        }

        // AirPlay device info (Apple TVs, HomePods, AirPlay speakers)
        if openPorts.contains(7000) {
            let airplayEntries = await probeAirPlay(ip: ip)
            entries.append(contentsOf: airplayEntries)
        }

        // Chromecast / Google Cast device info
        if openPorts.contains(8008) || openPorts.contains(8443) {
            let castEntries = await probeChromecast(ip: ip)
            entries.append(contentsOf: castEntries)
        }

        // Measure TCP latency to infer wired vs WiFi
        let latency = await measureLatency(ip: ip, openPorts: openPorts)
        if let latency {
            let ms = String(format: "%.1f ms", latency * 1000)
            entries.append(ProbeEntry(source: "Network", label: "Latency", value: ms))
            let connectionType = latency < 0.005 ? "Wired (likely)" :
                                 latency < 0.030 ? "WiFi (likely)" : "Remote / multi-hop"
            entries.append(ProbeEntry(source: "Network", label: "Connection", value: connectionType))
        }

        // UPnP device description
        let upnpPorts: [UInt16] = [80, 8080, 5000, 49152].filter { openPorts.contains($0) }
        if !upnpPorts.isEmpty {
            let upnpEntries = await probeUPnP(ip: ip, ports: upnpPorts)
            entries.append(contentsOf: upnpEntries)
        }

        return entries
    }

    // MARK: - HTTP Probing

    private func probeHTTP(ip: String, port: UInt16, secure: Bool) async -> [ProbeEntry] {
        let scheme = secure ? "https" : "http"
        let portSuffix = (port == 80 && !secure) || (port == 443 && secure) ? "" : ":\(port)"
        guard let url = URL(string: "\(scheme)://\(ip)\(portSuffix)/") else { return [] }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5

        let delegate = InsecureSessionDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var entries: [ProbeEntry] = []
        let source = "\(scheme.uppercased()) :\(port)"

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return [] }

            if let server = httpResponse.value(forHTTPHeaderField: "Server"), !server.isEmpty {
                entries.append(ProbeEntry(source: source, label: "Server", value: server))
            }
            if let poweredBy = httpResponse.value(forHTTPHeaderField: "X-Powered-By"), !poweredBy.isEmpty {
                entries.append(ProbeEntry(source: source, label: "Powered By", value: poweredBy))
            }
            if let auth = httpResponse.value(forHTTPHeaderField: "WWW-Authenticate"), !auth.isEmpty {
                entries.append(ProbeEntry(source: source, label: "Auth", value: auth))
            }
            if let xGenerator = httpResponse.value(forHTTPHeaderField: "X-Generator"), !xGenerator.isEmpty {
                entries.append(ProbeEntry(source: source, label: "Generator", value: xGenerator))
            }

            // Extract info from HTML body
            let bodyLimit = min(data.count, 8192)
            if let html = String(data: data.prefix(bodyLimit), encoding: .utf8)
                ?? String(data: data.prefix(bodyLimit), encoding: .ascii)
            {
                if let title = extractHTMLTitle(from: html), !title.isEmpty {
                    entries.append(ProbeEntry(source: source, label: "Page Title", value: title))
                }
                if let generator = extractMeta(name: "generator", from: html) {
                    entries.append(ProbeEntry(source: source, label: "Generator", value: generator))
                }
                if let description = extractMeta(name: "description", from: html), description.count <= 120 {
                    entries.append(ProbeEntry(source: source, label: "Description", value: description))
                }
            }

            // Status code (only if interesting — not 200)
            if httpResponse.statusCode != 200 {
                entries.append(ProbeEntry(source: source, label: "Status", value: "\(httpResponse.statusCode)"))
            }
        } catch {
            // Connection refused, timeout — no info to gather
        }

        return entries
    }

    // MARK: - Banner Grabbing (SSH, FTP, SMTP, RTSP, etc.)

    private func grabBanner(ip: String, port: UInt16, label: String) async -> String? {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(ip),
                port: NWEndpoint.Port(rawValue: port)!
            )
            let params = NWParameters.tcp
            params.requiredInterfaceType = .wifi
            let connection = NWConnection(to: endpoint, using: params)
            let gate = ContinuationGate()

            let timeoutWork = DispatchWorkItem { [gate] in
                if gate.tryResume() {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeoutWork)

            connection.stateUpdateHandler = { [gate] state in
                switch state {
                case .ready:
                    // Many services send a banner immediately on connect
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                        timeoutWork.cancel()
                        if gate.tryResume() {
                            let banner = data.flatMap { d in
                                String(data: d, encoding: .utf8)?
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .components(separatedBy: "\r\n").first?
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            connection.cancel()
                            continuation.resume(returning: banner?.isEmpty == true ? nil : banner)
                        }
                    }
                case .failed, .cancelled:
                    timeoutWork.cancel()
                    if gate.tryResume() {
                        continuation.resume(returning: nil)
                    }
                case .waiting:
                    timeoutWork.cancel()
                    if gate.tryResume() {
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: DispatchQueue.global(qos: .utility))
        }
    }

    // MARK: - UPnP Device Description

    private func probeUPnP(ip: String, ports: [UInt16]) async -> [ProbeEntry] {
        let paths = [
            "/description.xml",
            "/rootDesc.xml",
            "/DeviceDescription.xml",
            "/upnp/IGD.xml",
            "/upnp.xml",
            "/dmr/DeviceDescription.xml",
        ]

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        for port in ports {
            for path in paths {
                let portSuffix = port == 80 ? "" : ":\(port)"
                guard let url = URL(string: "http://\(ip)\(portSuffix)\(path)") else { continue }

                do {
                    let (data, response) = try await session.data(from: url)
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else { continue }
                    guard let xml = String(data: data, encoding: .utf8) else { continue }
                    guard xml.contains("<device>") || xml.contains("<Device>")
                        || xml.contains("deviceType") else { continue }

                    var entries: [ProbeEntry] = []
                    let source = "UPnP"

                    if let name = extractXMLElement("friendlyName", from: xml) {
                        entries.append(ProbeEntry(source: source, label: "Name", value: name))
                    }
                    if let mfg = extractXMLElement("manufacturer", from: xml) {
                        entries.append(ProbeEntry(source: source, label: "Manufacturer", value: mfg))
                    }
                    if let model = extractXMLElement("modelName", from: xml) {
                        entries.append(ProbeEntry(source: source, label: "Model", value: model))
                    }
                    if let desc = extractXMLElement("modelDescription", from: xml) {
                        entries.append(ProbeEntry(source: source, label: "Description", value: desc))
                    }
                    if let num = extractXMLElement("modelNumber", from: xml) {
                        entries.append(ProbeEntry(source: source, label: "Model Number", value: num))
                    }
                    if let serial = extractXMLElement("serialNumber", from: xml) {
                        entries.append(ProbeEntry(source: source, label: "Serial", value: serial))
                    }
                    if let firmware = extractXMLElement("firmwareVersion", from: xml) {
                        entries.append(ProbeEntry(source: source, label: "Firmware", value: firmware))
                    }
                    if let deviceType = extractXMLElement("deviceType", from: xml) {
                        // e.g. "urn:schemas-upnp-org:device:MediaRenderer:1"
                        let shortType = deviceType
                            .replacingOccurrences(of: "urn:schemas-upnp-org:device:", with: "")
                            .replacingOccurrences(of: "urn:schemas-upnp-org:service:", with: "")
                        entries.append(ProbeEntry(source: source, label: "Device Type", value: shortType))
                    }

                    if !entries.isEmpty { return entries }
                } catch {
                    continue
                }
            }
        }
        return []
    }

    // MARK: - AirPlay Device Info

    private func probeAirPlay(ip: String) async -> [ProbeEntry] {
        guard let url = URL(string: "http://\(ip):7000/info") else { return [] }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }

            var entries: [ProbeEntry] = []
            let source = "AirPlay"

            // AirPlay /info returns a binary plist or XML plist
            if let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any]
            {
                if let model = plist["model"] as? String {
                    entries.append(ProbeEntry(source: source, label: "Model", value: model))
                    if let friendly = Self.appleModelName(model) {
                        entries.append(ProbeEntry(source: source, label: "Device", value: friendly))
                    }
                }
                if let name = plist["name"] as? String {
                    entries.append(ProbeEntry(source: source, label: "Name", value: name))
                }
                if let deviceID = plist["deviceid"] as? String {
                    entries.append(ProbeEntry(source: source, label: "Device ID", value: deviceID))
                }
                if let srcvers = plist["srcvers"] as? String {
                    entries.append(ProbeEntry(source: source, label: "AirPlay Version", value: srcvers))
                }
                if let osvers = plist["osBuildVersion"] as? String {
                    entries.append(ProbeEntry(source: source, label: "OS Build", value: osvers))
                }
                if let macAddress = plist["macAddress"] as? String {
                    entries.append(ProbeEntry(source: source, label: "MAC Address", value: macAddress))
                }
            }

            return entries
        } catch {
            return []
        }
    }

    // MARK: - Chromecast / Google Cast Info

    private func probeChromecast(ip: String) async -> [ProbeEntry] {
        guard let url = URL(string: "http://\(ip):8008/setup/eureka_info?params=version,name,build_info,detail,device_info,net,wifi,setup,settings,opt_in&options=detail") else { return [] }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

            var entries: [ProbeEntry] = []
            let source = "Cast"

            if let name = json["name"] as? String {
                entries.append(ProbeEntry(source: source, label: "Name", value: name))
            }
            if let detail = json["detail"] as? [String: Any] {
                if let model = detail["model_name"] as? String {
                    entries.append(ProbeEntry(source: source, label: "Model", value: model))
                }
                if let manufacturer = detail["manufacturer"] as? String {
                    entries.append(ProbeEntry(source: source, label: "Manufacturer", value: manufacturer))
                }
            }
            if let version = json["version"] as? Int {
                entries.append(ProbeEntry(source: source, label: "Cast Version", value: "\(version)"))
            }
            if let buildInfo = json["build_info"] as? [String: Any] {
                if let castBuild = buildInfo["cast_build_revision"] as? String {
                    entries.append(ProbeEntry(source: source, label: "Firmware", value: castBuild))
                }
            }
            if let net = json["net"] as? [String: Any] {
                if let ethernet = net["ethernet_connected"] as? Bool {
                    entries.append(ProbeEntry(source: source, label: "Ethernet", value: ethernet ? "Connected" : "Not connected"))
                }
            }
            if let wifi = json["wifi"] as? [String: Any] {
                if let ssid = wifi["ssid"] as? String {
                    entries.append(ProbeEntry(source: source, label: "WiFi Network", value: ssid))
                }
                if let bssid = wifi["bssid"] as? String {
                    entries.append(ProbeEntry(source: source, label: "WiFi BSSID", value: bssid))
                }
                if let signal = wifi["signal_level"] as? Double {
                    entries.append(ProbeEntry(source: source, label: "WiFi Signal", value: "\(Int(signal)) dBm"))
                }
                if let noise = wifi["noise_level"] as? Double {
                    entries.append(ProbeEntry(source: source, label: "WiFi Noise", value: "\(Int(noise)) dBm"))
                }
            }

            return entries
        } catch {
            return []
        }
    }

    // MARK: - Latency Measurement

    private func measureLatency(ip: String, openPorts: [UInt16]) async -> TimeInterval? {
        // Pick the first open port for the measurement
        guard let port = openPorts.first else { return nil }

        let start = ContinuousClock.now

        let connected: Bool = await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(ip),
                port: NWEndpoint.Port(rawValue: port)!
            )
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
            DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeoutWork)

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

        guard connected else { return nil }
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.attoseconds) / 1e18
    }

    // MARK: - Apple Model ID Lookup

    private static func appleModelName(_ identifier: String) -> String? {
        let models: [String: String] = [
            "AppleTV3,1": "Apple TV (3rd gen)", "AppleTV3,2": "Apple TV (3rd gen Rev A)",
            "AppleTV5,3": "Apple TV HD", "AppleTV6,2": "Apple TV 4K (1st gen)",
            "AppleTV11,1": "Apple TV 4K (2nd gen)", "AppleTV14,1": "Apple TV 4K (3rd gen)",
            "AudioAccessory1,1": "HomePod", "AudioAccessory1,2": "HomePod",
            "AudioAccessory5,1": "HomePod mini", "AudioAccessory6,1": "HomePod (2nd gen)",
            "AirPort10,1": "AirPort Express (2nd gen)",
        ]
        return models[identifier]
    }

    // MARK: - HTML/XML Parsing Helpers

    private func extractHTMLTitle(from html: String) -> String? {
        guard let startRange = html.range(of: "<title", options: .caseInsensitive),
              let closeRange = html.range(of: ">", range: startRange.upperBound..<html.endIndex),
              let endRange = html.range(of: "</title>", options: .caseInsensitive,
                                        range: closeRange.upperBound..<html.endIndex) else {
            return nil
        }
        let title = String(html[closeRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : String(title.prefix(200))
    }

    private func extractMeta(name: String, from html: String) -> String? {
        let patterns = [
            "name=\"\(name)\"[^>]*content=\"([^\"]+)\"",
            "content=\"([^\"]+)\"[^>]*name=\"\(name)\"",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html)
            {
                let value = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private func extractXMLElement(_ element: String, from xml: String) -> String? {
        let pattern = "<\(element)>([^<]+)</\(element)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        let value = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - HTTPS Certificate Bypass (local devices use self-signed certs)

private final class InsecureSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust
        {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}

