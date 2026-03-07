# HomeNet

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI-purple)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

A visual home network scanner for iPhone. Discovers devices on your Wi-Fi using Bonjour/mDNS and TCP port scanning, then displays them on an interactive radial map.

![HomeNet running on iPhone 16 Pro](https://pcwilliams.design/dev/home/home-screenshot.png)

## Features

- **Radial network map** — Router at the centre with devices arranged in concentric rings by category, connected by coloured lines
- **Pinch-to-zoom and drag** — Explore the map with standard iOS gestures; reset button to snap back
- **Bonjour service discovery** — Scans 24 mDNS service types including AirPlay, HomeKit, Chromecast, Sonos, Spotify Connect, and more
- **Subnet port scanning** — Probes the entire /24 network to find devices that don't advertise Bonjour services
- **Smart classification** — Identifies devices as phones, computers, speakers, TVs, printers, smart home devices, gaming consoles, NAS boxes, and more
- **Progressive updates** — Devices appear and update in real time as they're discovered and identified
- **Deep device probing** — After initial scan, probes HTTP headers, SSH banners, UPnP descriptions, AirPlay `/info`, Chromecast `/setup/eureka_info`, and TCP latency for wired/WiFi inference
- **Smart display names** — Devices show friendly names discovered from AirPlay, UPnP, Chromecast, or Bonjour services, falling back to hostname then IP
- **Bonjour TXT records** — Extracts model identifiers, OS versions, device IDs from mDNS metadata for precise Apple device classification
- **Device detail view** — Tap any device to see its IP, hostname, open ports, discovered services, and probe results
- **List view** — Alternative grouped view organised by device category
- **Dark mode** — Designed for dark backgrounds with category-coloured icons and connection lines

## Device Categories

| Category | Icon | Identified By |
|----------|------|---------------|
| Router | wifi.router | Gateway IP address |
| Phone | smartphone | Port 62078, hostname patterns |
| Apple | apple.logo | Companion Link, Device Info services |
| Computer | laptopcomputer | SSH, Screen Sharing, hostname |
| TV & Media | tv | Chromecast, AirPlay, GameStream |
| Speaker | hifispeaker | Sonos, Spotify Connect, AirPlay Audio |
| Printer | printer | IPP, printer/scanner services |
| Smart Home | lightbulb | HomeKit, HAP, Thread/Matter |
| Gaming | gamecontroller | PlayStation/Xbox/Nintendo hostname |
| Storage | externaldrive | NAS hostname, SMB + UPnP ports |

## Getting Started

1. Open `HomeNet.xcodeproj` in Xcode 16+
2. Select your iPhone as the run destination
3. Build and run (Cmd+R)
4. Grant local network access when prompted
5. The scan starts automatically

**Note:** This app must be tested on a physical iPhone — the simulator doesn't have access to a real local network.

## Build from Command Line

```bash
xcodebuild -project HomeNet.xcodeproj -scheme HomeNet \
  -destination 'generic/platform=iOS' build \
  CODE_SIGNING_ALLOWED=NO
```

## Run Tests

```bash
xcodebuild -project HomeNet.xcodeproj -scheme HomeNet \
  -destination 'platform=iOS Simulator,name=iPhone 16' test \
  CODE_SIGNING_ALLOWED=NO
```

119 tests covering device classification, Bonjour name matching, model behaviour, progressive update simulation, deep probing, and TXT record classification.

## Project Structure

```
HomeNet/
├── HomeNet.xcodeproj/
├── CLAUDE.md
├── README.md
├── architecture.html
├── tutorial.html
└── HomeNet/
    ├── App/
    │   ├── HomeNetApp.swift
    │   └── ContentView.swift
    ├── Models/
    │   └── NetworkDevice.swift
    ├── Views/
    │   ├── NetworkMapView.swift
    │   ├── DeviceListView.swift
    │   └── DeviceDetailView.swift
    ├── Services/
    │   ├── NetworkScanner.swift
    │   ├── BonjourBrowser.swift
    │   ├── DeviceClassifier.swift
    │   └── DeviceProber.swift
    ├── ViewModels/
    │   └── NetworkViewModel.swift
    └── Assets.xcassets/
```

## Documentation

- [Architecture diagrams](https://pcwilliams.design/dev/home/architecture.html) — Interactive Mermaid.js diagrams of the scan pipeline and data flow
- [Build tutorial](https://pcwilliams.design/dev/home/tutorial.html) — Step-by-step narrative of how this app was built with Claude Code

## How This Was Built

Built entirely through conversation with Claude Code. No code was written manually.

| Metric | Value |
|--------|-------|
| Source files | 12 |
| Test files | 4 |
| Tests | 119 |
| External dependencies | 0 |
| Frameworks | SwiftUI, Network |

## Licence

Personal use
