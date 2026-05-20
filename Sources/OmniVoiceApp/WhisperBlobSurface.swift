import SwiftUI

struct WhisperBlobSurface: ViewModifier {
    let accent: Color
    let secondary: Color
    let tint: Color
    let fillOpacity: Double
    let materialOpacity: Double
    let edgeOpacity: Double
    let highlightOpacity: Double
    let depthOpacity: Double
    let innerRimOpacity: Double
    let glowOpacity: Double
    let shadowOpacity: Double
    let edgeBlurRadius: CGFloat
    let edgeBleed: CGFloat
    let interactive: Bool
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(tint.opacity(fillOpacity))
                        .interactive(interactive),
                    in: shape
                )
                .background {
                    glassCore
                }
                .overlay {
                    glassRim
                }
                .overlay {
                    ghostEdge
                        .padding(-edgeBleed)
                }
                .shadow(color: accent.opacity(glowOpacity), radius: 16, x: 0, y: 8)
                .whisperMotion(accent: accent, strong: interactive, isHovering: isHovering, reduceMotion: reduceMotion)
                .onHover { isHovering = $0 }
        } else {
            content
                .background {
                    glassCore
                }
                .overlay {
                    glassRim
                }
                .overlay {
                    ghostEdge
                        .padding(-edgeBleed)
                }
                .shadow(color: accent.opacity(glowOpacity), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(shadowOpacity), radius: 28, x: 0, y: 16)
                .whisperMotion(accent: accent, strong: interactive, isHovering: isHovering, reduceMotion: reduceMotion)
                .onHover { isHovering = $0 }
        }
    }

    private var glassCore: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(materialOpacity)
            .overlay {
                Capsule(style: .continuous)
                    .fill(tint.opacity(fillOpacity))
            }
            .overlay {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(highlightOpacity),
                                Color.white.opacity(highlightOpacity * 0.22),
                                Color.clear,
                                secondary.opacity(highlightOpacity * 0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(depthOpacity),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.multiply)
            }
    }

    private var glassRim: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(innerRimOpacity),
                        accent.opacity(edgeOpacity),
                        secondary.opacity(edgeOpacity * 0.52),
                        Color.white.opacity(innerRimOpacity * 0.42),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .blur(radius: 0.25)
    }

    private var ghostEdge: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        accent.opacity(edgeOpacity),
                        secondary.opacity(edgeOpacity * 0.56),
                        Color.white.opacity(edgeOpacity * 0.32),
                        accent.opacity(edgeOpacity * 0.42),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: edgeBlurRadius > 3 ? 2.5 : 1
            )
            .blur(radius: edgeBlurRadius)
    }
}

extension View {
    func whisperBlobSurface(
        accent: Color,
        secondary: Color,
        tint: Color,
        fillOpacity: Double = 0.12,
        materialOpacity: Double = 1,
        edgeOpacity: Double = 0.16,
        highlightOpacity: Double = 0.10,
        depthOpacity: Double = 0.06,
        innerRimOpacity: Double = 0.14,
        glowOpacity: Double = 0.16,
        shadowOpacity: Double = 0.18,
        edgeBlurRadius: CGFloat = 0.4,
        edgeBleed: CGFloat = 0,
        interactive: Bool = false
    ) -> some View {
        modifier(
            WhisperBlobSurface(
                accent: accent,
                secondary: secondary,
                tint: tint,
                fillOpacity: fillOpacity,
                materialOpacity: materialOpacity,
                edgeOpacity: edgeOpacity,
                highlightOpacity: highlightOpacity,
                depthOpacity: depthOpacity,
                innerRimOpacity: innerRimOpacity,
                glowOpacity: glowOpacity,
                shadowOpacity: shadowOpacity,
                edgeBlurRadius: edgeBlurRadius,
                edgeBleed: edgeBleed,
                interactive: interactive
            )
        )
    }

    fileprivate func whisperMotion(
        accent: Color,
        strong: Bool,
        isHovering: Bool,
        reduceMotion: Bool
    ) -> some View {
        scaleEffect(isHovering && !reduceMotion ? (strong ? 1.01 : 1.005) : 1)
            .shadow(
                color: accent.opacity(isHovering && !reduceMotion ? (strong ? 0.16 : 0.08) : 0),
                radius: isHovering ? (strong ? 18 : 10) : 0,
                x: 0,
                y: isHovering ? (strong ? 8 : 4) : 0
            )
            .animation(.snappy(duration: 0.22), value: isHovering)
    }
}
