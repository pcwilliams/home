import SwiftUI

struct DeviceDetailView: View {
    let device: NetworkDevice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    deviceHeader
                    networkInfoSection
                    if !device.probeResults.isEmpty { probeResultsSection }
                    if !device.services.isEmpty { servicesSection }
                    if !device.openPorts.isEmpty { portsSection }
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Device Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var deviceHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [categoryColor.opacity(0.4), categoryColor.opacity(0.1)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)

                Circle()
                    .stroke(categoryColor.opacity(0.6), lineWidth: 2)
                    .frame(width: 100, height: 100)

                Image(systemName: DeviceClassifier.refinedIcon(for: device))
                    .font(.system(size: 36))
                    .foregroundStyle(categoryColor)
            }

            Text(device.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                Label(device.category.rawValue, systemImage: device.category.icon)
                    .font(.caption)
                    .foregroundStyle(categoryColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(categoryColor.opacity(0.15)))

                if device.isThisDevice {
                    Label("This Device", systemImage: "iphone")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.cyan.opacity(0.15)))
                }
            }
        }
    }

    private var networkInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Network", icon: "network")

            InfoRow(label: "IP Address", value: device.ipAddress)

            if let hostname = device.hostname {
                InfoRow(label: "Hostname", value: hostname)
            }

            InfoRow(label: "First Seen", value: device.firstSeen.formatted(date: .abbreviated, time: .shortened))
            InfoRow(label: "Last Seen", value: device.lastSeen.formatted(date: .abbreviated, time: .shortened))
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private var probeResultsSection: some View {
        let grouped = Dictionary(grouping: device.probeResults) { $0.source }
        let sources = grouped.keys.sorted()

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Discovered Info (\(device.probeResults.count))", icon: "magnifyingglass")

            ForEach(sources, id: \.self) { source in
                if let entries = grouped[source] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(source)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(categoryColor.opacity(0.8))
                            .padding(.top, 4)

                        ForEach(entries) { entry in
                            HStack(alignment: .top) {
                                Text(entry.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 80, alignment: .leading)
                                Spacer()
                                Text(entry.value)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.trailing)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if source != sources.last {
                        Divider().background(Color.white.opacity(0.1))
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Services (\(device.services.count))", icon: "server.rack")

            ForEach(device.services) { service in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(categoryColor)
                            .frame(width: 6, height: 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(serviceFriendlyName(service.type))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                            Text(service.type)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let port = service.port {
                            Text(":\(port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !service.txtRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(service.txtRecords.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack(alignment: .top) {
                                    Text(key)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 60, alignment: .leading)
                                    Text(value)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.leading, 14)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Open Ports (\(device.openPorts.count))", icon: "door.left.hand.open")

            FlowLayout(spacing: 8) {
                ForEach(device.openPorts, id: \.self) { port in
                    VStack(spacing: 2) {
                        Text("\(port)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(portDescription(port))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(categoryColor)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    private var categoryColor: Color {
        device.category.swiftUIColor
    }

    private func serviceFriendlyName(_ type: String) -> String {
        let names: [String: String] = [
            "_airplay._tcp": "AirPlay",
            "_raop._tcp": "AirPlay Audio",
            "_homekit._tcp": "HomeKit",
            "_hap._tcp": "HomeKit Accessory",
            "_googlecast._tcp": "Google Cast",
            "_spotify-connect._tcp": "Spotify Connect",
            "_sonos._tcp": "Sonos",
            "_amzn-wplay._tcp": "Amazon Echo",
            "_companion-link._tcp": "Apple Companion Link",
            "_http._tcp": "Web Server",
            "_ssh._tcp": "SSH",
            "_smb._tcp": "File Sharing (SMB)",
            "_printer._tcp": "Printer",
            "_ipp._tcp": "Internet Printing",
            "_pdl-datastream._tcp": "Printer Data Stream",
            "_scanner._tcp": "Network Scanner",
            "_daap._tcp": "Music Sharing (DAAP)",
            "_airport._tcp": "AirPort Base Station",
            "_device-info._tcp": "Device Info",
            "_rfb._tcp": "Screen Sharing (VNC)",
            "_nvstream._tcp": "NVIDIA GameStream",
            "_privet._tcp": "Google Cloud Print",
            "_sleep-proxy._udp": "Sleep Proxy",
            "_meshcop._udp": "Thread/Matter",
        ]
        return names[type] ?? type
    }

    private func portDescription(_ port: UInt16) -> String {
        switch port {
        case 22: return "SSH"
        case 53: return "DNS"
        case 80: return "HTTP"
        case 443: return "HTTPS"
        case 445: return "SMB"
        case 548: return "AFP"
        case 554: return "RTSP"
        case 631: return "IPP"
        case 3000: return "Dev Server"
        case 3689: return "DAAP"
        case 5000: return "UPnP"
        case 5353: return "mDNS"
        case 7000: return "AirPlay"
        case 7100: return "AirPlay"
        case 8080: return "HTTP Alt"
        case 8443: return "HTTPS Alt"
        case 8888: return "HTTP Proxy"
        case 9090: return "Web Admin"
        case 49152: return "Dynamic"
        case 62078: return "iDevice"
        default: return "Port"
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                   proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
