# Design (Xtv)

The visual system for Xtv on tvOS, redesigned to look and feel like the Apple TV app on tvOS 26 while running smoothly on Apple TV HD (4th generation, A8 chip, 2 GB RAM, 1080p SDR output).

## Theme

Dark, warm, and cinematic. The canvas is a deep warm near-black (`#15120E`) so poster art is the only saturated element on screen. Elevation is expressed by stepping lightness up on warm-tinted surfaces and by focused card lift, never by live translucent blur stacks on constrained hardware.

## Apple TV HD (A8) Hardware Optimization Rules

- **Zero Liquid Glass / Live Blur on HD:** Liquid Glass APIs (`.ultraThinMaterial`, `liquidGlassBackground`) are guarded and fall back to solid dark fills (`Theme.Palette.surface1` @ 96%).
- **SDR Output (No HDR / DV switching):** Apple TV HD is strictly 1080p SDR. HDMI dynamic range mode-switching (`HDRDisplayMode.request`) is bypassed when `PerformanceMode.reduced` is true.
- **Demuxer Read-Ahead Buffer:** Reduced from 512 MiB to 128 MiB (remote CDN/debrid) and 48 MiB (local torrent) to prevent jetsam OOM kills on 2 GB RAM.
- **Asynchronous Artwork Downsampling:** Remote poster artwork is loaded and downsampled off the main thread to 1080p display sizes (2x pixel density max) with an in-memory `NSCache` limit.
- **Focused-Only Shadows:** Inactive/resting cards have 0 drop shadow and 0 border strokes; only the single focused card receives the 1.08x scale, drop shadow, and theme accent glow.
- **Single Shared Hero Trailer Player:** A single shared AVPlayer instance handles backdrop trailers with a 1.8s dwell delay, capped at 720p SDR with a 4.0s forward buffer, tearing down immediately on navigation, backgrounding, or memory warning.

## Navigation & Sidebar (Apple TV 26 Style)

- **Left Sidebar:** Native left sidebar panel (`SidebarView`) with user profile avatar, username, and live 1s clock at top. Items show circular icons and labels (Search, Home, Discover, Live TV, Library, Add-ons, Settings). Solid dark semi-opaque fill (`#15120E` @ 96%) without live blurs.
- **Top-left Home Navigation:** Small translucent "Home" / tab pill with back chevron (`< Home`) at the top-left of the viewport. Siri Remote Menu button (`.onExitCommand`) cleanly pops back to the sidebar and Home.

## Color

Strategy: **Restrained**. Warm-neutral monochrome chrome plus one accent. The accent means focus, current selection, primary action, and progress. Nothing decorative is colored.

Neutrals (warm, hue ~60, very low chroma):

| Token | OKLCH intent | sRGB hex | Use |
|---|---|---|---|
| `canvas` | 14% 0.008 60 | `#15120E` | App background |
| `surface1` | 19% 0.009 60 | `#211C16` | Rows, cards, panels |
| `surface2` | 24% 0.010 60 | `#2D261D` | Chips, controls, elevated |
| `surface3` | 30% 0.011 60 | `#3A3127` | Hover / selected fill |
| `hairline` | 32% 0.010 60 | `#403629` | 1px separators only |
| `textPrimary` | 96% 0.006 75 | `#F6F1E9` | Titles, primary text |
| `textSecondary` | 76% 0.012 75 | `#BCB1A1` | Secondary text, labels |
| `textTertiary` | 56% 0.012 75 | `#8C8273` | Captions, disabled |

Accent (ember / warm coral, hue ~38):

| Token | OKLCH intent | sRGB hex | Use |
|---|---|---|---|
| `accent` | 72% 0.16 38 | `#F2784B` | Focus ring, selection, primary action, progress fill |
| `accentBright` | 78% 0.15 45 | `#FF9163` | Focus glow highlight |
| `accentSoft` | accent @ 18% alpha | rgba | Selected-chip fill, glow base |

Semantic: destructive uses the system red (`#DE4856`).

## Typography

Two families, both system (no bundled fonts, zero load risk):

- **Display (editorial moments only)**: SF Pro Rounded is avoided; use the system serif **New York** (`Font.system(..., design: .serif)`) at heavy/bold for the wordmark and the detail-page hero title.
- **UI (everything else)**: **SF Pro** (`design: .default`). Carries section headers, card titles, body, labels, data.

Scale (tvOS, fixed, ratio ~1.25), defined as `Theme.Font` helpers:

| Role | Size / weight / tracking | Family |
|---|---|---|
| `hero` | 64 heavy, tracking -1.5 | serif |
| `wordmark` | 40 bold, tracking -0.5 | serif |
| `screenTitle` | 52 heavy, tracking -1 | sans |
| `sectionTitle` | 30 semibold, tracking -0.3 | sans |
| `cardTitle` | 22 semibold | sans |
| `body` | 24 regular, line height 1.4 | sans |
| `label` | 20 medium | sans |
| `eyebrow` | 15 bold, tracking +1.5, uppercase | sans |

## Radius & Elevation

- Radius: `card 20`, `heroCard 36`, `chip 14`, `control 14`.
- Elevation: Active focused card lifts to (y 14, blur 24, black 80%) plus accent glow. Resting cards have zero shadow on HD.
- Specular rim highlight border (`Color.white`, width 3.5) renders strictly on focus.

## Components & Rails

- **Full-Bleed Hero**: 1920×780 hero banner with left and bottom dark gradient scrims, left-aligned stacked info block, white pill Play button, bottom-right page dots, and auto-rotation with Reduce Motion support.
- **Continue Watching Rail**: 380×214 landscape cards with source badge, remaining time indicator, and 4pt progress bar.
- **Ranked Charts Rail**: Large gradient rank numbers (1 to 10) in the corner of each 2:3 card, backed by `LazyHStack`.
- **Curated Feature Rail**: 240×360 portrait cards with bottom title/genre scrim, optional "NEW" badge, and 1.5s dwell trailer.
- **Detail Page**: Single static dominant-color gradient backdrop (extracted once via `DominantColorExtractor`), metadata format badges (HD, CC, LIVE), season chips, and horizontal `LazyHStack` episode cards with high-contrast focused backplates.

## Motion

- Focus: 250ms ease-out on scale and lift (`Theme.Motion.focus`).
- State changes: 180ms ease-out.
- Reduce Motion: disables auto-rotation, trailer playback, title parallax, and scales.
- Only transform and opacity animations; never animate layout dimensions.
