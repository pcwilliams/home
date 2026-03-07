import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = NetworkViewModel()
    @State private var viewMode: ViewMode = .map
    @State private var selectedDevice: NetworkDevice?

    enum ViewMode: String, CaseIterable {
        case map = "Map"
        case list = "List"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("View", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    switch viewMode {
                    case .map:
                        NetworkMapView(viewModel: viewModel, selectedDevice: $selectedDevice)
                    case .list:
                        DeviceListView(viewModel: viewModel, selectedDevice: $selectedDevice)
                    }
                }
            }
            .navigationTitle("HomeNet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if viewModel.isScanning {
                            viewModel.stopScan()
                        } else if viewModel.hasScanned {
                            viewModel.refreshScan()
                        } else {
                            viewModel.startScan()
                        }
                    } label: {
                        if viewModel.isScanning {
                            ProgressView()
                                .tint(.white)
                        } else if viewModel.hasScanned {
                            Image(systemName: "arrow.clockwise")
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(viewModel.devices.count) devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(item: $selectedDevice) { device in
                DeviceDetailView(device: device)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            viewModel.startScan()
        }
    }
}
