# Port Monitor

A small macOS SwiftUI app that shows the open TCP/UDP ports on your machine,
along with the process and PID that owns each one — plus optional per-process
network throughput.

It started life as a single `test.swift` "Hello World". It is now a testable
SwiftPM package with two interchangeable backends and a dependency-free test
suite.

## Features

- Lists listening TCP ports and bound UDP ports
- Shows port, protocol, owning process name, PID, address and socket state
- Live search across port, process, PID, address, protocol and state
- **Filter presets**: all / TCP only / UDP only / listening only / privileged
  (<1024) / unprivileged (>=1024)
- **Group by process** — one expandable row per process, with its sockets
  nested underneath
- **Traffic rate column** — per-process throughput sampled with `nettop`
- Auto-refresh (every 3 seconds) or manual refresh
- Highlights ports that appeared since the previous refresh
- Optional system notifications when a new port opens
- **Export** the rows currently on screen to CSV or JSON
- **Terminate** the process owning a port (with a confirmation prompt)
- **Menu-bar item** showing the live listening count when the window is closed
- **Menu bar only** mode: hide the Dock icon and live in the menu bar
- Selectable data source: native `libproc`, `lsof`, or automatic with fallback
- Clear error surface (e.g. missing `lsof`) instead of a blank window

## Requirements

- macOS 14 or later
- Xcode **Command Line Tools** (a full Xcode install is *not* required)

## How open ports are read

Two interchangeable backends sit behind the `PortProviding` protocol:

| Backend | How it works | Notes |
|---|---|---|
| `NativePortProvider` | `proc_listallpids` + `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` via a small C shim (`CProcSockets`) | No subprocess, no text parsing |
| `LsofPortProvider` | Runs `lsof -F` and parses field output | Proven, but spawns a process |

The default is **Automatic**: it prefers the native backend and falls back to
`lsof` if native returns nothing or errors, so the app can never regress to
showing an empty list. You can force either backend from the **Source** picker.

Both backends only see processes owned by the current user unless run with
elevated privileges, so some system daemons may not appear.

## How traffic rates are read

`nettop -P -L 1 -n -x` reports the kernel's **per-process** byte counters. The
app samples it on each refresh and divides the delta by the elapsed time.

macOS does not expose **per-socket** byte counters through a public API, so a
rate is attributed to the owning process rather than to an individual socket —
which is why the rate reads especially well in the grouped view. Turn the
**Traffic rates** toggle off to skip `nettop` entirely.

## Layout

```
Package.swift
Assets/
  AppIcon.icns            App icon, copied into the bundle
Sources/
  CProcSockets/           C shim reading sockets via libproc
    include/cproc_sockets.h
    cproc_sockets.c
  PortMonitorCore/        Reusable, UI-free logic (also exposed as a library)
    PortInfo.swift        Value type for one open socket
    TransportProtocol.swift
    LsofParser.swift      Pure parser for `lsof -F` output
    LsofPortProvider.swift
    NativePortProvider.swift
    NettopParser.swift    Pure parser for `nettop -L` CSV  (in NettopTrafficProvider.swift)
    NettopTrafficProvider.swift
    PortProviderKind.swift   Backend selection + fallback chain
    PortProviding.swift   Data-source abstraction
    PortFilter.swift      Search + filter presets
    PortListDiffer.swift  'New since last refresh' diffing
    ProcessGrouping.swift Per-process grouping
    Traffic.swift         ProcessTraffic, rate maths, formatting
    PortExport.swift      CSV + JSON serialisation
    Subprocess.swift      Shared process helper
  PortMonitor/            SwiftUI app (executable)
    PortMonitorApp.swift  Window + menu-bar scenes
    ContentView.swift
    PortListViewModel.swift
    AppPreferences.swift  Menu-bar-only preference
    PortNotifier.swift    Bundled-only notifications
  PortMonitorCoreTests/   Dependency-free test runner (executable)
Tests/
  PortMonitorXCTests/     Opt-in XCTest mirror (needs full Xcode)
```

## Usage

```sh
make build     # compile the app
make test      # run the test suite
make run       # launch the GUI
make bundle    # package a Release .app into build/
make clean     # remove artifacts
```

Or with plain SwiftPM:

```sh
swift build
swift run PortMonitorCoreTests   # tests
swift run PortMonitor            # app
```

## Packaging, signing and notarization

`make bundle` produces `build/PortMonitor.app` with `Assets/AppIcon.icns` and an
`Info.plist` (bundle id `com.rahul.PortMonitor`). By default it is **ad-hoc
signed**, which is fine for local use.

```sh
# Ad-hoc (default)
make bundle

# Menu-bar-only bundle (LSUIElement, no Dock icon)
make bundle MENUBAR_ONLY=1

# Developer ID build: hardened runtime + secure timestamp
make bundle CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"

# Notarize and staple (once, store a notarytool profile):
xcrun notarytool store-credentials portmonitor-notary \
    --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
make notarize CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

Developer ID signing and notarization require an **Apple Developer account**;
everything up to and including ad-hoc signing works without one.

## Tests

The canonical suite runs **without XCTest** so it works with a Command Line
Tools-only toolchain: `make test` (or `swift run PortMonitorCoreTests`) exits
non-zero on failure, which is what CI relies on.

```
39/39 passed
```

Covered:

- `lsof -F` parsing: TCP/UDP, commands with spaces, unbound-socket filtering,
  connected sockets, IPv6 hosts, malformed input
- Provider aggregation, sorting, and missing-tool errors
- Fallback chain behaviour (first non-empty, skip errors, rethrow if all fail)
- Native provider output sorted and in range
- **Native and `lsof` agree on the set of TCP listeners** (parity check)
- Filter presets and query matching (name, port, PID, host, protocol, state)
- Refresh diffing: initial load, added/removed sockets, reset
- Per-process grouping and ordering
- Traffic rate maths (deltas, counter resets, unknown PIDs, interval guard)
  and rate formatting
- `nettop` CSV parsing (including dotted process names) and provider wiring
- CSV escaping/header and JSON round-tripping
- Real end-to-end calls to both backends and `nettop`

An **XCTest mirror** of the same assertions lives in `Tests/PortMonitorXCTests`.
XCTest only ships with a full Xcode install, so that target is declared only
when you ask for it:

```sh
make test-xctest      # PORTMONITOR_ENABLE_XCTEST=1 swift test
```

CI runs the dependency-free runner, packages the bundle, and then runs the
XCTest mirror on `macos-latest` (which has Xcode).

## Notes and limitations

- Port info is per-user unless run elevated; system daemons may not appear.
- **Terminate** sends `SIGTERM` (not `SIGKILL`) to the selected PID and asks for
  confirmation first.
- Notifications require a real app bundle; they are a no-op under `swift run`.
  Ad-hoc signing may prevent delivery, which is why they default to off.
- Traffic rates are per **process**, not per socket (see above).
- `test.swift` and the prebuilt `testapp` binary are kept for reference and are
  not part of the package. They can be deleted safely.

## Remaining work

- Developer ID signing / notarization needs an Apple Developer account; the
  `make notarize` path is wired up but unused.
- Possibly surface per-interface traffic (from `netstat -ib`) as a complement to
  the per-process rates.
