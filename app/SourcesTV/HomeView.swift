import SwiftUI

/// Native tvOS Home, driven by the **stremio-core** engine (via `CoreBridge`): a "Continue Watching"
/// rail plus every catalog of every installed addon, on the StremioX design system (Theme.swift).
struct HomeView: View {
    @EnvironmentObject private var core: CoreBridge
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var account: StremioAccount
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject private var appSettings = AppSettings.shared
    @StateObject private var focusModel = FocusedItemModel()
    @State private var topTrendingItems: [TMDBMediaItem] = []
    @State private var trendingBackdrops: [String: URL] = [:]

    /// The owner profile rides the account's Continue Watching; overlay profiles ride their own
    /// private synced history.
    private var continueWatching: [CoreCWItem] {
        profiles.activeUsesEngineHistory ? core.continueWatching : profiles.cwItems
    }

    private var heroCarouselItems: [HeroCarouselItem] {
        if !topTrendingItems.isEmpty {
            return topTrendingItems.prefix(6).map { tm in
                HeroCarouselItem(
                    id: tm.imdbId ?? tm.id,
                    type: tm.type,
                    title: tm.title,
                    subtitle: nil,
                    overview: tm.overview,
                    backdropURL: tm.backdropURL,
                    posterURL: tm.posterURL,
                    rating: tm.rating,
                    releaseYear: tm.releaseYear,
                    genres: [],
                    meta: tm.meta
                )
            }
        }
        var items: [HeroCarouselItem] = []
        for row in core.boardRows.prefix(1) {
            for it in row.items.prefix(6) {
                let backdrop = trendingBackdrops[it.id]
                let meta = PlaybackMeta(libraryId: it.id, videoId: it.id, type: it.type, name: it.name, poster: it.poster, season: nil, episode: nil)
                items.append(HeroCarouselItem(
                    id: it.id,
                    type: it.type,
                    title: it.name,
                    subtitle: nil,
                    overview: nil,
                    backdropURL: backdrop,
                    posterURL: it.poster.flatMap { URL(string: $0) },
                    rating: nil,
                    releaseYear: nil,
                    genres: [],
                    meta: meta
                ))
            }
        }
        return items
    }

    private var bannerItems: [BannerCardItem] {
        if !topTrendingItems.isEmpty {
            return topTrendingItems.prefix(10).enumerated().map { index, tm in
                BannerCardItem(
                    id: tm.imdbId ?? tm.id,
                    type: tm.type,
                    rank: index + 1,
                    title: tm.title,
                    backdropURL: tm.backdropURL,
                    posterURL: tm.posterURL,
                    genre: tm.type.capitalized,
                    meta: tm.meta
                )
            }
        }
        var list: [BannerCardItem] = []
        var rank = 1
        for row in core.boardRows.prefix(1) {
            for it in row.items.prefix(10) {
                let backdrop = trendingBackdrops[it.id]
                let meta = PlaybackMeta(libraryId: it.id, videoId: it.id, type: it.type, name: it.name, poster: it.poster, season: nil, episode: nil)
                list.append(BannerCardItem(
                    id: it.id,
                    type: it.type,
                    rank: rank,
                    title: it.name,
                    backdropURL: backdrop,
                    posterURL: it.poster.flatMap { URL(string: $0) },
                    genre: it.type.capitalized,
                    meta: meta
                ))
                rank += 1
            }
        }
        return list
    }

    private var curatedItems: [CuratedCardItem] {
        if topTrendingItems.count > 5 {
            return Array(topTrendingItems.dropFirst(3).prefix(6).enumerated()).map { index, tm in
                CuratedCardItem(
                    id: tm.imdbId ?? tm.id,
                    type: tm.type,
                    title: tm.title,
                    backdropURL: tm.backdropURL,
                    posterURL: tm.posterURL,
                    tag: index == 0 ? "New" : nil,
                    subtag: index == 0 ? "Another Season Is Coming" : (index == 1 ? "#1 Show on Xtv" : nil),
                    genres: [],
                    meta: tm.meta
                )
            }
        }
        return []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // If Hero Carousel mode is enabled, it takes the top stage; otherwise use living backdrop
                if !appSettings.heroCarousel {
                    BrowseHeroBackdrop(model: focusModel, detailsBottom: 520)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.lg) {
                        if appSettings.heroCarousel && !heroCarouselItems.isEmpty {
                            HeroCarouselView(items: heroCarouselItems)
                                .padding(.bottom, Theme.Space.sm)
                        }

                        if appSettings.fullBleedBanners && !bannerItems.isEmpty {
                            FullBleedBannerRail(title: "Top 10 Today", items: bannerItems)
                        }

                        if !continueWatching.isEmpty {
                            CoreContinueWatchingRow(items: continueWatching, focusModel: focusModel)
                        }

                        if !curatedItems.isEmpty {
                            CuratedCategoryRail(
                                eyebrow: "FEATURED DRAMA & THRILLERS",
                                title: "Criminally Entertaining",
                                items: curatedItems
                            )
                        }

                        if appSettings.smartRecommendations, let first = continueWatching.first {
                            SmartRecommendationsRail(
                                baseTitle: first.name,
                                baseId: first.id,
                                baseType: "series",
                                focusModel: focusModel
                            )
                        }

                        ForEach(core.boardRows) { row in
                            CoreCatalogRowView(row: row, focusModel: focusModel)
                        }
                        if continueWatching.isEmpty && core.boardRows.isEmpty {
                            if account.isSignedIn { LoadingRail() } else { CoreEmptyState.signedOut }
                        }
                    }
                    .padding(.top, Theme.Space.sm)
                    .padding(.bottom, Theme.Space.xl)
                }
                .modifier(HomeScrollModifier(heroCarousel: appSettings.heroCarousel))
            }
            .background(Theme.Palette.canvas.ignoresSafeArea())
        }
        .task {
            let trending = await MetadataService.shared.fetchTopTrending()
            await MainActor.run {
                self.topTrendingItems = trending
            }
        }
        .task(id: core.boardRows.first?.id) {
            if let firstRow = core.boardRows.first {
                for it in firstRow.items.prefix(10) {
                    if trendingBackdrops[it.id] == nil {
                        if let u = await MetadataService.shared.resolveBackdrop(for: it.id) {
                            await MainActor.run {
                                self.trendingBackdrops[it.id] = u
                            }
                        }
                    }
                }
            }
        }
        .onAppear { configureMetaSources(); seed() }
        .onChange(of: core.boardRows.first?.id) { seed() }
        .onChange(of: core.continueWatching.first?.id) { seed() }
        .onChange(of: profiles.activeID) { seed() }
        .onChange(of: core.addons.count) { configureMetaSources() }
    }

    /// The hero enrichment asks the user's own meta add-ons, so every id scheme resolves.
    private func configureMetaSources() {
        FocusedItemModel.configureMetaSources(
            transportUrls: core.addons.filter(\.providesMeta).map(\.transportUrl))
    }

    /// First render shows the page's actual first item, and Continue Watching pre-fetches its
    /// details so heroes are rich on first focus.
    private func seed() {
        focusModel.seedIfEmpty(continueWatching.first?.focusedHero
                               ?? core.boardRows.first?.items.first?.focusedHero)
        focusModel.warm(continueWatching.map(\.focusedHero))
    }
}

/// Eyebrow kicker + section title, the shared header for every rail.
struct RailHeader: View {
    var eyebrow: String? = nil
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow { Text(eyebrow).eyebrowStyle() }
            Text(title).sectionTitleStyle()
        }
        .padding(.horizontal, Theme.Space.screenEdge)
    }
}

/// Target for opening a full detail page from a Continue Watching card's long-press menu.
struct CWDetailTarget: Identifiable, Hashable { let id: String; let type: String }

/// "Continue Watching" rail from the engine (`continue_watching_preview`), newest first, with a
/// resume-progress stripe on each poster.
struct CoreContinueWatchingRow: View {
    let items: [CoreCWItem]
    var focusModel: FocusedItemModel? = nil
    var menu: PosterMenu = .continueWatching   // .none on overlay-profile rails (engine menu doesn't apply)
    @EnvironmentObject private var theme: ThemeManager   // observe so the rail's cards repaint on a theme change
    @EnvironmentObject private var presenter: PlayerPresenter
    @EnvironmentObject private var profiles: ProfileStore
    @State private var detailTarget: CWDetailTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            RailHeader(eyebrow: "Pick up where you left off", title: "Continue Watching")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Space.lg) {
                    ForEach(items) { item in
                        LandscapeCWCard(
                            item: item,
                            directPlay: directResume(item),
                            onDetails: { detailTarget = CWDetailTarget(id: item.id, type: item.type) }
                        )
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge)
                .padding(.vertical, Theme.Space.lg)   // room for the focus halo
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationDestination(item: $detailTarget) { DetailView(type: $0.type, id: $0.id) }
    }

    /// Continue Watching resumes the exact link that was playing last time, straight
    /// into the player, instead of routing through the detail page and re-resolving
    /// sources. Falls back to the detail page when no remembered link fits: never
    /// played here, or the engine moved the series on to a different episode.
    private func directResume(_ item: CoreCWItem) -> (() -> Void)? {
        guard let entry = LastStreamStore.entry(for: item.id, profileID: profiles.activeID),
              let url = URL(string: entry.url) else { return nil }
        if PlaybackSettings.torrentsDisabled && entry.torrent == true { return nil }
        if item.type == "series", let cwVideo = item.state.videoId, cwVideo != entry.videoId { return nil }
        return {
            presenter.request = PlaybackRequest(
                url: url, title: entry.title,
                meta: PlaybackMeta(libraryId: item.id, videoId: entry.videoId, type: entry.type,
                                   name: entry.name, poster: entry.poster,
                                   season: entry.season, episode: entry.episode),
                episodes: [], sourceHint: entry.qualityText, torrent: entry.torrent ?? false,
                headers: entry.headers)
        }
    }
}

private struct HomeScrollModifier: ViewModifier {
    let heroCarousel: Bool
    func body(content: Content) -> some View {
        if heroCarousel {
            content
        } else {
            content.heroBottomStrip()
        }
    }
}

/// One engine catalog row from the board (all installed-addon catalogs).
struct CoreCatalogRowView: View {
    let row: CoreBoardRow
    var focusModel: FocusedItemModel? = nil
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            RailHeader(title: row.title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Space.lg) {
                    ForEach(row.items) { item in
                        PosterCard(title: item.name, poster: item.poster, type: item.type, id: item.id,
                                   menu: .catalog,
                                   onFocus: focusModel.map { model in
                                       { model.focus(item.focusedHero) }
                                   })
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge)
                .padding(.vertical, Theme.Space.lg)   // room for the focus halo
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Skeleton rail shown while the engine is still loading (signed in). Calmer than a spinner.
struct LoadingRail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            RailHeader(title: "Loading your library")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Space.lg) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.Palette.surface1)
                            .frame(width: kPosterWidth, height: kPosterWidth * 1.5)
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge)
                .padding(.vertical, Theme.Space.lg)   // room for the focus halo
            }
        }
    }
}
