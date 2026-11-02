# Kill9: Design System & User Interface Specification

## Core visual pillars

- Native macOS frosted glass using `NSVisualEffectView`, inheriting system Light/Dark appearance.
- Hyper-compact process rows; contextual actions and no filler text.
- Hover transitions: 0.15 seconds, ease-out.

## Color and typography

| Element | Light | Dark | Font |
| --- | --- | --- | --- |
| Branding | Primary → secondary gradient | Primary → secondary gradient | Impact wordmark, 17pt |
| Port badge fill | Control accent, 15% | Control accent, 20% | System monospaced, bold, 11pt |
| Port badge text | Control accent | Control accent | System monospaced, bold, 11pt |
| Hover background | Primary black, 5% | Primary white, 5% | — |
| Destructive button | #FF3B30 | #FF453A | 10pt bold, white |
| Process name | Primary | Primary | System regular, 12pt, single-line tail truncation |
| PID | Secondary | Secondary | System monospaced, 10pt |

## Geometry

- Outer canvas: `VStack(spacing: 0)`, no explicit outer padding, low-opacity dividers.
- Fixed width: 290pt.
- Each row: 46pt, with horizontal 8pt and vertical 6pt internal padding.
- List height: `min(rows * 46 + 16, 300)`; the additional 16pt is vertical list inset.
- Up to six rows: intrinsic list. Seven or more: encapsulated vertical `ScrollView`, 300pt high.
- The 300pt ceiling applies to the list; header, footer, and an optional error message sit outside it.

## Interaction

- Opening the transient status-item popover starts a fresh background TCP LISTEN snapshot.
- Automatically discover recognized runtimes and project-backed custom servers on any port; hide system services and desktop app helpers by default. Empty state: “No matching dev servers”. Footer: dev port count.
- Use the nearest `package.json` project name as the row title, falling back to its project folder, then runtime. Keep runtime and PID on the secondary line, and show full name/directory on hover. Retain the 46pt row and 290pt canvas.
- Header sliders button (⌘,) opens inline Discovery settings: automatic mode, persisted include ports/ranges, and hide ports/ranges. Hide takes priority. Explicit includes can opt user-owned helpers into the list. Validate the full 1–65535 range before saving.
- Name tooltips identify metadata names versus inferred folder names. A row context menu offers “Choose Project Folder…” and “Use Detected Project” for saved corrections. The folder chooser is a native directory panel; no additional SwiftUI window scene is introduced.
- Normal stop sends SIGTERM. If the same process is still listening after the grace interval, offer an explicit Force action (SIGKILL).
- Stop appears on hover or keyboard focus; VoiceOver also exposes a named action.
- A pending force action stays visible to distinguish it from a normal stop.
- Refresh: ⌘R. Quit: ⌘Q. Outside click/Escape dismiss the native transient popover.

## Branding

- Menu bar: Impact “KILL9” as a 34×18pt template image in a variable-width status item. Center its visible glyph bounds, with a maximum 30pt width and 12pt height; use a heavy system font fallback. Native template tint follows menu bar appearance and selection.
- Popover header: “KILL9” in Impact, 17pt, using the primary-to-secondary text gradient and no symbol.
- App icon: supplied black-and-white artwork.
