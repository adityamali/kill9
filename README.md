# Kill9

A standalone macOS 13+ menu bar utility, written in SwiftUI and AppKit. Open the status icon to inspect live TCP listeners and stop a process holding a development port.

## Run

Open `Kill9.xcodeproj`, select the shared **Kill9** scheme, then Run. No third-party packages are required. The app appears as a compact **KILL9** wordmark in Impact in the menu bar, with a system heavy font fallback. The wordmark is drawn as a 34×18pt native template image, centered by its visible bounds inside a variable-width status item; AppKit controls tint for appearance and selection. The popover header uses the KILL9 Impact wordmark without a system symbol. The app icon uses the supplied black-and-white artwork, packaged at standard macOS icon sizes. It has no Dock icon or conventional app window. Quit is inside the popover.

For a universal local build (Apple silicon and Intel):

```sh
./Scripts/build.sh
```

Outputs:

- `build/Release/Kill9.app` — locally ad-hoc signed app.
- `build/Kill9-macOS.zip` — app archive.
- `build/Kill9-Implementation.zip` — complete source, Xcode project, tests, design spec, and build script.

The local build is not Developer ID signed or notarized. Configure your Apple development team and distribution signing before external distribution. App Sandbox is deliberately disabled so the utility can inspect and signal the user's local development processes.

## Behavior

Every popover opening launches `/usr/sbin/lsof -iTCP -sTCP:LISTEN -n -P -Fpcn` on a worker task. `-Fpcn` adds machine-readable PID, command, and endpoint fields to the requested TCP LISTEN snapshot. No polling timer runs while the app is idle. Refresh clicks during an active scan coalesce into a follow-up scan. The scanner drains its output before waiting for exit and has a five-second watchdog.

Rows are sorted by port, then PID. IPv4/IPv6 sockets belonging to the same PID and port become one row. Different processes sharing a port remain separate. The UI filters the raw snapshot to development server candidates owned by the current user. UDP and non-listening TCP connections are excluded.

Automatic discovery has **no port-number restriction**. It recognizes server runtimes (Node, Bun, Deno, Python, Ruby, PHP, Java, .NET, and common server commands) on any TCP listening port, including dynamically assigned high ports. Custom binaries outside system paths and desktop application bundles are shown when their working directory provides project evidence (`package.json` or a repository boundary). Runtimes embedded in an IDE are supported. Control Center, Figma helpers, rapportd, sharingd, and desktop app helpers stay excluded from automatic discovery. This remains a heuristic: a listener alone cannot establish whether a process is a development server or hung.

Click the **sliders button** in the header (or **⌘,**) for Discovery settings:

- **Detect dev servers on any port:** enabled by default. Turn it off to use only your explicit includes.
- **Always include ports:** add individual ports or ranges, e.g. `12345, 20000-20100`. This can explicitly show any listener you own, including an unrecognized server or an application helper. An included port is shown only while something is actually listening on it.
- **Always hide ports:** suppress noisy listeners even if automatically detected or explicitly included. Hide rules take priority.

Save validates ports against 1–65535 and rejects reversed ranges. Empty fields add no restrictions. Rules persist across restarts and take effect with a fresh snapshot. Ownership restrictions still apply. The policy lives in `DevelopmentPortFilter` and `DiscoverySettings` under `Kill9/Core`.

**Stop** sends SIGTERM to the selected process, affecting all ports it owns. After 1.2 seconds, the list refreshes. If that same process is still listening, **Force** becomes available and sends SIGKILL only when clicked. This is a process operation; closing just one port of an arbitrary application is not possible. A supervisor may restart a stopped service under a new PID, which appears on the next refresh.

The app rechecks process owner and start time immediately before signaling, rejecting stale identities and reducing PID-reuse risk. This check and the signal are separate OS calls, so they are not atomic. PID 1, Kill9 itself, and processes owned by other users cannot be stopped or explicitly included. Listeners whose process identity cannot be inspected are hidden. No sudo, elevated helper, or interpolated shell commands are used.

## Architecture

Rows show the project's `package.json` **name** when available, with runtime and PID on the second line. Hover the project name for its full name and directory. Kill9 reads the listener's actual working directory via `proc_pidinfo`, then checks up to 12 ancestors for the nearest package. It stops at repository boundaries, respects monorepo workspace packages, and avoids mistaking `node_modules` packages for the project. When metadata is missing, malformed, unnamed, or larger than 256 KiB, it uses the project folder name. If process inspection is unavailable, it keeps the original runtime name. Python/Go/Rust projects without `package.json` use their folder/repository name.

Project inspection runs on the scan worker and resolves each process/directory once per snapshot. Reopening or refreshing rereads metadata, so renamed projects are reflected without restarting Kill9. It never runs package scripts, reads process environment variables, or sends requests to the service. If a server changes its working directory away from its project, the automatic name may be unavailable or inferred from that different directory.

Name tooltips explicitly distinguish **Name from package.json**, **Folder name (inferred)**, and **Project folder selected by you**. Unidentified projects retain their process name. To correct a name, **right-click a server → Choose Project Folder…**. The chosen folder's own package name (or its folder name) is used. Choose **Use Detected Project** to clear the correction. Folder choices persist, scoped to the runtime, original working directory, and port rather than an unstable PID or a global port-only mapping. If the folder is removed, automatic detection is used again. Choosing a folder requires access to the listener's working directory; it is disabled when macOS does not expose that context. A previously selected mapping may need updating if you reuse the exact same runtime, working directory, and port for a different project.

| File | Responsibility |
| --- | --- |
| `Kill9/main.swift` | AppKit lifecycle without SwiftUI window scenes |
| `Kill9/AppDelegate.swift` | NSStatusItem, transient NSPopover, explicit size updates |
| `Kill9/PortStore.swift` | Main-actor UI state and asynchronous refresh/stop coordination |
| `Kill9/Core/PortService.swift` | Background lsof execution and process signals |
| `Kill9/Core/Listener.swift` | Process identity, field parser, stable row IDs, list geometry |
| `Kill9/Core/ProjectResolver.swift` | Process working directory, nearest package name, folder fallback |
| `Kill9/Core/DiscoverySettings.swift` | Persistent include/hide rules, automatic mode, port validation |
| `Kill9/UI/DiscoveryPreferencesView.swift` | Inline discovery settings without an additional window scene |
| `Kill9/UI/VisualEffectView.swift` | Native popover material and system appearance |
| `Kill9/UI/PopoverView.swift` | 290pt canvas, header, lazy list, scroll threshold, footer |
| `Kill9/UI/PortRow.swift` | 46pt row, contextual actions, focus and accessibility |
| `Kill9/Info.plist` | `LSUIElement = YES` (Application is agent) |

The supplied visual specification is saved in `DESIGN_SPEC.md`. This workspace contained no existing Swift logic; the core implementation was created from the requirements in the request.

## Validation

```sh
swift test
```

The Swift package tests the same core source files compiled into the app. Coverage includes parsing and deduplication, malformed data, the six/seven-row scroll threshold, discovery of a real local listening socket, arbitrary/high-port detection, include/hide precedence and validation, saved settings, project-folder corrections and their scope, SIGTERM/SIGKILL against disposable owned child processes, and refusal of stale/self/system identities. Tests never stop an existing developer service.

Manual UI checks: open and dismiss the popover, check fresh listeners on reopening, hover and keyboard-focus Stop, check Light/Dark appearance and Reduce Transparency, and populate seven or more listener rows to verify scrolling. The automated core tests do not validate native vibrancy or rendered layout.

Native API references: [NSPopover](https://developer.apple.com/documentation/appkit/nspopover), [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem).
