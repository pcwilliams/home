
# iOS Development Conventions

Native iOS apps built with Swift and SwiftUI. No storyboards, no external dependencies.

## Tech Stack

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
├── CLAUDE.md                    # Developer reference
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

Smaller projects (e.g. Where) may flatten this into fewer files — simplicity over ceremony.

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

### Simulator Testing with Launch Arguments

For apps with multiple modes or views, add **launch argument parsing** so visual testing can be fully automated from the command line — never try to tap simulator UI with AppleScript (it's unreliable). Parse `ProcessInfo.processInfo.arguments` in the root view to accept flags like `-mode <value>`.

**Launch arguments must override persisted settings.** When an app uses `@AppStorage` or `UserDefaults`, launch arguments must be applied *after* persistence loads (e.g. in `onAppear`) so they take priority. Return optionals from launch-arg parsers (nil = no override).

```swift
// In ContentView or root view
private static func initialMode() -> Mode {
    let args = ProcessInfo.processInfo.arguments
    if let idx = args.firstIndex(of: "-mode"), idx + 1 < args.count {
        return Mode(rawValue: args[idx + 1]) ?? .default
    }
    return .default
}
```

Then test each mode from the command line:

```bash
xcrun simctl install booted path/to/App.app
xcrun simctl privacy booted grant microphone com.bundle.id  # if needed
xcrun simctl terminate booted com.bundle.id
xcrun simctl launch booted com.bundle.id -- -mode someMode
sleep 2
xcrun simctl io booted screenshot /tmp/screenshot.png
```

This pattern was established in ShiftingSands and adopted in Spectrum. Every new project with multiple visual states should support this from the start.

### Bundled Test Files for Hardware-Dependent Features

When a feature depends on hardware input (microphone, GPS, camera), create **bundled test files** that exercise the same code path in the simulator:

- **Audio**: Generate WAV files with Python — pure tones (440Hz sine), multi-tone sequences, periodic beats. Bundle and play via `-testfile <name>` launch argument.
- **Location**: Bundle JSON files with known GPS coordinates for map-based testing.
- **Images**: Bundle sample photos with known EXIF data for photo-processing features.

The DSP/processing pipeline shouldn't know or care whether input comes from hardware or a test file.

```python
import wave, struct, math
sample_rate = 44100
samples = []
for freq, duration in [(261.63, 1.5), (329.63, 1.5), (440.0, 1.5), (0, 1.0)]:
    for i in range(int(sample_rate * duration)):
        t = i / sample_rate
        value = 0.7 * math.sin(2 * math.pi * freq * t) if freq > 0 else 0
        samples.append(int(value * 32767))
with wave.open('test.wav', 'w') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(sample_rate)
    f.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
```

### Diagnostic Logging for Algorithm Debugging

For complex algorithms (DSP, ML, signal processing), add **structured diagnostic logging** gated behind a launch argument:

```swift
// In the engine/service
static var verboseLogging = false

// In the algorithm
if Self.verboseLogging {
    alog("PITCH DBG: acPeak=\(peak) lag=\(lag) freq=\(freq)Hz")
}

// In ContentView onAppear
if args.contains("-pitchlog") { AudioEngine.verboseLogging = true }
```

**What to log:** algorithm confidence metrics, which branch/threshold was taken, input characteristics, state changes.

**What NOT to log every frame:** raw sample values, full array contents, unchanged state.

Use change-only logging for display state and periodic logging for diagnostics (every Nth frame).

### Reading Logs from Simulator and Device

```bash
# Simulator: read the app's Documents directory
CONTAINER=$(xcrun simctl get_app_container booted com.bundle.id data)
cat "$CONTAINER/Documents/app.log"

# Clear log before a test run
> "$CONTAINER/Documents/app.log"

# Device: stream logs via:
xcrun devicectl device syslog --device <udid>
```

### Performance Testing in the DSP/Rendering Pipeline

For real-time processing, measure execution time against the time budget:

```swift
let start = CACurrentMediaTime()
// ... processing ...
let elapsed = CACurrentMediaTime() - start
dspTimingSum += elapsed
dspTimingCount += 1
if elapsed > dspTimingMax { dspTimingMax = elapsed }
if dspTimingCount % 100 == 0 {
    let avgMs = (dspTimingSum / Double(dspTimingCount)) * 1000
    let maxMs = dspTimingMax * 1000
    let budgetMs = Double(bufferSize) / Double(sampleRate) * 1000
    alog("DSP PERF: avg=\(avgMs)ms, max=\(maxMs)ms, budget=\(budgetMs)ms")
}
```

Budget = time between callbacks (e.g. 2048 samples at 44.1kHz = 46.4ms). If average exceeds ~50% of budget, optimise before adding features.

### Simulator vs Device Differences

The simulator does NOT replicate everything. Always test on device for:

- **Microphone input** (simulator has no mic hardware)
- **GPS / CoreLocation** (simulator uses simulated locations)
- **Audio session behaviour** (`.playAndRecord` fails on simulator — use `.playback` with `#if targetEnvironment(simulator)`)
- **Sample rates** (simulator often uses 44.1kHz, device may use 48kHz — parameterise, don't hardcode)
- **Real-world signal characteristics** (voice has harmonics, vibrato, breath noise that pure test tones lack)
- **Hardware format edge cases** (0 Hz sample rate, 0 input channels — detect and alert the user)

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

### GPU rendering — 3D surfaces, terrain, waterfalls, landscapes

For any feature that renders a 2D value field as a lit, animated 3D surface (frequency × time, day × hour, X × Y × any-Z, ridgelines, terrain), use the **`3dsurface`** skill. It captures the canonical Metal pipeline, mesh, camera math, lighting, smoothing, and animation patterns extracted from HeartMap and Spectrum — including the non-obvious decisions (fixed colour scales, smoothing-decoupled-from-colour, face normals, locked camera) that make a surface read as *stunning* rather than just correct.

### Apple Health / HealthKit

For any feature that reads heart rate, steps, workouts, sleep, or other Apple Health data, use the **`healthkit`** skill. It captures the actor-based service shape, authorization (single combined prompt; read perms aren't queryable), the optimized fetch patterns (per-month queries, server-side bucketing via `HKStatisticsCollectionQuery + .cumulativeSum`, parallel `async let`), the three-phase load (disk-cache seed → current-month refresh → background stream), the empty-result fallback to demo data, infinity-safe JSON disk caching, workout activity type → label/symbol mapping, and entitlements/provisioning gotchas (wildcard profiles can't carry HealthKit).

For *clinical interpretation* of that data — fitness scores, resting heart rate calculations, AHA active-minute zones, age-adjusted scoring, evidence-based step thresholds — use the **`health`** skill. It's platform-agnostic (useful in web dashboards too) and always carries an explicit "not medical advice" disclaimer.

## App Icons

Generated programmatically using **Python/Pillow** — not designed in a graphics tool. Three variants at 1024x1024:

- **Standard** (light mode)
- **Dark** (dark mode)
- **Tinted** (greyscale for tinted mode)

Referenced in `Contents.json` with `luminosity` appearance variants. Use `Image.new("RGB", ...)` not `"RGBA"` — iOS strips alpha for app icons, causing compositing artefacts with semi-transparent overlays.

## Documentation

Each project includes four living documents that must be kept up to date:

### CLAUDE.md (developer reference)

Must be updated whenever: a file, model, view, or service is added/removed; an architectural decision is made; a new API is integrated; a non-obvious bug is fixed; build configuration or project structure changes.

This is the single source of truth for project context. A future session should be able to read CLAUDE.md and understand the entire project without exploring the codebase.

### README.md (user-facing)

Must be updated whenever: features are added/changed/removed; setup instructions change; project structure changes significantly; screenshots become outdated.

### architecture.html (architecture diagrams)

Interactive Mermaid.js diagrams. Must be updated whenever: view hierarchy changes; data flow changes; new major subsystems are added.

Use `graph TD` for readability. Load Mermaid.js from CDN. Apply the shared dark theme with CSS custom properties and project-appropriate accent colours.

### tutorial.html (build narrative)

A step-by-step record of how the app was built. Must be updated whenever: a significant new feature is added; a major refactor is made; an interesting problem is solved through iterative prompting.

**Prompt tone:** Use collaborative language — "Could we try...", "How about...", "I'd love it if..." rather than imperatives. Use "I'm seeing..." for problems rather than assertive declarations.

### Formatting conventions

- Plain Markdown in `.md` files (no inline HTML except README badges). Images use `![alt](src)` syntax, not `<img>` tags
- HTML docs use a shared dark theme with CSS custom properties and Mermaid.js loaded from CDN
- HTML docs include a hero screenshot in a phone-frame wrapper (black background, rounded corners, drop shadow) below the title/badges

## Common Gotchas

- **Keychain: always delete before add** to avoid `errSecDuplicateItem`
- **SwiftUI `.refreshable` cancels structured concurrency** — wrap network calls in an unstructured `Task`
- **Wikimedia geosearch caps at 10,000m radius** — clamp before sending
- **Wikipedia disambiguation pages** — filter out articles where extract contains "may refer to"

---

# HomeNet - Network Scanner & Visualiser

Visual home network discovery app for iPhone. Scans Wi-Fi networks using Bonjour/mDNS service discovery and TCP port probing, then displays devices on an interactive radial map.

Shared iOS conventions (Swift 5 / SwiftUI / MVVM, Xcode pbxproj editing, build verification, simulator launch-arg testing, diagnostic logging, app icon generation) live in the `ios` skill referenced above.

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

For day-to-day device rebuilds, use the bundled `run_phone.sh` — it
builds (signed, via `id=$IPHONE_BUILD_ID -allowProvisioningUpdates
DEVELOPMENT_TEAM=$APPLE_TEAM_ID`), installs via `devicectl`, and
launches in one step:

```bash
./run_phone.sh
```

`run_phone.sh` reads `APPLE_TEAM_ID` / `IPHONE_UDID` / `IPHONE_BUILD_ID`
from `~/appledev/setupenv.sh`. The bare
`-destination "platform=iOS,name=…"` form silently produces an unsigned
`.app` that fails to install with `No code signature found` — the script
side-steps that. (HomeNet must be tested on a physical device anyway —
the simulator can't access a real local network.)

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
