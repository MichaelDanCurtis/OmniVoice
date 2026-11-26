import AppKit
import SwiftUI
import OmniVoiceCore

/// Persistent bottom action bar shown while macOS Accessibility permission is not yet granted.
/// Provides a draggable `OmniSpeak.app` tile that users can drag directly into
/// System Settings → Privacy & Security → Accessibility, alongside one-click Settings & Reset buttons.
struct AccessibilityDragBar: View {
    let theme: OmniVoiceTheme
    let openSettings: () -> Void
    let resetPermission: () -> Void

    @State private var isHoveringDragTile = false
    @Environment(\.colorScheme) private var colorScheme

    private var appBundleURL: URL {
        Bundle.main.bundleURL
    }

    private var appIconImage: NSImage {
        NSApp.applicationIconImage ?? NSWorkspace.shared.icon(forFile: appBundleURL.path)
    }

    var body: some View {
        let accent = Color.orange
        let barShape = RoundedRectangle(cornerRadius: theme.look.cardRadius(forRequested: 14), style: .continuous)
        let tileRadius = theme.look.cardRadius(forRequested: 11)
        let tileShape = RoundedRectangle(cornerRadius: tileRadius, style: .continuous)

        HStack(spacing: 12) {
            draggableAppTile(accent: accent, tileShape: tileShape)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                    Text("Accessibility Required")
                        .font(.callout.weight(.semibold))
                        .fontDesign(theme.look.headerFontDesign)
                }

                Text("Click Open Settings, then drag the OmniSpeak tile on the left straight into the Accessibility list.")
                    .font(.caption)
                    .fontDesign(theme.look.bodyFontDesign)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button {
                    openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape.fill")
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .tint(accent)

                Button {
                    resetPermission()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .help("Reset stale Accessibility entry (tccutil) and reopen System Settings")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            barShape
                .fill(accent.opacity(colorScheme == .dark ? 0.12 : 0.09))
                .overlay {
                    barShape.stroke(
                        accent.opacity(colorScheme == .dark ? 0.42 : 0.36),
                        lineWidth: max(1, theme.look.strokeWidth)
                    )
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func draggableAppTile(accent: Color, tileShape: RoundedRectangle) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent.opacity(0.85))

            Image(nsImage: appIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("OmniSpeak")
                    .font(.caption.weight(.bold))
                    .fontDesign(theme.look.headerFontDesign)
                    .foregroundStyle(.primary)
                Text("Drag me →")
                    .font(.caption2.weight(.semibold))
                    .fontDesign(theme.look.bodyFontDesign)
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            tileShape.fill(
                colorScheme == .dark
                    ? Color.white.opacity(isHoveringDragTile ? 0.12 : 0.07)
                    : Color.white.opacity(isHoveringDragTile ? 0.96 : 0.82)
            )
        )
        .overlay {
            tileShape.stroke(
                accent.opacity(isHoveringDragTile ? 0.85 : 0.45),
                style: StrokeStyle(lineWidth: isHoveringDragTile ? 1.5 : 1.1, dash: isHoveringDragTile ? [] : [4, 3])
            )
        }
        .scaleEffect(isHoveringDragTile ? 1.02 : 1.0)
        .animation(.snappy(duration: 0.16), value: isHoveringDragTile)
        .contentShape(tileShape)
        .draggable(appBundleURL) {
            HStack(spacing: 8) {
                Image(nsImage: appIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("OmniSpeak.app")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .onHover { hovering in
            isHoveringDragTile = hovering
            if hovering {
                NSCursor.openHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHoveringDragTile {
                isHoveringDragTile = false
                NSCursor.pop()
            }
        }
        .help("Drag and drop OmniSpeak onto System Settings → Privacy & Security → Accessibility")
    }
}
