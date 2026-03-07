# Apple Dev - Claude Code Project Conventions

This folder contains native iOS apps built entirely through conversation with Claude Code. This file captures the shared principles, patterns, and preferences that apply across all projects.


## Tech Stack

Every project uses the same foundation:

- **Language:** Swift 5
- **UI Framework:** SwiftUI (no storyboards, no XIBs)
- **Minimum Target:** iOS 17.0+ (some projects use iOS 18.0+)
- **Xcode:** 16+
- **Device:** iPhone only (`TARGETED_DEVICE_FAMILY = 1`)
- **Orientation:** Portrait only
- **Dependencies:** Zero external dependencies — pure Apple frameworks only (SwiftUI, MapKit, CoreLocation, Photos, CryptoKit, Swift Charts, etc.)

## Architecture

All projects follow **MVVM** with SwiftUI's reactive data binding:

- **View models** are `ObservableObject` classes with `@Published` properties, observed via `@StateObject` in views
- **Views** are declarative SwiftUI — no UIKit unless wrapping a system controller (e.g. `SFSafariViewController`)
- **Services/API clients** use the `actor` pattern for thread safety
- **Networking** uses native `URLSession` with `async/await` — no external HTTP libraries
- **View models** are annotated `@MainActor` when they drive UI state

## Project Structure

Each project follows this standard layout:

```
ProjectName/
├── ProjectName.xcodeproj/
├── CLAUDE.md                    # Developer reference (this kind of file)
├── README.md                    # User-facing documentation
├── architecture.html            # Interactive Mermaid.js architecture diagrams
├── tutorial.html                # Build narrative with prompts and responses
└── ProjectName/
    ├── App/
    │   ├── ProjectNameApp.swift # @main entry point
    │   └── ContentView.swift    # Root view / navigation
    ├── Models/                  # Data model structs and SwiftData @Models
    ├── Views/                   # SwiftUI views
    │   └── Components/          # Reusable view components
    ├── Services/                # API clients, managers, business logic
    ├── ViewModels/              # ObservableObject state management
    ├── Extensions/              # Formatters and helpers
    └── Assets.xcassets/
        ├── AppIcon.appiconset/  # 1024x1024 icons (standard, dark, tinted)
        └── AccentColor.colorset/
```

Smaller projects (e.g. Where) may flatten this into fewer files — the principle is simplicity over ceremony.

## Xcode Project File (project.pbxproj)

Projects are created and maintained by writing `project.pbxproj` directly, not via the Xcode GUI. When adding new Swift files to a target that doesn't use file system sync, register in four places:

1. **PBXBuildFile section** — build file entry
2. **PBXFileReference section** — file reference entry
3. **PBXGroup** — add to the appropriate group's `children` list
4. **PBXSourcesBuildPhase** — add build file to the target's Sources phase

ID patterns vary per project but follow a consistent incrementing convention within each project. Test targets may use `PBXFileSystemSynchronizedRootGroup` (Xcode 16+), meaning test files are auto-discovered.

## Build Verification

Always verify the build after any code change:

```bash
xcodebuild -project ProjectName.xcodeproj -scheme ProjectName \
  -destination 'generic/platform=iOS' build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

A clean result ends with `** BUILD SUCCEEDED **`. Fix any errors before considering a task complete.

## Testing

```bash
xcodebuild -project ProjectName.xcodeproj -scheme ProjectName \
  -destination 'platform=iOS Simulator,name=iPhone 16' test \
  CODE_SIGNING_ALLOWED=NO
```

- Use **in-memory containers** for SwiftData tests (fast, isolated)
- Use the **Swift Testing framework** (`import Testing`, `@Test`, `#expect()`) for newer projects
- **Extract pure decision logic as `internal static` methods** with explicit parameters so tests can inject values directly — avoid testing through singletons, UserDefaults, or system frameworks
- Test files that use Foundation types must `import Foundation` alongside `import Testing`

## Key Patterns

### Persistence

- **SwiftData** for structured app data (e.g. PillRecord)
- **UserDefaults / @AppStorage** for preferences, settings, and cache
- **iOS Keychain** for API credentials and secrets (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **JSON encoding** in UserDefaults for lightweight structured data (e.g. portfolio, saved places)

### Networking

- **Graceful degradation:** The app should work with reduced functionality when API calls fail. Isolate independent API calls in separate `do/catch` blocks so one failure doesn't take down the others
- **Task cancellation:** Cancel in-flight tasks before starting new ones. Check `Task.isCancelled` before publishing results
- **Debouncing:** Use 0.8-second debounce for rapid user interactions (e.g. map panning) to prevent API spam
- **Caching:** Cache API responses with TTLs in UserDefaults (e.g. 5-min for quotes, 30-min for historical data)

### Concurrency

- **Actor-based services** for thread-safe API clients
- **`async let` for parallel fetching** of independent data
- Wrap work in an unstructured `Task` inside `.refreshable` to prevent SwiftUI from cancelling structured concurrency children when `@Published` properties trigger re-renders
- **`Task.detached(.utility)`** for background work like photo library scanning
- **Swift 6 concurrency:** Use `guard let self else { return }` in detached task closures; copy mutable `var` to `let` before `await MainActor.run`

### Timers

- Prefer **one-shot `DispatchWorkItem`** over polling `Timer.publish`
- Avoid always-running timers — schedule on demand, cancel on completion

### SwiftUI

- **`.id()` modifier** on views for animated identity changes (e.g. month transitions)
- **GeometryReader** for proportional layouts
- **Asymmetric slide transitions** with tracked direction state
- **NavigationStack** with `.toolbar` and `.sheet` for settings
- **`.refreshable`** for pull-to-refresh
- **Segmented pickers** for mode selection (chart periods, map styles, etc.)
- **@AppStorage** for persisting UI preferences across launches
- **`.contentShape(Rectangle())`** for full-row tap targets

## App Icons

Generated programmatically using **Python/Pillow** — not designed in a graphics tool. Three variants at 1024x1024:

- **Standard** (light mode)
- **Dark** (dark mode)
- **Tinted** (greyscale for tinted mode)

Referenced in `Contents.json` with `luminosity` appearance variants. Use `Image.new("RGB", ...)` not `"RGBA"` — iOS strips alpha for app icons, causing compositing artefacts with semi-transparent overlays.

## Documentation

Each project includes four living documents that must be kept up to date as the project evolves:

### CLAUDE.md (developer reference)

The comprehensive knowledge base for Claude Code sessions. Must be updated whenever:
- A new file, model, view, or service is added or removed
- An architectural decision is made or changed
- A new API is integrated or an existing one changes
- A non-obvious bug is fixed or a gotcha is discovered
- Build configuration, test coverage, or project structure changes

This is the single source of truth for project context. A future session should be able to read CLAUDE.md and understand the entire project without exploring the codebase.

### README.md (user-facing)

The public-facing project overview. Must be updated whenever:
- Features are added, changed, or removed
- Setup instructions change (new dependencies, API keys, permissions)
- The project structure changes significantly
- Screenshots become outdated (note when a new screenshot is needed)

Keep it concise and practical — someone should be able to clone the repo and get running by following the README.

### architecture.html (architecture diagrams)

Interactive Mermaid.js diagrams rendered in a standalone HTML file. Must be updated whenever:
- The view hierarchy changes (new views, removed views, restructured navigation)
- Data flow changes (new services, new API integrations, changed data pipelines)
- New major subsystems are added (e.g. a notification system, a caching layer, a P&L calculator)

Use `graph TD` (top-down) for readability on narrow screens. Load Mermaid.js from CDN. Apply the shared dark theme with CSS custom properties and project-appropriate accent colours.

### tutorial.html (build narrative)

A step-by-step record of how the app was built through Claude Code conversation. Must be updated whenever:
- A significant new feature is added via a notable prompt interaction
- A major refactor or architectural change is made
- An interesting problem is solved through iterative prompting

Capture the essence of the prompt, the approach taken, and the outcome. This documents the collaborative development process and serves as a guide for building similar features in future projects.

**Prompt tone:** Prompts recorded in the tutorial should sound collaborative, not demanding. Use phrases like "Could we try...", "How about...", "Would you mind...", "Would it be worth...", "I'd love it if..." rather than "Make...", "Add...", "I want...", "I need...". When describing problems, use "I'm seeing..." or "I'm noticing..." rather than assertive declarations. The tone should reflect a partnership — two people working together on something, not instructions being issued.

### Formatting conventions

- Use plain Markdown in `.md` files (no inline HTML except README badges). Images must use `![alt](src)` syntax, not `<img>` tags
- HTML docs use a shared dark theme with CSS custom properties and Mermaid.js loaded from CDN
- HTML docs include a hero screenshot in a phone-frame wrapper (black background, rounded corners, drop shadow) below the title/badges

## Allowed Permissions

Claude Code may freely perform the following without asking:

- **Read any file** in `/Users/pwilliams/appledev/` and all subfolders
- **Read anything from the web** (documentation, API references, etc.)
- **Run read-only shell commands** in this folder and subfolders: `ls`, `head`, `tail`, `grep`, `find`, `cat`, `wc`, `file`, `diff`, `git log`, `git status`, `git diff`, etc.
- **Build projects** using the Xcode toolchain (`xcodebuild build`, `swift build`, etc.)
- **Run tests** using the Xcode toolchain (`xcodebuild test`)
- **Launch and use the iPhone Simulator** for testing (`xcrun simctl` commands, simulator destinations in xcodebuild)

## Working Style

- **Iterative conversation:** Apps are built through progressive prompts — start with the core idea, then refine through follow-up requests
- **Copy-based versioning:** Folder copies (e.g. `BitcoinTracker copy 8`) are used as snapshots before major changes, providing easy rollback
- **Build-verify-iterate:** Every change is verified with a build before moving on
- **Real-device testing:** Apps are tested on a physical iPhone 16 Pro — simulators lack GPS, geotagged photos, and other sensor data
- **CLAUDE.md is the living knowledge base:** It captures every architectural decision, API quirk, and lesson learned so future sessions start with full context

## Common Gotchas

- **Keychain: always delete before add** to avoid `errSecDuplicateItem`
- **SwiftUI `.refreshable` cancels structured concurrency** — wrap network calls in an unstructured `Task`
- **Wikimedia geosearch caps at 10,000m radius** — clamp before sending
- **Wikipedia disambiguation pages** — filter out articles where extract contains "may refer to"

---

# HomeNet - Network Scanner & Visualiser

Visual home network discovery app for iPhone. Scans Wi-Fi networks using Bonjour/mDNS service discovery and TCP port probing, then displays devices on an interactive radial map.

## Quick Reference

- **Bundle ID:** com.pwilliams.HomeNet
- **Target:** iOS 17.0+, iPhone only, portrait only
- **Frameworks:** SwiftUI, Network (NWBrowser, NWConnection)
- **Architecture:** MVVM with actor-based network scanning
- **Tests:** 119 tests (Swift Testing framework)

## Project Structure

```
HomeNet/
├── HomeNet.xcodeproj/        # File system sync (objectVersion 77), includes test target
├── CLAUDE.md
├── README.md
├── architecture.html          # Interactive Mermaid.js architecture diagrams
├── tutorial.html              # Build narrative with prompts and responses
└── HomeNet/
    ├── App/
    │   ├── HomeNetApp.swift   # @main entry point
    │   └── ContentView.swift  # NavigationStack with map/list segmented picker
    ├── Models/
    │   └── NetworkDevice.swift # NetworkDevice, DiscoveredService, DeviceCategory
    ├── Views/
    │   ├── NetworkMapView.swift    # Radial map with pinch-zoom, drag-pan, DeviceNode
    │   ├── DeviceListView.swift    # Grouped list view by category, DeviceRow
    │   └── DeviceDetailView.swift  # Device detail sheet with FlowLayout
    ├── Services/
    │   ├── NetworkScanner.swift    # Actor: subnet scanning, port probing, hostname resolution
    │   ├── BonjourBrowser.swift    # NWBrowser: mDNS service discovery (24 service types)
    │   ├── DeviceClassifier.swift  # Device type identification from services/hostname/ports/probes
    │   └── DeviceProber.swift      # Actor: HTTP headers, SSH banners, UPnP descriptions
    ├── ViewModels/
    │   └── NetworkViewModel.swift  # @MainActor: orchestrates scanning, progressive updates
    └── Assets.xcassets/
        ├── AppIcon.appiconset/     # Network topology icons (standard/dark/tinted)
        └── AccentColor.colorset/   # Cyan accent
HomeNetTests/
    ├── DeviceClassifierTests.swift  # 48 tests: service/hostname/port/probe/TXT record classification
    ├── NetworkDeviceTests.swift     # 11 tests: model equality, display name, hash
    ├── ProgressiveUpdateTests.swift # 18 tests: enrichment pipeline simulation + probing
    ├── BonjourMatchingTests.swift   # 32 tests: hex prefix stripping, name normalisation, matching, display names
    └── Info.plist                   # ATS: NSAllowsLocalNetworking
```

## How It Works

### Discovery Pipeline
1. **getifaddrs()** — Gets local IP, subnet mask, computes gateway and address range
2. **Parallel discovery** — Bonjour browsing (8s window) and subnet scanning run concurrently via `async let`
3. **Subnet port scan** — Batches of 25 IPs, each probed on 15 common ports with 1.0s timeout via NWConnection
4. **Identification batches** — Groups of 8 devices resolved in parallel (hostname + 20-port fingerprint, 1.5s timeout)
5. **Progressive classification** — Each device classified immediately after its info arrives; Bonjour services matched by hostname
6. **Live UI updates** — `@Published` array with full `Equatable` comparison triggers SwiftUI re-renders per batch
7. **Background deep probe** — After scan completes, a separate Task probes devices for HTTP headers, SSH banners, UPnP descriptions; updates arrive progressively without blocking the map

### Deep Probing (DeviceProber)
After the initial scan shows all devices, a background `DeviceProber` actor interrogates each device:
- **HTTP/HTTPS** (ports 80, 443, 8080, 8443) — Server header, page title, X-Powered-By, meta generator, auth realm
- **SSH banner** (port 22) — Server version string (e.g. `SSH-2.0-OpenSSH_8.9p1`)
- **FTP/SMTP/RTSP banners** (ports 21, 25, 554) — Welcome messages reveal server identity
- **UPnP device description** — Fetches XML from standard paths (`/description.xml`, `/rootDesc.xml`, etc.) to extract manufacturer, model, serial number, firmware version
- **AirPlay /info** (port 7000) — Binary/XML plist with model identifier, firmware, MAC address, AirPlay version
- **Chromecast /setup/eureka_info** (port 8008) — JSON with name, model, manufacturer, firmware, WiFi SSID/signal/noise, ethernet status
- **TCP latency** — ContinuousClock timing of TCP connection as proxy for wired (<5ms) vs WiFi (5–30ms) vs multi-hop (>50ms)
- Results stored as `[ProbeEntry]` on each device, displayed in a "Discovered Info" section in the detail view
- Probe results also feed into `DeviceClassifier` for reclassification (e.g. UPnP reveals a Sonos, HTTP Server reveals Plex)
- Probe-discovered friendly names (from any source: UPnP, AirPlay, Chromecast) are preferred for `displayName` on the map/list

### Bonjour TXT Record Classification
TXT records from Bonjour service discovery (e.g. `model`, `am`, `osvers`, `deviceid`) are extracted per-service and used for:
- **Apple model ID classification** — `MacBookPro18,1` → .computer, `AppleTV6,2` → .tv, `AudioAccessory5,1` → .speaker
- **Refined icons** — Model ID selects precise SF Symbols (e.g. `macmini` for Mac mini, `airpods` for AirPods)
- **Detail view display** — TXT records shown inline under each Bonjour service in the services section

### Device Categories
| Category | Icon | Colour | Radius | Identification |
|----------|------|--------|--------|----------------|
| Router | wifi.router | Blue | Centre | Gateway IP |
| Phone | smartphone | Indigo | 0.70 | Port 62078, hostname patterns |
| Apple | apple.logo | Cyan | 0.75 | _companion-link, _device-info services |
| Computer | laptopcomputer | Purple | 0.80 | SSH, Screen Sharing, hostname patterns |
| Speaker | hifispeaker | Orange | 0.85 | Sonos, Spotify Connect, AirPlay Audio |
| Gaming | gamecontroller | Red | 0.88 | Hostname patterns (PlayStation, Xbox, etc.) |
| TV & Media | tv | Pink | 0.90 | Chromecast, AirPlay, NVIDIA GameStream |
| Storage | externaldrive | Teal | 0.92 | NAS hostname patterns, SMB + port 5000 |
| Printer | printer | Green | 0.95 | IPP, _printer, _scanner services |
| Smart Home | lightbulb | Yellow | 0.98 | HomeKit, HAP, Thread/Matter |
| Unknown | questionmark.circle | Grey | 1.00 | Fallback |

### Bonjour Service Types Scanned
`_airplay._tcp`, `_raop._tcp`, `_homekit._tcp`, `_hap._tcp`, `_googlecast._tcp`, `_spotify-connect._tcp`, `_sonos._tcp`, `_amzn-wplay._tcp`, `_companion-link._tcp`, `_http._tcp`, `_ssh._tcp`, `_smb._tcp`, `_printer._tcp`, `_ipp._tcp`, `_pdl-datastream._tcp`, `_scanner._tcp`, `_daap._tcp`, `_airport._tcp`, `_device-info._tcp`, `_rfb._tcp`, `_nvstream._tcp`, `_privet._tcp`, `_sleep-proxy._udp`, `_meshcop._udp`

### Ports Probed
**Discovery (15 ports, 1.0s):** 22, 53, 80, 443, 445, 548, 554, 631, 5000, 5353, 7000, 8080, 8443, 9090, 62078

**Fingerprinting (20 ports, 1.5s):** 22, 53, 80, 443, 445, 548, 554, 631, 3000, 3689, 5000, 5353, 7000, 7100, 8080, 8443, 8888, 9090, 49152, 62078

## Key Design Decisions

- **Actor for NetworkScanner** — Thread-safe concurrent port scanning with TaskGroup
- **NWConnection for probing** — iOS-approved way to check TCP connectivity (no raw sockets)
- **ContinuationGate (NSLock)** — Shared across NetworkScanner and DeviceProber; prevents double-resume of `withCheckedContinuation` from NWConnection state handler + timeout
- **8-second Bonjour window** — Many devices take several seconds to respond to mDNS queries
- **Batched scanning (25 IPs)** — Prevents iOS from throttling/dropping concurrent NWConnections
- **Progressive classification** — Each device classified immediately after identification, not deferred to end of scan
- **Full Equatable on NetworkDevice** — Compares ipAddress + hostname + category + services + openPorts so SwiftUI detects every enrichment
- **Elliptical layout with stable positioning** — All non-router devices distributed evenly by array index around a full ellipse (independent X/Y radii for portrait screens), with subtle radius variation by category (0.70–1.0). Angles stay stable as devices get classified — only radius shifts slightly
- **MagnificationGesture + DragGesture** — Combined with `.simultaneousGesture` for concurrent zoom and pan
- **Canvas for grid/lines** — Performant drawing for connection lines and background grid
- **Background probing** — Deep probe runs as separate Task after scan completes, so map shows immediately
- **NSAllowsLocalNetworking** — ATS exception in Info.plist for HTTP requests to local IP addresses
- **Opt-in diagnostic logging** — `NetworkViewModel.verbose` flag (default `false`); flip to `true` for Bonjour matching and scan pipeline debug output
- **InsecureSessionDelegate** — URLSession delegate that accepts self-signed certs from local HTTPS devices
- **DeviceCategory.swiftUIColor** — Single source of truth for category colours; used by all views instead of duplicate switch statements
- **cleanHostname()** — Shared helper for stripping domain suffixes (.local, .lan, .home.arpa); used by displayName and ViewModel matching
- **IP-based deduplication** — After all Bonjour matching, `deduplicateByIP()` merges devices sharing the same IP, combining services/ports/probes and reclassifying

## Permissions Required (Info.plist)

- **NSLocalNetworkUsageDescription** — Local network access for scanning
- **NSBonjourServices** — Array of all 24 Bonjour service types (must be XML array in Info.plist, not pbxproj)
- **NSAllowsLocalNetworking** — ATS exception for HTTP requests to local IP addresses

## Build

```bash
xcodebuild -project HomeNet.xcodeproj -scheme HomeNet \
  -destination 'generic/platform=iOS' build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

## Test

```bash
xcodebuild -project HomeNet.xcodeproj -scheme HomeNet \
  -destination 'platform=iOS Simulator,name=iPhone 16' test \
  CODE_SIGNING_ALLOWED=NO
```

## Gotchas & Lessons Learned

- **NSBonjourServices must be in Info.plist** — All 24 service types must be declared as an XML array in Info.plist; without this, NWBrowser fails with `NoAuth (-65555)` on every browse
- **`displayName` must check all probe sources** — AirPlay and Chromecast probes return friendly names via `label: "Name"`, not just UPnP; check any source with `label == "Name"`
- **RAOP Bonjour names have hex prefix** — `_raop._tcp` service names use format `HEXMAC@DeviceName` (e.g. `D0817AD9AF37@Paul's iMac Pro`); `stripBonjourHexPrefix()` in NetworkDevice.swift strips this globally — in the Bonjour device map key, name matching, mDNS resolution, and display name
- **Bonjour creates duplicate devices** — Multiple Bonjour services and port scanning can discover the same device separately; `deduplicateByIP()` merges them after all matching, combining services, ports, and probe results. Keeps the richer device (more services) as the base
- **Never dedup on sentinel IPs** — Bonjour-only devices that can't be resolved get `ip=unknown`; dedup must skip these or all unresolvable devices merge into one Frankenstein device
- **DNS vs Bonjour name mismatch** — Routers add disambiguation suffixes (`-7`), Bonjour uses instance numbers (`(920)`), and domain suffixes (`.lan`, `.local`, `.home.arpa`) vary; `normaliseName()` strips all of these for comparison
- **NWConnection `.waiting` state** — Must be handled as "not reachable", otherwise connections hang until timeout
- **`browseResultsChangedHandler` is Sendable** — Can't access MainActor-isolated state directly; parse results in the closure, then dispatch to MainActor via `Task { @MainActor in ... }`
- **Custom Equatable kills SwiftUI updates** — If `==` only checks IP, SwiftUI won't re-render when hostname/category change
- **Concurrent NWConnections flood iOS** — More than ~50 simultaneous connections get silently dropped; batch to 25
- **`getifaddrs` interface name** — Wi-Fi is always `en0` on iOS; check for `AF_INET` (IPv4)

## Known Limitations

- Cannot get MAC addresses on iOS (no ARP access)
- Bonjour only finds devices that advertise services — silent devices found via port scan
- Port scanning triggers local network permission prompt on first launch
- Subnet scan limited to /24 (254 hosts) even on larger subnets
- Simulator won't find real network devices — test on physical device
