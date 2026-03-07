import Foundation

struct DeviceClassifier {
    static func classify(hostname: String?, services: [DiscoveredService], openPorts: [UInt16], isGateway: Bool, probeResults: [ProbeEntry] = []) -> DeviceCategory {
        if isGateway { return .router }

        let serviceTypes = Set(services.map { $0.type })
        let nameLC = (hostname ?? "").lowercased()

        // Collect all TXT records across services for model-based classification
        let allTXT = services.reduce(into: [String: String]()) { dict, svc in
            for (k, v) in svc.txtRecords { dict[k] = v }
        }

        // Apple model identifier from TXT records (e.g. "MacBookPro18,1", "AppleTV6,2")
        if let modelID = allTXT["model"] ?? allTXT["am"] {
            if let category = classifyByAppleModelID(modelID) {
                return category
            }
        }

        if serviceTypes.contains("_printer._tcp") || serviceTypes.contains("_ipp._tcp")
            || serviceTypes.contains("_pdl-datastream._tcp") || serviceTypes.contains("_scanner._tcp") {
            return .printer
        }

        if serviceTypes.contains("_googlecast._tcp") || serviceTypes.contains("_nvstream._tcp") {
            return .tv
        }

        if serviceTypes.contains("_airplay._tcp") {
            if nameLC.contains("apple tv") || nameLC.contains("appletv") || nameLC.contains("tv") {
                return .tv
            }
            if nameLC.contains("homepod") || nameLC.contains("sonos") {
                return .speaker
            }
            return .tv
        }

        if serviceTypes.contains("_sonos._tcp") || serviceTypes.contains("_spotify-connect._tcp")
            || serviceTypes.contains("_raop._tcp") {
            if nameLC.contains("homepod") { return .speaker }
            if nameLC.contains("tv") || nameLC.contains("appletv") { return .tv }
            return .speaker
        }

        if serviceTypes.contains("_amzn-wplay._tcp") {
            if nameLC.contains("echo") || nameLC.contains("dot") || nameLC.contains("alexa") {
                return .speaker
            }
            if nameLC.contains("fire") || nameLC.contains("stick") { return .tv }
            return .speaker
        }

        if serviceTypes.contains("_homekit._tcp") || serviceTypes.contains("_hap._tcp")
            || serviceTypes.contains("_meshcop._udp") {
            return .smarthome
        }

        if serviceTypes.contains("_companion-link._tcp") || serviceTypes.contains("_device-info._tcp") {
            if nameLC.contains("iphone") || nameLC.contains("ipad") {
                return nameLC.contains("ipad") ? .apple : .phone
            }
            if nameLC.contains("macbook") || nameLC.contains("imac") || nameLC.contains("mac") {
                return .computer
            }
            return .apple
        }

        if serviceTypes.contains("_rfb._tcp") || serviceTypes.contains("_ssh._tcp") {
            return .computer
        }

        if serviceTypes.contains("_smb._tcp") || serviceTypes.contains("_airport._tcp") {
            if nameLC.contains("nas") || nameLC.contains("synology") || nameLC.contains("qnap")
                || nameLC.contains("diskstation") {
                return .storage
            }
            return .computer
        }

        if serviceTypes.contains("_daap._tcp") {
            return .computer
        }

        // Try probe results (UPnP manufacturer/model, HTTP headers, SSH banners)
        if !probeResults.isEmpty {
            if let category = classifyByProbeResults(probeResults) {
                return category
            }
        }

        if let hostname = hostname {
            return classifyByHostname(hostname, openPorts: openPorts)
        }

        return classifyByPorts(openPorts)
    }

    private static func classifyByHostname(_ hostname: String, openPorts: [UInt16]) -> DeviceCategory {
        let name = hostname.lowercased()

        if name.contains("iphone") { return .phone }
        if name.contains("ipad") { return .apple }
        if name.contains("macbook") || name.contains("imac") || name.contains("mac-") || name.contains("mac.") {
            return .computer
        }
        if name.contains("apple") || name.contains("homepod") { return .speaker }

        if name.contains("android") || name.contains("galaxy") || name.contains("pixel")
            || name.contains("oneplus") || name.contains("huawei") || name.contains("xiaomi") {
            return .phone
        }

        if name.contains("chromecast") || name.contains("roku") || name.contains("firestick")
            || name.contains("fire-tv") || name.contains("shield") || name.contains("appletv") {
            return .tv
        }

        if name.contains("echo") || name.contains("alexa") || name.contains("dot-")
            || name.contains("sonos") || name.contains("heos") || name.contains("bose") {
            return .speaker
        }

        if name.contains("printer") || name.contains("epson") || name.contains("canon")
            || name.contains("brother") || name.contains("hp-") || name.contains("laserjet")
            || name.contains("deskjet") || name.contains("officejet") {
            return .printer
        }

        if name.contains("hue") || name.contains("nest") || name.contains("ring")
            || name.contains("wemo") || name.contains("tplink") || name.contains("smartthings")
            || name.contains("ikea") || name.contains("tradfri") || name.contains("meross")
            || name.contains("tuya") || name.contains("shelly") {
            return .smarthome
        }

        if name.contains("playstation") || name.contains("xbox") || name.contains("nintendo")
            || name.contains("switch") || name.contains("ps5") || name.contains("ps4") {
            return .gaming
        }

        if name.contains("nas") || name.contains("synology") || name.contains("qnap")
            || name.contains("diskstation") || name.contains("freenas") || name.contains("truenas") {
            return .storage
        }

        if name.contains("pc") || name.contains("desktop") || name.contains("laptop")
            || name.contains("windows") || name.contains("dell") || name.contains("lenovo")
            || name.contains("thinkpad") || name.contains("surface") {
            return .computer
        }

        return classifyByPorts(openPorts)
    }

    /// Classify based on Apple model identifier from Bonjour TXT records
    static func classifyByAppleModelID(_ modelID: String) -> DeviceCategory? {
        let id = modelID.lowercased()
        if id.hasPrefix("macbookpro") || id.hasPrefix("macbookair") || id.hasPrefix("macbook")
            || id.hasPrefix("imac") || id.hasPrefix("macpro") || id.hasPrefix("macmini")
            || id.hasPrefix("mac") {
            return .computer
        }
        if id.hasPrefix("appletv") { return .tv }
        if id.hasPrefix("homepod") || id.hasPrefix("audioaccessory") { return .speaker }
        if id.hasPrefix("iphone") { return .phone }
        if id.hasPrefix("ipad") { return .apple }
        if id.hasPrefix("watch") || id.hasPrefix("applewatch") { return .apple }
        if id.hasPrefix("airpods") || id.hasPrefix("ipod") { return .apple }
        if id.hasPrefix("airport") { return .router }
        return nil
    }

    private static func classifyByProbeResults(_ results: [ProbeEntry]) -> DeviceCategory? {
        // Combine all probe text for keyword matching
        let allText = results.map { "\($0.label) \($0.value)" }.joined(separator: " ").lowercased()

        // UPnP device types are very reliable
        if let deviceType = results.first(where: { $0.source == "UPnP" && $0.label == "Device Type" })?.value.lowercased() {
            if deviceType.contains("mediarenderer") || deviceType.contains("mediaserver") { return .tv }
            if deviceType.contains("printer") { return .printer }
            if deviceType.contains("internetgateway") || deviceType.contains("wandevice") { return .router }
            if deviceType.contains("light") || deviceType.contains("switch") || deviceType.contains("sensor") { return .smarthome }
        }

        // Manufacturer-based classification
        if allText.contains("sonos") { return .speaker }
        if allText.contains("philips hue") || allText.contains("signify") { return .smarthome }
        if allText.contains("belkin") || allText.contains("wemo") { return .smarthome }
        if allText.contains("roku") { return .tv }
        if allText.contains("samsung tv") || allText.contains("lg webos") || allText.contains("vizio") { return .tv }
        if allText.contains("synology") || allText.contains("qnap") || allText.contains("buffalo") { return .storage }
        if allText.contains("epson") || allText.contains("canon") || allText.contains("brother")
            || allText.contains("hp ") || allText.contains("laserjet") || allText.contains("deskjet") { return .printer }
        if allText.contains("nest") || allText.contains("ring") || allText.contains("ecobee") { return .smarthome }
        if allText.contains("playstation") || allText.contains("xbox") || allText.contains("nintendo") { return .gaming }

        // SSH version can reveal OS
        if let ssh = results.first(where: { $0.source == "SSH" })?.value.lowercased() {
            if ssh.contains("dropbear") { return .smarthome } // Common on embedded/IoT
        }

        // HTTP Server header
        if let server = results.first(where: { $0.label == "Server" })?.value.lowercased() {
            if server.contains("webos") { return .tv }
            if server.contains("kodi") || server.contains("plex") || server.contains("emby") || server.contains("jellyfin") { return .tv }
            if server.contains("home assistant") || server.contains("homeassistant") { return .smarthome }
        }

        // Page title clues
        if let title = results.first(where: { $0.label == "Page Title" })?.value.lowercased() {
            if title.contains("printer") || title.contains("print") { return .printer }
            if title.contains("router") || title.contains("gateway") || title.contains("modem") { return .router }
            if title.contains("nas") || title.contains("storage") || title.contains("diskstation") { return .storage }
            if title.contains("camera") || title.contains("webcam") || title.contains("surveillance") { return .smarthome }
        }

        return nil
    }

    private static func classifyByPorts(_ ports: [UInt16]) -> DeviceCategory {
        let portSet = Set(ports)

        if portSet.contains(631) || portSet.contains(9100) { return .printer }
        if portSet.contains(62078) { return .phone }
        if portSet.contains(22) || portSet.contains(548) { return .computer }
        if portSet.contains(7000) || portSet.contains(7100) { return .tv }
        if portSet.contains(445) || portSet.contains(5000) { return .storage }

        return .unknown
    }

    static func refinedIcon(for device: NetworkDevice) -> String {
        let name = (device.hostname ?? "").lowercased()

        // Check TXT record model ID for precise Apple device icons
        let allTXT = device.services.reduce(into: [String: String]()) { dict, svc in
            for (k, v) in svc.txtRecords { dict[k] = v }
        }
        let modelID = (allTXT["model"] ?? allTXT["am"] ?? "").lowercased()

        switch device.category {
        case .computer:
            if modelID.hasPrefix("macbookpro") || modelID.hasPrefix("macbookair") || modelID.hasPrefix("macbook")
                || name.contains("macbook") || name.contains("laptop") || name.contains("thinkpad") {
                return "laptopcomputer"
            }
            if modelID.hasPrefix("imac") || name.contains("imac") || name.contains("desktop") {
                return "desktopcomputer"
            }
            if modelID.hasPrefix("macmini") { return "macmini" }
            if modelID.hasPrefix("macpro") { return "macpro.gen3" }
            if name.contains("mac") || modelID.hasPrefix("mac") { return "desktopcomputer" }
            return "laptopcomputer"
        case .phone:
            if modelID.hasPrefix("iphone") || name.contains("iphone") { return "iphone" }
            if modelID.hasPrefix("ipad") || name.contains("ipad") { return "ipad" }
            return "smartphone"
        case .apple:
            if modelID.hasPrefix("ipad") || name.contains("ipad") { return "ipad" }
            if modelID.hasPrefix("watch") || name.contains("watch") { return "applewatch" }
            if modelID.hasPrefix("airpods") { return "airpods" }
            return "apple.logo"
        case .speaker:
            if modelID.hasPrefix("audioaccessory") || name.contains("homepod") { return "homepodmini" }
            return "hifispeaker"
        case .tv:
            if modelID.hasPrefix("appletv") || name.contains("appletv") || name.contains("apple tv") || name.contains("apple-tv") { return "appletv" }
            return "tv"
        default:
            return device.category.icon
        }
    }
}
