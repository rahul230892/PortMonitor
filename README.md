# PortMonitorTest

A small macOS SwiftUI app that shows the open TCP/UDP ports on your machine,
along with the process and PID that owns each one.

The original `test.swift` was just a SwiftUI "Hello World". This project
implements the actual port monitor and wraps it in a testable Swift package.

## Features

- Lists listening TCP ports and bound UDP ports
- Shows port, protocol, owning process name, PID, address and socket state
- Live search across port, process, PID, address and protocol
- Auto-refresh (every 3 seconds) or manual refresh
- Highlights ports that appeared since the previous refresh
- Optional system notifications when a new port opens
- **Terminate** the process owning a port (with a confirmation prompt)
- **Menu-bar item** showing the live listening count when the window is closed
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

## Layout

```
Package.swift
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
    PortProviderKind.swift   Backend selection + fallback chain
    PortProviding.swift   Data-source abstraction
  PortMonitorTest/        SwiftUI app (executable)
    PortMonitorApp.swift  Window + menu-bar scenes
    ContentView.swift
    PortListViewModel.swift
    PortNotifier.swift    Bundled-only notifications
  PortMonitorCoreTests/   Dependency-free test runner (executable)
```

## Usage

```sh
make build     # compile the app
make test      # run the test suite
make run       # launch the GUI
make bundle    # package a Release .app into build/
```

Or with plain SwiftPM:

```sh
swift build
swift run PortMonitorCoreTests   # tests
swift run PortMonitorTest        # app
```

## Tests

The suite runs without XCTest so it works with a Command Line Tools only
toolchain. Run it with `make test` (or `swift run PortMonitorCoreTests`); it
exits non-zero on failure, which is what CI relies on.

Covered:

- `lsof -F` parsing: TCP/UDP, commands with spaces, unbound-socket filtering,
  connected sockets, IPv6 hosts, malformed input
- Provider aggregation, sorting, and missing-tool errors
- Fallback chain behaviour (first non-empty, skip errors, rethrow if all fail)
- Native provider output is sorted and in range
- **Native and `lsof` agree on the set of TCP listeners** (parity check)
- Real end-to-end calls to both backends

## Notes and limitations

- Port info is per-user unless run elevated; system daemons may not appear.
- **Terminate** sends `SIGTERM` (not `SIGKILL`) to the selected PID and asks for
  confirmation first.
- Notifications require a real app bundle; they are a no-op under `swift run`.
  Ad-hoc signing may prevent delivery, which is why they default to off.
- `test.swift` and the prebuilt `testapp` binary are kept for reference and are
  not part of the package. They can be deleted safely.

## Remaining work

- App icon and Developer ID signing / notarization (needs an Apple Developer
  account; the bundle is currently ad-hoc signed by `make bundle`).
- Per-process grouping and expand/collapse in the table.
- Unit tests for the SwiftUI view model.
