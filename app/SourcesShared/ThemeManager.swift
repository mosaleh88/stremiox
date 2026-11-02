import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private func themeRGB(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
}

/// A selectable accent. `base` recolors focus / selection / primary / progress everywhere;
/// `bright` is the focus-glow peak.
struct AccentOption: Identifiable {
    let id: String
    let label: String
    let base: Color
    let bright: Color
}

/// The user-chosen theme (accent + chrome), persisted to `UserDefaults` and applied through
/// `Theme.Palette`, which reads `ThemeManager.shared`. The top-level screens observe this object so a
/// change repaints the app live, without a `.id` rebuild that would drop focus mid-pick.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var accentID: String { didSet { UserDefaults.standard.set(accentID, forKey: Self.accentKey) } }
    @Published var oled: Bool { didSet { UserDefaults.standard.set(oled, forKey: Self.oledKey) } }
    /// UI text scale, 0.80 to 1.40. @Published so a change repaints the whole app LIVE (every screen
    /// that observes ThemeManager), the same path the accent uses; Theme.Typography reads it per
    /// render via `Theme.scaled`. Static-let typography never updated because tvOS "Restart App"
    /// can't relaunch the process, so the frozen sizes stuck.
    ///
    /// The setter explicitly fans `objectWillChange` out FIRST and clamps in one place, so a write
    /// from any path (the iOS Stepper's `$theme.textScale` binding, the tvOS +/- buttons via
    /// `adjustTextScale`, a profile switch via `applyTheme`) invalidates observers deterministically.
    /// Reading `textScale` through `Theme.Typography` alone does NOT subscribe a view — a view must
    /// observe ThemeManager (`@EnvironmentObject theme`) for its fonts to repaint on change.
    @Published var textScale: Double {
        didSet {
            let clamped = min(max(textScale, Self.textScaleRange.lowerBound), Self.textScaleRange.upperBound)
            // Re-entrancy guard: only correct out-of-range writes (clamping fires didSet once more,
            // then the value already equals `clamped` and we stop), never loop on an in-range write.
            if clamped != textScale { textScale = clamped; return }
            UserDefaults.standard.set(textScale, forKey: Self.textScaleKey)
        }
    }

    static let textScaleRange: ClosedRange<Double> = 0.80...1.40
    static let textScaleStep: Double = 0.05

    private static let accentKey = "stremiox.theme.accent"
    private static let oledKey = "stremiox.theme.oled"
    private static let textScaleKey = "stremiox.theme.textScale"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let savedAccent = UserDefaults.standard.string(forKey: Self.accentKey)
        accentID = (savedAccent == nil || savedAccent == "ember" || savedAccent == "ocean") ? "apple" : savedAccent!
        oled = UserDefaults.standard.bool(forKey: Self.oledKey)
        let saved = UserDefaults.standard.object(forKey: Self.textScaleKey) as? Double
        textScale = saved.map { min(max($0, Self.textScaleRange.lowerBound), Self.textScaleRange.upperBound) } ?? 1.0

        AppSettings.shared.$appearanceMode
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    var isLight: Bool {
        switch AppSettings.shared.appearanceMode {
        case .light: return true
        case .dark: return false
        case .auto:
            #if canImport(UIKit)
            return UIScreen.main.traitCollection.userInterfaceStyle == .light
            #else
            return false
            #endif
        }
    }

    var textPrimary: Color {
        isLight ? themeRGB(0.08, 0.08, 0.09) : themeRGB(0.965, 0.945, 0.914)
    }

    var textSecondary: Color {
        isLight ? themeRGB(0.38, 0.38, 0.42) : themeRGB(0.737, 0.694, 0.631)
    }

    var textTertiary: Color {
        isLight ? themeRGB(0.55, 0.55, 0.60) : themeRGB(0.620, 0.580, 0.520)
    }

    /// Nudge the text scale one step within range (the tvOS Settings +/- buttons; the iOS Settings
    /// Stepper writes `$theme.textScale` directly). Rounds to whole percent; the `textScale` setter
    /// clamps to range and publishes, so observers repaint live.
    func adjustTextScale(_ direction: Int) {
        let next = textScale + Double(direction) * Self.textScaleStep
        textScale = (next * 100).rounded() / 100
    }

    /// Pure Apple TV default monochrome design + optional accents
    static let accents: [AccentOption] = [
        AccentOption(id: "apple",   label: "Apple TV",  base: Color.white, bright: Color.white),
        AccentOption(id: "mono",    label: "Mono",      base: themeRGB(0.820, 0.800, 0.761), bright: themeRGB(0.922, 0.910, 0.882)),
        AccentOption(id: "ocean",   label: "Cupertino", base: themeRGB(0.040, 0.520, 1.000), bright: themeRGB(0.220, 0.680, 1.000)),
        AccentOption(id: "ember",   label: "Ember",     base: themeRGB(0.949, 0.471, 0.294), bright: themeRGB(1.000, 0.569, 0.388)),
    ]

    private var option: AccentOption { Self.accents.first { $0.id == accentID } ?? Self.accents[0] }

    var accent: Color { option.base }
    var accentBright: Color { option.bright }

    var onAccent: Color {
        if accentID == "apple" { return Color.black }
        if accentID == "ember" { return themeRGB(0.106, 0.067, 0.043) }
        return accentLuminance > 0.5 ? Color.black : Color.white
    }

    /// Perceived (Rec. 709) luminance of the current accent, for picking the on-accent ink.
    private var accentLuminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(accent).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        // Guard the sRGB conversion (matches tintedDark): without it a nil conversion leaves r/g/b at
        // 0, luminance reads 0, and every macOS accent would wrongly get the near-white ink.
        guard let srgb = NSColor(accent).usingColorSpace(.sRGB) else { return 0.55 }   // mid → neutral-dark ink
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }

    // Chrome: support Dark (warm near-black/OLED) and Light (Apple TV white), or system auto
    var canvas: Color   { isLight ? themeRGB(0.95, 0.95, 0.97) : (oled ? themeRGB(0, 0, 0)             : tintedDark(0.085)) }
    var surface1: Color { isLight ? themeRGB(1.0, 1.0, 1.0)     : (oled ? themeRGB(0.055, 0.055, 0.057) : tintedDark(0.130)) }
    var surface2: Color { isLight ? themeRGB(0.90, 0.90, 0.93) : (oled ? themeRGB(0.094, 0.094, 0.098) : tintedDark(0.175)) }
    var surface3: Color { isLight ? themeRGB(0.84, 0.84, 0.88) : (oled ? themeRGB(0.141, 0.141, 0.149) : tintedDark(0.225)) }
    var hairline: Color { isLight ? themeRGB(0.80, 0.80, 0.84) : (oled ? themeRGB(0.196, 0.196, 0.204) : tintedDark(0.260)) }

    /// Pure neutral dark surfaces matching Apple TV (no color tinting)
    private func tintedDark(_ brightness: Double) -> Color {
        themeRGB(brightness, brightness, brightness)
    }
}
