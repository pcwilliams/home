import SwiftUI

struct NetworkMapView: View {
    @ObservedObject var viewModel: NetworkViewModel
    @Binding var selectedDevice: NetworkDevice?
    @State private var animationPhase: Double = 0

    // Zoom & pan state
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radiusX = geo.size.width * 0.42
            let radiusY = geo.size.height * 0.42
            let positions = computePositions(center: center, radiusX: radiusX, radiusY: radiusY)

            ZStack {
                gridBackground(size: geo.size)

                // Transformable content
                ZStack {
                    if viewModel.isScanning {
                        scanPulse(center: center, radiusX: radiusX, radiusY: radiusY)
                    }

                    connectionLines(center: center, positions: positions)

                    if let router = viewModel.devices.first(where: { $0.isGateway }) {
                        DeviceNode(device: router)
                            .position(center)
                            .onTapGesture { selectedDevice = router }
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }

                    ForEach(Array(positions.keys.sorted(by: { $0.uuidString < $1.uuidString })), id: \.self) { deviceID in
                        if let position = positions[deviceID],
                           let device = nonRouterDevices.first(where: { $0.id == deviceID }) {
                            DeviceNode(device: device)
                                .position(position)
                                .onTapGesture { selectedDevice = device }
                                .transition(.scale(scale: 0.2).combined(with: .opacity))
                        }
                    }
                }
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: nonRouterDevices.map(\.id))
                .scaleEffect(currentScale)
                .offset(currentOffset)
            }
            .overlay(alignment: .bottom) {
                statusBar
            }
            .overlay(alignment: .topTrailing) {
                if currentScale != 1.0 || currentOffset != .zero {
                    Button {
                        withAnimation(.spring(response: 0.4)) {
                            currentScale = 1.0
                            lastScale = 1.0
                            currentOffset = .zero
                            lastOffset = .zero
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        currentScale = lastScale * value
                    }
                    .onEnded { value in
                        lastScale = max(0.5, min(lastScale * value, 4.0))
                        currentScale = lastScale
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        currentOffset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { value in
                        lastOffset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                        currentOffset = lastOffset
                    }
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                animationPhase = 1.0
            }
        }
    }

    private var nonRouterDevices: [NetworkDevice] {
        viewModel.devices.filter { !$0.isGateway }
    }

    // MARK: - Layout

    private func computePositions(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat) -> [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        let devices = nonRouterDevices
        guard !devices.isEmpty else { return result }

        // Radius band per category — subtle variation, not dramatic rings
        let radiusFraction: [DeviceCategory: CGFloat] = [
            .phone: 0.70,
            .apple: 0.75,
            .computer: 0.80,
            .tv: 0.90,
            .speaker: 0.85,
            .printer: 0.95,
            .gaming: 0.88,
            .storage: 0.92,
            .smarthome: 0.98,
            .unknown: 1.0,
            .router: 0,
        ]

        // Distribute ALL devices evenly around the ellipse by array index.
        // This keeps positions stable as devices get classified — only the
        // radius changes slightly, not the angle.
        let count = devices.count
        for (i, device) in devices.enumerated() {
            let angle = (2 * .pi * Double(i) / Double(count)) - .pi / 2
            let rf = radiusFraction[device.category] ?? 1.0
            let pos = CGPoint(
                x: center.x + radiusX * rf * CGFloat(cos(angle)),
                y: center.y + radiusY * rf * CGFloat(sin(angle))
            )
            result[device.id] = pos
        }

        return result
    }

    // MARK: - Drawing

    private func gridBackground(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let gridSpacing: CGFloat = 30
            let color = Color.white.opacity(0.03)

            for x in stride(from: 0, through: canvasSize.width, by: gridSpacing) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }

            for y in stride(from: 0, through: canvasSize.height, by: gridSpacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }
        }
    }

    private func scanPulse(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat) -> some View {
        ForEach(0..<3, id: \.self) { ring in
            let phase = CGFloat(animationPhase + Double(ring) * 0.3).truncatingRemainder(dividingBy: 1.0)
            Ellipse()
                .stroke(Color.cyan.opacity(0.3 - Double(ring) * 0.1), lineWidth: 1)
                .frame(width: radiusX * 2 * phase, height: radiusY * 2 * phase)
                .position(center)
                .opacity(1.0 - Double(phase))
        }
    }

    private func connectionLines(center: CGPoint, positions: [UUID: CGPoint]) -> some View {
        Canvas { context, _ in
            for (deviceID, pos) in positions {
                let device = nonRouterDevices.first { $0.id == deviceID }
                let isStale = device?.isStale ?? false
                let color = isStale ? Color.gray : (device?.category ?? .unknown).swiftUIColor
                let opacity = isStale ? 0.15 : 0.35

                var path = Path()
                path.move(to: center)
                path.addLine(to: pos)

                context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 1)
            }
        }
    }

    private var statusBar: some View {
        VStack(spacing: 4) {
            if viewModel.isScanning {
                ProgressView(value: viewModel.scanProgress)
                    .tint(.cyan)
                    .padding(.horizontal)
            } else if viewModel.isProbing {
                ProgressView()
                    .tint(.orange)
                    .scaleEffect(0.7)
            }

            HStack {
                Text(viewModel.scanStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if !viewModel.localIP.isEmpty {
                    Text(viewModel.localIP)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

}

struct DeviceNode: View {
    let device: NetworkDevice
    @State private var glowPhase: Bool = false

    private var effectiveColor: Color {
        device.isStale ? .gray : nodeColor
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(effectiveColor.opacity(0.2))
                    .frame(width: nodeSize + 12, height: nodeSize + 12)
                    .blur(radius: 4)
                    .opacity(glowPhase ? 0.8 : 0.4)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [effectiveColor.opacity(0.6), effectiveColor.opacity(0.2)],
                            center: .center,
                            startRadius: 0,
                            endRadius: nodeSize / 2
                        )
                    )
                    .frame(width: nodeSize, height: nodeSize)

                Circle()
                    .stroke(effectiveColor.opacity(device.isStale ? 0.3 : 0.8),
                            lineWidth: device.isThisDevice ? 2 : 1)
                    .frame(width: nodeSize, height: nodeSize)

                if device.isStale {
                    // Dashed circle to indicate stale
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.gray.opacity(0.4))
                        .frame(width: nodeSize, height: nodeSize)
                }

                Image(systemName: DeviceClassifier.refinedIcon(for: device))
                    .font(.system(size: iconSize))
                    .foregroundStyle(effectiveColor)
            }

            Text(device.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(device.isStale ? .white.opacity(0.4) : .white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: 80)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.5))
                )
        }
        .opacity(device.isStale ? 0.5 : 1.0)
        .onAppear {
            if device.isThisDevice {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowPhase = true
                }
            }
        }
    }

    private var nodeSize: CGFloat {
        if device.isGateway { return 52 }
        if device.isThisDevice { return 44 }
        return 36
    }

    private var iconSize: CGFloat {
        if device.isGateway { return 22 }
        if device.isThisDevice { return 18 }
        return 14
    }

    private var nodeColor: Color {
        device.category.swiftUIColor
    }
}
