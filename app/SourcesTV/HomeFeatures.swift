import SwiftUI

// MARK: - White Pill Button Style (Apple TV Native Play Button)

struct WhitePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WhitePillButton(configuration: configuration)
    }

    private struct WhitePillButton: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(isFocused ? Color.white : Color.white.opacity(0.92))
                )
                .scaleEffect(isFocused && !reduceMotion ? 1.08 : (configuration.isPressed ? 0.96 : 1.0))
                .shadow(color: isFocused ? Color.black.opacity(0.6) : Color.clear, radius: 18, y: 8)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: isFocused)
        }
    }
}

// MARK: - Circle Glass Button Style (Apple TV Native)

struct CircleGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CircleGlassButton(configuration: configuration)
    }

    private struct CircleGlassButton: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .background(
                    Circle()
                        .fill(isFocused ? Color.white : Color.white.opacity(0.22))
                )
                .overlay(
                    Circle()
                        .strokeBorder(isFocused ? Color.white : Color.white.opacity(0.35), lineWidth: 1.5)
                )
                .scaleEffect(isFocused && !reduceMotion ? 1.15 : (configuration.isPressed ? 0.94 : 1.0))
                .shadow(color: isFocused ? Color.black.opacity(0.6) : Color.clear, radius: 14, y: 7)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: isFocused)
        }
    }
}

// MARK: - Apple TV+ Style "Up Next" / Hero Carousel

struct HeroCarouselItem: Identifiable {
    let id: String
    let type: String
    let title: String
    let subtitle: String?
    let overview: String?
    var backdropURL: URL?
    let posterURL: URL?
    let rating: String?
    let releaseYear: String?
    let genres: [String]
    let meta: PlaybackMeta?
}

struct HeroCarouselView: View {
    let items: [HeroCarouselItem]
    @State private var currentIndex: Int = 0
    @FocusState private var isControlsFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var presenter: PlayerPresenter
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var appSettings = AppSettings.shared

    private let timer = Timer.publish(every: 7.0, on: .main, in: .common).autoconnect()

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ZStack(alignment: .bottomLeading) {
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.prefix(6).enumerated()), id: \.element.id) { index, item in
                        heroCarouselSlide(item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 840)

                // Page indicator dots at bottom right
                HStack(spacing: 8) {
                    ForEach(0..<min(items.count, 6), id: \.self) { idx in
                        Capsule()
                            .fill(idx == currentIndex ? Color.white : Color.white.opacity(0.35))
                            .frame(width: idx == currentIndex ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentIndex)
                    }
                }
                .padding(.trailing, 60)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 840)
            .onReceive(timer) { _ in
                guard !reduceMotion && !isControlsFocused else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    currentIndex = (currentIndex + 1) % max(1, min(items.count, 6))
                }
            }
        }
    }

    private func heroCarouselSlide(_ item: HeroCarouselItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed 16:9 Backdrop
            if let url = item.backdropURL {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Theme.Palette.surface1
                    }
                }
            } else {
                Theme.Palette.surface1
            }

            // Dark gradient on left edge for text contrast
            LinearGradient(
                colors: [
                    Color.black.opacity(0.85),
                    Color.black.opacity(0.40),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Dark gradient on bottom edge to blend into canvas
            LinearGradient(
                colors: [
                    Color.clear,
                    Theme.Palette.canvas.opacity(0.60),
                    Theme.Palette.canvas
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            // Left-aligned stacked Hero Info Block
            VStack(alignment: .leading, spacing: 8) {
                // Capsule Badge
                Text(item.type == "series" ? "SERIES" : "FEATURED")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5))

                // Large Editorial Title Text
                Text(item.title)
                    .font(.system(size: 50, weight: .black, design: .serif))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.85), radius: 8, x: 0, y: 3)

                // Metadata Line (type, genres, rating)
                HStack(spacing: 8) {
                    Image(systemName: "tv.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text(item.type.capitalized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)

                    if let year = item.releaseYear {
                        Text("•").foregroundStyle(Theme.Palette.textTertiary)
                        Text(year)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }

                    if let rating = item.rating {
                        Text("•").foregroundStyle(Theme.Palette.textTertiary)
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.85))
                            Text(rating)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.Palette.textPrimary)
                        }
                    }

                    if !item.genres.isEmpty {
                        Text("•").foregroundStyle(Theme.Palette.textTertiary)
                        Text(item.genres.prefix(2).joined(separator: " / "))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }

                // 2-line Description
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                        .lineSpacing(3)
                        .frame(maxWidth: 820, alignment: .leading)
                }

                // Action Buttons: White Pill Play button + small circular buttons
                HStack(spacing: Theme.Space.md) {
                    // White Pill: Play
                    NavigationLink(destination: DetailView(type: item.type, id: item.id)) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(WhitePillButtonStyle())

                    // Circular button: + (Add to Library)
                    Button {
                        CoreBridge.shared.addToLibrary(metaId: item.id)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(CircleGlassButtonStyle())

                    // Circular button: i (Info / Details)
                    NavigationLink(destination: DetailView(type: item.type, id: item.id)) {
                        Image(systemName: "info")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(CircleGlassButtonStyle())

                    // Circular button: Trailer
                    Button {
                        Task {
                            if let trailer = await MetadataService.shared.resolveTrailer(for: item.id) {
                                await MainActor.run {
                                    presenter.request = PlaybackRequest(
                                        url: trailer.videoURL,
                                        title: "\(item.title) — Trailer",
                                        audioURL: trailer.audioURL
                                    )
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(CircleGlassButtonStyle())
                }
                .padding(.top, 4)
                .focused($isControlsFocused)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Apple TV 16:9 Landscape Continue Watching Card (Photo 1)

struct LandscapeCWCard: View {
    let item: CoreCWItem
    let directPlay: (() -> Void)?
    let onDetails: (() -> Void)?
    @Environment(\.isFocused) private var isFocused
    @EnvironmentObject private var theme: ThemeManager
    @State private var backdropURL: URL?

    var body: some View {
        Button {
            directPlay?()
        } label: {
            ZStack(alignment: .bottomLeading) {
                // 16:9 Landscape Backdrop
                if let url = backdropURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Theme.Palette.surface1
                        }
                    }
                } else if let poster = item.poster, let url = URL(string: poster) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Theme.Palette.surface1
                        }
                    }
                } else {
                    Theme.Palette.surface1
                }

                // Cinematic bottom gradient scrim
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.35),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Bottom Content matching Apple TV Photo 1: (▶ — S1, E1 • 20m) + Source Badge + 4pt Progress Bar
                VStack(spacing: 6) {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("—")
                            .foregroundStyle(Color.white.opacity(0.6))
                        Text(episodeCode)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Text("•")
                            .foregroundStyle(Color.white.opacity(0.6))
                        Text(remainingTimeText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))

                        Spacer()

                        // Circular provider / source badge matching Apple TV Photo 1
                        Circle()
                            .fill(Color.black.opacity(0.65))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: "tv.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white)
                            )
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)

                    // 4pt Progress Bar matching Apple TV
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.24))
                            Capsule().fill(Color.white)
                                .frame(width: max(4, geo.size.width * CGFloat(min(max(item.progress, 0), 1))))
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
            }
            .frame(width: 380, height: 214)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isFocused ? Color.white.opacity(0.35) : Color.clear, lineWidth: isFocused ? 1.5 : 0)
            )
        }
        .buttonStyle(CardFocusStyle(scale: 1.08))
        .contextMenu {
            if let onDetails {
                Button(action: onDetails) {
                    Label("Details", systemImage: "info.circle")
                }
            }
            Button(role: .destructive) {
                CoreBridge.shared.removeFromLibrary(id: item.id)
            } label: {
                Label("Remove from Continue Watching", systemImage: "minus.circle")
            }
        }
        .task {
            if let backdrop = await MetadataService.shared.resolveBackdrop(for: item.id) {
                await MainActor.run { self.backdropURL = backdrop }
            } else if item.id.hasPrefix("tt") {
                await MainActor.run {
                    self.backdropURL = URL(string: "https://images.metahub.space/background/big/\(item.id)/img")
                }
            }
        }
    }

    private var episodeCode: String {
        if let vid = item.state.videoId, vid.contains(":") {
            let parts = vid.components(separatedBy: ":")
            if parts.count >= 3, let s = Int(parts[1]), let e = Int(parts[2]) {
                return "S\(s), E\(e)"
            }
        }
        return item.name
    }

    private var remainingTimeText: String {
        guard item.state.duration > 0 else { return "\(Int((item.progress * 100).rounded()))%" }
        let remainingMs = max(0, item.state.duration - item.state.timeOffset)
        let totalMins = Int((remainingMs / 60_000).rounded())
        let hours = totalMins / 60
        let mins = totalMins % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(max(1, mins))m"
        }
    }
}

// MARK: - Top 10 Ranked Rail (Apple TV Style matching Photo 5)

struct BannerCardItem: Identifiable {
    let id: String
    let type: String
    let rank: Int
    let title: String
    var backdropURL: URL?
    var posterURL: URL? = nil
    var genre: String? = nil
    let meta: PlaybackMeta?
}

struct FullBleedBannerRail: View {
    let title: String
    let items: [BannerCardItem]
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                RailHeader(eyebrow: "FEATURED CHARTS", title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Space.xl) {
                        ForEach(items) { item in
                            bannerCard(item)
                        }
                    }
                    .padding(.horizontal, Theme.Space.screenEdge)
                    .padding(.vertical, Theme.Space.md)
                }
            }
        }
    }

    private func bannerCard(_ item: BannerCardItem) -> some View {
        NavigationLink(destination: DetailView(type: item.type, id: item.id)) {
            Top10ItemView(item: item)
        }
        .buttonStyle(CardFocusStyle(scale: 1.08))
    }
}

private struct Top10ItemView: View {
    let item: BannerCardItem
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: -26) {
            // Stylized outlined ranking number matching Apple TV Photo 5
            Text("\(item.rank)")
                .font(.system(size: 130, weight: .black, design: .default))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.85), Color.white.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 4)
                .zIndex(1)

            VStack(alignment: .leading, spacing: 8) {
                // 2:3 Portrait Card matching Apple TV Photo 5
                ZStack {
                    if let poster = item.posterURL {
                        AsyncImage(url: poster) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Theme.Palette.surface1
                            }
                        }
                    } else if let backdrop = item.backdropURL {
                        AsyncImage(url: backdrop) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Theme.Palette.surface1
                            }
                        }
                    } else {
                        Theme.Palette.surface1
                    }
                }
                .frame(width: 200, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(isFocused ? Color.white.opacity(0.35) : Color.clear, lineWidth: isFocused ? 1.5 : 0)
                )

                // Title and Genre underneath matching Apple TV Photo 5
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 18, weight: isFocused ? .bold : .semibold))
                        .foregroundStyle(isFocused ? Color.white : Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .offset(y: (isFocused && !reduceMotion) ? -2 : 0)
                    Text(item.genre ?? item.type.capitalized)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
                .frame(width: 200, alignment: .leading)
            }
        }
    }
}

// MARK: - Curated Thematic Rail with Inline Video Trailer on Dwell (Photos 3 & 4)

struct CuratedCardItem: Identifiable {
    let id: String
    let type: String
    let title: String
    var backdropURL: URL?
    var posterURL: URL? = nil
    var tag: String? = nil            // e.g. "New"
    var subtag: String? = nil         // e.g. "Another Season Is Coming" or "#1 Show on Xtv"
    var genres: [String] = []
    let meta: PlaybackMeta?
}

struct CuratedCategoryRail: View {
    let eyebrow: String?
    let title: String
    let items: [CuratedCardItem]
    @EnvironmentObject private var presenter: PlayerPresenter
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                RailHeader(eyebrow: eyebrow, title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Space.lg) {
                        ForEach(items) { item in
                            CuratedCardView(item: item)
                        }
                    }
                    .padding(.horizontal, Theme.Space.screenEdge)
                    .padding(.vertical, Theme.Space.md)
                }
            }
        }
    }
}

private struct CuratedCardView: View {
    let item: CuratedCardItem
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trailerURL: URL?
    @State private var dwellTask: Task<Void, Never>?
    @State private var isDwellTrailerActive = false

    var body: some View {
        NavigationLink(destination: DetailView(type: item.type, id: item.id)) {
            ZStack(alignment: .bottomLeading) {
                // Card Media Layer: 2:3 Large Portrait Poster or Looping Trailer
                if isDwellTrailerActive, let trailerURL {
                    BackdropVideoPlayer(url: trailerURL)
                        .transition(.opacity)
                } else if let poster = item.posterURL {
                    AsyncImage(url: poster) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Theme.Palette.surface1
                        }
                    }
                } else if let backdrop = item.backdropURL {
                    AsyncImage(url: backdrop) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Theme.Palette.surface1
                        }
                    }
                } else {
                    Theme.Palette.surface1
                }

                // Optional "New" or promotional badge in top corner
                if let tag = item.tag, !tag.isEmpty {
                    VStack {
                        HStack {
                            Text(tag.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(14)
                }

                // Bottom Gradient Scrim for readable title & metadata
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.45),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Title, metadata line (genres) and tagline at bottom
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.85), radius: 4, x: 0, y: 2)
                        .offset(y: (isFocused && !reduceMotion) ? -2 : 0)

                    HStack(spacing: 5) {
                        Text(item.type.capitalized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                        if !item.genres.isEmpty {
                            Text("•").foregroundStyle(Color.white.opacity(0.5))
                            Text(item.genres.prefix(2).joined(separator: " · "))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                    }

                    if let subtag = item.subtag, !subtag.isEmpty {
                        Text(subtag)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
                .padding(14)
            }
            .frame(width: 240, height: 360)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isFocused ? Color.white.opacity(0.3) : Color.clear, lineWidth: isFocused ? 1.5 : 0)
            )
        }
        .buttonStyle(CardFocusStyle(scale: 1.08))
        .onChange(of: isFocused) { focused in
            dwellTask?.cancel()
            if focused && !reduceMotion && AppSettings.shared.backdropTrailers {
                // 1500ms dwell before inline video trailer playback kicks in
                dwellTask = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    if let trailer = await MetadataService.shared.resolveTrailer(for: item.id) {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            self.trailerURL = trailer.videoURL
                            withAnimation(.easeInOut(duration: 0.4)) {
                                self.isDwellTrailerActive = true
                            }
                        }
                    }
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDwellTrailerActive = false
                    trailerURL = nil
                }
            }
        }
        .onDisappear {
            dwellTask?.cancel()
            isDwellTrailerActive = false
            trailerURL = nil
        }
    }
}

// MARK: - Smart Recommendation Engine ("Because You Watched...")

struct SmartRecommendationsRail: View {
    let baseTitle: String
    let baseId: String
    let baseType: String
    var focusModel: FocusedItemModel? = nil
    @State private var items: [TMDBMediaItem] = []
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                RailHeader(eyebrow: "SMART RECOMMENDATIONS", title: "Because you watched \(baseTitle)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.md) {
                        ForEach(items) { item in
                            PosterCard(
                                title: item.title,
                                poster: item.posterURL?.absoluteString,
                                type: item.type,
                                id: item.imdbId ?? item.id,
                                onFocus: focusModel.map { model in {
                                    model.focus(FocusedHero(
                                        id: item.imdbId ?? item.id,
                                        type: item.type,
                                        title: item.title,
                                        backdrop: item.backdropURL?.absoluteString ?? item.posterURL?.absoluteString,
                                        metaLine: [item.releaseYear, item.rating.map { "★ \($0)" }, item.type.capitalized].compactMap { $0 }.joined(separator: " · "),
                                        overview: item.overview,
                                        genreLine: nil
                                    ))
                                }}
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Space.screenEdge)
                    .padding(.vertical, Theme.Space.sm)
                }
            }
        } else {
            Color.clear.frame(height: 0)
                .task {
                    let fetched = await MetadataService.shared.fetchRecommendations(for: baseId, type: baseType)
                    await MainActor.run {
                        self.items = fetched
                    }
                }
        }
    }
}

// MARK: - Interactive Floating Detail Drawer (Peek & Pop)

struct FloatingDetailDrawer: View {
    let meta: PlaybackMeta
    let synopsis: String?
    let rating: String?
    let onPlay: () -> Void
    let onDismiss: () -> Void
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    if let poster = meta.poster, let url = URL(string: poster) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Theme.Palette.surface2
                            }
                        }
                        .frame(width: 160, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(meta.name)
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)

                        if let rating {
                            Label(rating, systemImage: "star.fill")
                                .font(Theme.Typography.label)
                                .foregroundStyle(Theme.Palette.accent)
                        }

                        if let synopsis, !synopsis.isEmpty {
                            Text(synopsis)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .lineLimit(4)
                        }

                        Spacer()

                        HStack(spacing: Theme.Space.sm) {
                            Button {
                                onPlay()
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(PrimaryActionStyle())

                            Button {
                                onDismiss()
                            } label: {
                                Text("Close")
                            }
                            .buttonStyle(ChipButtonStyle(selected: false))
                        }
                    }
                }
                .padding(Theme.Space.lg)
            }
            .frame(maxWidth: 880, maxHeight: 420)
            .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .liquidGlassBackground(cornerRadius: Theme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.accent, lineWidth: 1.5)
            )
        }
    }
}
