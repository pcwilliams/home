import Foundation
import Network

@MainActor
final class BonjourBrowser: ObservableObject {
    struct BonjourResult: Sendable {
        let serviceType: String
        let name: String
        let hostPort: String?
        let txtRecords: [String: String]
    }

    private var browsers: [NWBrowser] = []
    private var collectedResults: [BonjourResult] = []

    static let serviceTypes: [String] = [
        "_airplay._tcp", "_raop._tcp", "_homekit._tcp", "_hap._tcp",
        "_googlecast._tcp", "_spotify-connect._tcp", "_sonos._tcp",
        "_amzn-wplay._tcp", "_companion-link._tcp", "_http._tcp",
        "_ssh._tcp", "_smb._tcp", "_printer._tcp", "_ipp._tcp",
        "_pdl-datastream._tcp", "_scanner._tcp", "_daap._tcp",
        "_airport._tcp", "_device-info._tcp", "_rfb._tcp",
        "_nvstream._tcp", "_privet._tcp", "_sleep-proxy._udp",
        "_meshcop._udp",
    ]

    /// Common TXT record keys to probe
    nonisolated static let commonTXTKeys = [
        "model", "osvers", "deviceid", "features", "flags",
        "srcvers", "pk", "am", "ty", "product", "pdl",
        "note", "rp", "qtotal", "UUID", "vers", "protovers",
        "fn", "md", "id", "manufacturer", "serialNumber",
        "firmwareRevision", "hardwareRevision",
    ]

    func browse(for seconds: TimeInterval = 8.0) async -> [BonjourResult] {
        stopBrowsing()
        collectedResults = []

        for serviceType in Self.serviceTypes {
            let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: "local.")
            let params = NWParameters()
            params.includePeerToPeer = true

            let browser = NWBrowser(for: descriptor, using: params)
            let capturedType = serviceType

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let parsed: [BonjourResult] = results.compactMap { result in
                    let name: String
                    if case .service(let svcName, _, _, _) = result.endpoint {
                        name = svcName
                    } else {
                        name = result.endpoint.debugDescription
                    }

                    // Extract TXT records from metadata
                    var txtDict: [String: String] = [:]
                    if case .bonjour(let txtRecord) = result.metadata {
                        for key in Self.commonTXTKeys {
                            if let entry = try? txtRecord.getEntry(for: key) {
                                switch entry {
                                case .string(let value):
                                    txtDict[key] = value
                                case .none:
                                    break
                                @unknown default:
                                    break
                                }
                            }
                        }
                    }

                    return BonjourResult(
                        serviceType: capturedType, name: name,
                        hostPort: nil, txtRecords: txtDict
                    )
                }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for bonjourResult in parsed {
                        if let existing = self.collectedResults.firstIndex(where: {
                            $0.serviceType == bonjourResult.serviceType && $0.name == bonjourResult.name
                        }) {
                            if bonjourResult.txtRecords.count > self.collectedResults[existing].txtRecords.count {
                                self.collectedResults[existing] = bonjourResult
                            }
                        } else {
                            self.collectedResults.append(bonjourResult)
                        }
                    }
                }
            }

            browser.stateUpdateHandler = { _ in }

            browser.start(queue: .main)
            browsers.append(browser)
        }

        try? await Task.sleep(for: .seconds(seconds))

        let results = collectedResults
        stopBrowsing()
        return results
    }

    func stopBrowsing() {
        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()
    }
}
