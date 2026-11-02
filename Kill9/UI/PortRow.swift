import SwiftUI

struct PortRow: View {
    let listener: Listener
    let isStopping: Bool
    let canForce: Bool
    let stop: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @FocusState private var actionFocused: Bool

    private var showAction: Bool { isHovered || actionFocused || canForce }

    var body: some View {
        HStack(spacing: 8) {
            Text(String(listener.port))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 24)
                .background(Color.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.15),
                            in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(listener.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(listener.detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(listener.helpText)

            if isStopping {
                ProgressView().controlSize(.small).frame(width: 51)
            } else if listener.canTerminate {
                Button(canForce ? "Force" : "Stop", action: stop)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .frame(width: 51, height: 23)
                    .background(destructiveColor, in: RoundedRectangle(cornerRadius: 5))
                    .focused($actionFocused)
                    .opacity(showAction ? 1 : 0)
                    .allowsHitTesting(showAction)
                    .help(canForce ? "Force quit \(listener.displayName) (SIGKILL)" : "Stop \(listener.displayName) (SIGTERM)")
                    .accessibilityLabel("\(canForce ? "Force quit" : "Stop") \(listener.displayName), \(listener.command), port \(listener.port), PID \(listener.pid)")
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 51)
                    .help("This process is protected or belongs to another user.")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: ListGeometry.rowHeight)
        .background(Color.primary.opacity(isHovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: actionFocused)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(canForce ? "Force quit" : "Stop")) {
            if listener.canTerminate && !isStopping { stop() }
        }
    }

    private var destructiveColor: Color {
        colorScheme == .dark
            ? Color(red: 1, green: 69 / 255, blue: 58 / 255)
            : Color(red: 1, green: 59 / 255, blue: 48 / 255)
    }
}
