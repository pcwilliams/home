import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: NetworkViewModel
    @Binding var selectedDevice: NetworkDevice?

    var body: some View {
        ScrollView {
            if viewModel.isScanning {
                ProgressView(value: viewModel.scanProgress) {
                    Text(viewModel.scanStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(.cyan)
                .padding()
            }

            LazyVStack(spacing: 12) {
                ForEach(viewModel.devicesByCategory, id: \.category) { group in
                    Section {
                        ForEach(group.devices) { device in
                            DeviceRow(device: device)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedDevice = device }
                        }
                    } header: {
                        HStack {
                            Image(systemName: group.category.icon)
                                .foregroundStyle(group.category.swiftUIColor)
                            Text(group.category.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(group.devices.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.bottom)
        }
    }

}

struct DeviceRow: View {
    let device: NetworkDevice

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(nodeColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: DeviceClassifier.refinedIcon(for: device))
                    .font(.system(size: 18))
                    .foregroundStyle(nodeColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(device.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(device.isStale ? .white.opacity(0.4) : .white)

                    if device.isThisDevice {
                        Text("This device")
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.cyan.opacity(0.15)))
                    }

                    if device.isStale {
                        Text("Stale")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.orange.opacity(0.15)))
                    }
                }

                HStack(spacing: 8) {
                    Text(device.subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !device.services.isEmpty {
                        Text("\(device.services.count) services")
                            .font(.caption2)
                            .foregroundStyle(nodeColor.opacity(0.8))
                    }

                    if !device.openPorts.isEmpty {
                        Text("\(device.openPorts.count) ports")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal)
    }

    private var nodeColor: Color {
        device.isStale ? .gray : device.category.swiftUIColor
    }
}
