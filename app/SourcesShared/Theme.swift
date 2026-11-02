import SwiftUI

/// StremioX design system. One source of truth for color, type, spacing, motion, and the focus
/// treatment, so every tvOS screen reads as one product at ten feet. See DESIGN.md for the rationale.
/// Direction: editorial cinema. Warm near-black chrome so poster art is the only color on screen,
/// one ember accent that means focus / selection / primary / progress, nothing decorative colored.
enum Theme {

    // MARK: Color (warm-neutral chrome + a single ember accent)

    enum Palette {
        private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
        }
        // Chrome is user-themeable via ThemeManager (warm near-black by default, true black on OLED).
        static var canvas: Color   { ThemeManager.shared.canvas }   // app background
        static var surface1: Color { ThemeManager.shared.surface1 } // rows, cards, panels
        static var surface2: Color { ThemeManager.shared.surface2 } // chips, controls
        static var surface3: Color { ThemeManager.shared.surface3 } // hover / selected fill
        static var hairline: Color { ThemeManager.shared.hairline } // dividers only
        static var textPrimary: Color   { ThemeManager.shared.textPrimary }
        static var textSecondary: Color { ThemeManager.shared.textSecondary }
        static var textTertiary: Color  { ThemeManager.shared.textTertiary }
        // Accent is user-themeable via ThemeManager (8 curated accents). accentSoft / onAccent follow it.
        static var accent: Color { ThemeManager.shared.accent }             // focus / selection / primary / progress
        static var accentBright: Color { ThemeManager.shared.accentBright } // focus glow highlight
        static var accentSoft: Color { accent.opacity(0.18) }
        static var onAccent: Color { ThemeManager.shared.onAccent } // accent-adaptive ink (was a fixed warm-brown that read orange on every accent)
        static let danger = rgb(0.871, 0.282, 0.337)            // #DE4856 destructive (log out, remove) — a cooler red so it doesn't read as "leftover orange" next to a non-warm accent
    }

    // MARK: Spacing (8pt base, intentional rhythm)

    enum Space {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 20
        static let lg: CGFloat = 32
        static let xl: CGFloat = 48
        static let xxl: CGFloat = 72
        // 10-foot tvOS screen inset. Do NOT use this directly as horizontal padding on shared views
        // that also render on iPhone — 60pt eats ~120pt of a 390pt phone and clips content off the
        // edges (the beta7 server-config / add-ons clipping). Use `screenInset` instead.
        static let screenEdge: CGFloat = 60
        // Platform-aware screen inset: the tvOS 10-foot value on TV, an arm's-length value on
        // phone / iPad / Mac. Shared screens (ServerConfig, Add-ons, Profiles) use this so one token
        // keeps tvOS spacious without clipping the phone.
        #if os(tvOS)
        static let screenInset: CGFloat = screenEdge
        #else
        static let screenInset: CGFloat = md
        #endif
    }

    enum Radius {
        static let card: CGFloat = 20
        static let heroCard: CGFloat = 36
        static let chip: CGFloat = 14
        static let control: CGFloat = 14
    }

    // MARK: Motion

    enum Motion {
        static let focus = Animation.easeOut(duration: 0.25)
        static let state = Animation.easeOut(duration: 0.18)
    }

    // MARK: Typography (system only: New York serif for editorial moments, SF Pro for UI)

    /// Every size is a computed `static var` that multiplies by the LIVE text scale from
    /// ThemeManager (Settings → Appearance → App text size). Because each screen observes
    /// ThemeManager (`@EnvironmentObject theme`), changing the scale fires the manager's
    /// `objectWillChange`, those screens re-evaluate `body`, and these getters re-run against the
    /// new `textScale` — so the app repaints instantly, the same way the accent does, no relaunch.
    ///
    /// IMPORTANT reactivity contract: reading `Theme.Typography.*` does NOT by itself subscribe a
    /// view to text-size changes (the read goes through `ThemeManager.shared`, not the view's
    /// observed reference). A view (or its nearest observing ancestor) must hold
    /// `@EnvironmentObject theme: ThemeManager` for its fonts to repaint live. On iOS/Mac the
    /// browse, detail, player, and Settings screens all declare it; tvOS screens already did, which
    /// is why text size worked there but not on iOS/Mac (#48).
    enum Typography {
        private static func scaled(_ size: CGFloat) -> CGFloat {
            // Base sizes are tvOS 10-foot dimensions. On phone / iPad / Mac, viewed at arm's length,
            // those render far too large, so scale the base down to 62% before applying the user's
            // live textScale. tvOS keeps the full base. (Root cause of the "text too big" report.)
            #if os(tvOS)
            let base = size
            #else
            let base = size * 0.62
            #endif
            return (base * CGFloat(ThemeManager.shared.textScale)).rounded()
        }
        static var hero: Font        { .system(size: scaled(64), weight: .heavy, design: .default) }
        static var wordmark: Font    { .system(size: scaled(36), weight: .bold, design: .default) }
        static var screenTitle: Font { .system(size: scaled(52), weight: .heavy, design: .default) }
        static var sectionTitle: Font { .system(size: scaled(30), weight: .bold, design: .default) }
        static var cardTitle: Font   { .system(size: scaled(22), weight: .semibold, design: .default) }
        static var body: Font        { .system(size: scaled(24), weight: .regular, design: .default) }
        static var label: Font       { .system(size: scaled(20), weight: .medium, design: .default) }
        static var eyebrow: Font     { .system(size: scaled(15), weight: .bold, design: .default) }
    }
}

// MARK: - Text role helpers (font + tracking + default color in one place)

extension View {
    func eyebrowStyle(_ color: Color = Theme.Palette.textTertiary) -> some View {
        font(Theme.Typography.eyebrow).tracking(1.5).textCase(.uppercase).foregroundStyle(color)
    }
    func sectionTitleStyle() -> some View {
        font(Theme.Typography.sectionTitle).tracking(-0.3).foregroundStyle(Theme.Palette.textPrimary)
    }
    func screenTitleStyle() -> some View {
        font(Theme.Typography.screenTitle).tracking(-1).foregroundStyle(Theme.Palette.textPrimary)
    }
}

// MARK: - Focus treatment (the core tvOS interaction)

/// Crafted card focus: scale + lift + warm ember glow, spring-eased, Reduce-Motion aware.
/// Reads `isFocused` from the enclosing Button (the nearest focusable ancestor).
struct CardFocusStyle: ButtonStyle {
    var scale: CGFloat = 1.08
    func makeBody(configuration: Configuration) -> some View {
        CardFocusContent(configuration: configuration, scale: scale)
    }
}

private struct CardFocusContent: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var theme: ThemeManager   // observe so a theme change repaints this style
    #if os(macOS)
    @State private var isHovered = false   // Mac has no focus engine for cards; pointer hover drives the same lift
    #endif
    var body: some View {
        // On Mac, treat pointer hover as the focus signal so cards light up under the cursor;
        // iOS/tvOS keep using the focus engine (`focused`) untouched.
        #if os(macOS)
        let active = focused || isHovered
        #else
        let active = focused
        #endif
        let lifted = active && !reduceMotion
        let label = configuration.label
            .scaleEffect(lifted ? scale : (configuration.isPressed ? 0.97 : 1))
            .shadow(color: lifted ? Color.black.opacity(0.8) : Color.clear, radius: 24, x: 0, y: 14)
            .animation(reduceMotion ? nil : Theme.Motion.focus, value: active)
            .animation(Theme.Motion.state, value: configuration.isPressed)
        #if os(macOS)
        return label.onHover { isHovered = $0 }
        #else
        return label
        #endif
    }
}

/// Primary action (play / resume): ember fill, brighten + scale on focus.
struct PrimaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryActionContent(configuration: configuration)
    }
}

private struct PrimaryActionContent: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var theme: ThemeManager   // observe so a theme change repaints this style
    #if os(macOS)
    @State private var isHovered = false   // Mac drives the same brighten/scale/glow from pointer hover
    #endif
    var body: some View {
        // On Mac, pointer hover stands in for the focus engine; iOS/tvOS keep using `focused`.
        #if os(macOS)
        let active = focused || isHovered
        #else
        let active = focused
        #endif
        let label = configuration.label
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.onAccent)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.md)
            .background(active ? Theme.Palette.accentBright : Theme.Palette.accent,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .scaleEffect(active && !reduceMotion ? 1.06 : (configuration.isPressed ? 0.97 : 1))
            .animation(reduceMotion ? nil : Theme.Motion.focus, value: active)
        #if os(macOS)
        return label.onHover { isHovered = $0 }
        #else
        return label
        #endif
    }
}

// Chips live in ChipButtonStyle.swift (its API is used across 12 call sites).

/// List row (stream, episode, addon): a surface card that brightens and gains an ember ring on focus.
struct RowFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowFocusContent(configuration: configuration)
    }
}

private struct RowFocusContent: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var theme: ThemeManager   // observe so a theme change repaints this style
    #if os(macOS)
    @State private var isHovered = false   // Mac drives the same fill/ring/lift from pointer hover
    #endif
    var body: some View {
        // On Mac, pointer hover stands in for the focus engine; iOS/tvOS keep using `focused`.
        #if os(macOS)
        let active = focused || isHovered
        #else
        let active = focused
        #endif
        let label = configuration.label
            .background(active ? Theme.Palette.surface2 : Theme.Palette.surface1,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.accent, lineWidth: active ? 3 : 0)
            )
            .scaleEffect(active && !reduceMotion ? 1.015 : (configuration.isPressed ? 0.99 : 1))
            .animation(reduceMotion ? nil : Theme.Motion.focus, value: active)
        #if os(macOS)
        return label.onHover { isHovered = $0 }
        #else
        return label
        #endif
    }
}

// MARK: - Native Apple Liquid Glass & Frost Material
extension View {
    @ViewBuilder
    func liquidGlassBackground(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        // Liquid Glass / live blur is strictly guarded on Apple TV HD (PerformanceMode.reduced) to prevent severe GPU overdraw stutter
        if AppSettings.shared.liquidGlass && !PerformanceMode.reduced {
            self.background(
                ZStack {
                    // 1. Native tvOS frosted material blur
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // 2. Specular top-lit ambient sheen (Apple glass lighting)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.02),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    // 3. Specular rim highlight border (crisp top reflection, fading to soft bottom)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Color.black.opacity(0.28), radius: 16, x: 0, y: 8)
            )
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.Palette.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
}
