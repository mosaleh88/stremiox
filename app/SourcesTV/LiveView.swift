import SwiftUI

/// Unified IPTV Xtream Portal (Live TV, Movies VOD, Series VOD)
/// Completely independent from Stremio add-ons, natively integrated with tvOS focus engine and libmpv.
struct LiveView: View {
    @ObservedObject private var iptv = IPTVService.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @EnvironmentObject private var presenter: PlayerPresenter
    @EnvironmentObject private var theme: ThemeManager

    private enum IPTVSection: Int, CaseIterable, Identifiable {
        case live = 0
        case movies = 1
        case series = 2

        var id: Int { rawValue }
        var title: String {
            switch self {
            case .live: return "Live TV"
            case .movies: return "Movies"
            case .series: return "Series"
            }
        }
        var icon: String {
            switch self {
            case .live: return "tv"
            case .movies: return "film"
            case .series: return "play.tv"
            }
        }
    }

    @State private var selectedSection: IPTVSection = .live
    @State private var categories: [IPTVCategory] = []
    @State private var selectedCategoryId: String = "all"

    // Content lists
    @State private var liveStreams: [IPTVLiveStream] = []
    @State private var vodStreams: [IPTVVODStream] = []
    @State private var seriesList: [IPTVSeries] = []

    // State flags
    @State private var loading = false
    @State private var showQRModal = false
    @State private var showManualModal = false
    @State private var selectedSeriesForDetail: IPTVSeries?

    private let channelColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: Theme.Space.lg)
    ]
    private let posterColumns = [
        GridItem(.adaptive(minimum: 200, maximum: 230), spacing: Theme.Space.lg)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.canvas.ignoresSafeArea()

                if !iptv.isConnected {
                    unconfiguredView
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        // Top Navigation: Mode Switcher + Server Badge
                        topNavigationHeader
                            .padding(.horizontal, Theme.Space.screenEdge)
                            .padding(.top, Theme.Space.md)
                            .padding(.bottom, Theme.Space.sm)

                        // Categories & Content Layout
                        if appSettings.liveHorizontalCategories {
                            HStack(alignment: .top, spacing: 0) {
                                // Vertical Categories Sidebar
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        categoryButton("All (\(categories.count))", isSelected: selectedCategoryId == "all") {
                                            selectedCategoryId = "all"
                                        }

                                        if !appSettings.favoriteStreamIDs.isEmpty {
                                            categoryButton("⭐ Favorites (\(appSettings.favoriteStreamIDs.count))", isSelected: selectedCategoryId == "favorites") {
                                                selectedCategoryId = "favorites"
                                            }
                                        }

                                        ForEach(categories) { cat in
                                            categoryButton(cat.categoryName, isSelected: selectedCategoryId == cat.categoryId) {
                                                selectedCategoryId = cat.categoryId
                                            }
                                        }
                                    }
                                    .padding(.horizontal, Theme.Space.screenEdge)
                                    .padding(.vertical, Theme.Space.sm)
                                }
                                .frame(width: 340)
                                .focusSection()

                                // Content Grid
                                ScrollView {
                                    if loading {
                                        loadingView
                                    } else {
                                        contentGrid
                                            .padding(.horizontal, Theme.Space.md)
                                            .padding(.top, Theme.Space.md)
                                            .padding(.bottom, Theme.Space.xxl)
                                    }
                                }
                            }
                        } else {
                            // Default Horizontal Rail
                            if !categories.isEmpty {
                                categoriesRail
                                    .padding(.vertical, Theme.Space.sm)
                            }

                            // Content Grid
                            ScrollView {
                                if loading {
                                    loadingView
                                } else {
                                    contentGrid
                                        .padding(.horizontal, Theme.Space.screenEdge)
                                        .padding(.top, Theme.Space.md)
                                        .padding(.bottom, Theme.Space.xxl)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showQRModal) {
            IPTVQRModal()
        }
        .sheet(isPresented: $showManualModal) {
            IPTVManualConfigView {
                loadCurrentSection()
            }
        }
        .sheet(item: $selectedSeriesForDetail) { series in
            IPTVSeriesDetailView(series: series)
        }
        .onAppear {
            if iptv.isConnected {
                loadCurrentSection()
            }
        }
        .onChange(of: iptv.isConnected) {
            if iptv.isConnected {
                loadCurrentSection()
            }
        }
        .onChange(of: selectedSection) {
            selectedCategoryId = "all"
            loadCurrentSection()
        }
        .onChange(of: selectedCategoryId) {
            loadStreamContent()
        }
    }

    // MARK: - Top Navigation Header

    private var topNavigationHeader: some View {
        HStack(alignment: .center, spacing: Theme.Space.lg) {
            Text("Live TV").screenTitleStyle()

            Spacer()

            // Mode Picker
            HStack(spacing: Theme.Space.xs) {
                ForEach(IPTVSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: section.icon)
                            Text(section.title)
                        }
                    }
                    .buttonStyle(ChipButtonStyle(selected: selectedSection == section))
                }
            }
            .focusSection()
        }
    }

    private func categoryButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(ChipButtonStyle(selected: isSelected))
    }

    // MARK: - Categories Rail

    private var categoriesRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                Button("All (\(categories.count))") {
                    selectedCategoryId = "all"
                }
                .buttonStyle(ChipButtonStyle(selected: selectedCategoryId == "all"))

                if !appSettings.favoriteStreamIDs.isEmpty {
                    Button("⭐ Favorites (\(appSettings.favoriteStreamIDs.count))") {
                        selectedCategoryId = "favorites"
                    }
                    .buttonStyle(ChipButtonStyle(selected: selectedCategoryId == "favorites"))
                }

                ForEach(categories) { cat in
                    Button(cat.categoryName) {
                        selectedCategoryId = cat.categoryId
                    }
                    .buttonStyle(ChipButtonStyle(selected: selectedCategoryId == cat.categoryId))
                }
            }
            .padding(.horizontal, Theme.Space.screenEdge)
            .padding(.vertical, Theme.Space.xs)
        }
        .focusSection()
    }

    private var displayLiveStreams: [IPTVLiveStream] {
        var list = liveStreams
        if selectedCategoryId == "favorites" {
            list = list.filter { appSettings.isFavorite(streamId: $0.streamId) }
        }
        if appSettings.channelSortAscending {
            list.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        return list
    }

    // MARK: - Content Grids

    @ViewBuilder
    private var contentGrid: some View {
        switch selectedSection {
        case .live:
            if displayLiveStreams.isEmpty {
                emptyContentView(selectedCategoryId == "favorites" ? "No favorite channels yet. Star a channel to see it here." : "No channels found in this category.")
            } else {
                LazyVGrid(columns: channelColumns, spacing: Theme.Space.lg) {
                    ForEach(displayLiveStreams) { channel in
                        channelTile(channel)
                    }
                }
            }

        case .movies:
            if vodStreams.isEmpty {
                emptyContentView("No movies found in this category.")
            } else {
                LazyVGrid(columns: posterColumns, spacing: Theme.Space.lg) {
                    ForEach(vodStreams) { movie in
                        movieTile(movie)
                    }
                }
            }

        case .series:
            if seriesList.isEmpty {
                emptyContentView("No series found in this category.")
            } else {
                LazyVGrid(columns: posterColumns, spacing: Theme.Space.lg) {
                    ForEach(seriesList) { series in
                        seriesTile(series)
                    }
                }
            }
        }
    }

    // MARK: - Channel Tile (Live TV)

    private func channelTile(_ channel: IPTVLiveStream) -> some View {
        Button {
            playChannel(channel)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ZStack(alignment: .topTrailing) {
                    Theme.Palette.surface1

                    if let icon = channel.streamIcon, let url = URL(string: icon) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fit)
                                    .padding(Theme.Space.sm)
                            default:
                                channelPlaceholder
                            }
                        }
                    } else {
                        channelPlaceholder
                    }

                    if appSettings.isFavorite(streamId: channel.streamId) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.Palette.accent)
                            .padding(8)
                    }
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
                )

                HStack(spacing: 6) {
                    if let num = channel.num, num > 0 {
                        Text("\(num)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    Text(channel.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(CardFocusStyle())
        .contextMenu {
            Button {
                appSettings.toggleFavorite(streamId: channel.streamId)
            } label: {
                Label(appSettings.isFavorite(streamId: channel.streamId) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: appSettings.isFavorite(streamId: channel.streamId) ? "star.slash" : "star.fill")
            }
        }
    }

    private var channelPlaceholder: some View {
        Image(systemName: "tv")
            .font(.system(size: 40))
            .foregroundStyle(Theme.Palette.textTertiary)
    }

    // MARK: - Movie Tile (VOD)

    private func movieTile(_ movie: IPTVVODStream) -> some View {
        Button {
            playMovie(movie)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ZStack(alignment: .topTrailing) {
                    Theme.Palette.surface1

                    if let icon = movie.streamIcon, let url = URL(string: icon) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                moviePlaceholder
                            }
                        }
                    } else {
                        moviePlaceholder
                    }

                    if let rating = movie.rating, !rating.isEmpty, rating != "0" {
                        Text(rating)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
                )

                Text(movie.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .buttonStyle(CardFocusStyle())
    }

    private var moviePlaceholder: some View {
        Image(systemName: "film")
            .font(.system(size: 48))
            .foregroundStyle(Theme.Palette.textTertiary)
    }

    // MARK: - Series Tile (VOD)

    private func seriesTile(_ series: IPTVSeries) -> some View {
        Button {
            selectedSeriesForDetail = series
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ZStack(alignment: .topTrailing) {
                    Theme.Palette.surface1

                    if let cover = series.cover, let url = URL(string: cover) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                seriesPlaceholder
                            }
                        }
                    } else {
                        seriesPlaceholder
                    }

                    if let rating = series.rating, !rating.isEmpty, rating != "0" {
                        Text(rating)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
                )

                Text(series.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .buttonStyle(CardFocusStyle())
    }

    private var seriesPlaceholder: some View {
        Image(systemName: "play.tv")
            .font(.system(size: 48))
            .foregroundStyle(Theme.Palette.textTertiary)
    }

    // MARK: - Playback Triggers

    private func playChannel(_ channel: IPTVLiveStream) {
        guard let url = iptv.liveStreamURL(streamID: channel.streamId) else { return }
        let meta = PlaybackMeta(
            libraryId: "\(channel.streamId)",
            videoId: "\(channel.streamId)",
            type: "tv",
            name: channel.name,
            poster: channel.streamIcon,
            season: nil,
            episode: nil
        )
        presenter.request = PlaybackRequest(url: url, title: channel.name, meta: meta)
    }

    private func playMovie(_ movie: IPTVVODStream) {
        guard let url = iptv.vodStreamURL(streamID: movie.streamId, containerExtension: movie.containerExtension) else { return }
        let meta = PlaybackMeta(
            libraryId: "\(movie.streamId)",
            videoId: "\(movie.streamId)",
            type: "movie",
            name: movie.name,
            poster: movie.streamIcon,
            season: nil,
            episode: nil
        )
        presenter.request = PlaybackRequest(url: url, title: movie.name, meta: meta)
    }

    // MARK: - Loading & Empty States

    private var loadingView: some View {
        VStack(spacing: Theme.Space.md) {
            Spacer()
            BigSpinner()
            Text("Loading content…")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    private func emptyContentView(_ message: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "tv.slash")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - Unconfigured State

    private var unconfiguredView: some View {
        VStack(spacing: Theme.Space.lg) {
            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 72))
                .foregroundStyle(Theme.Palette.accent)

            Text("IPTV Xtream Not Configured")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Connect your Xtream Codes IPTV provider to watch live channels, movies, and series.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)

            HStack(spacing: Theme.Space.md) {
                Button {
                    showQRModal = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode")
                        Text("Scan QR with Phone")
                    }
                }
                .buttonStyle(PrimaryActionStyle())

                Button("Enter Server Details") {
                    showManualModal = true
                }
                .buttonStyle(ChipButtonStyle(selected: false))
            }
            .padding(.top, Theme.Space.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xxl)
    }

    // MARK: - Data Fetching

    private func loadCurrentSection() {
        loading = true
        Task {
            do {
                switch selectedSection {
                case .live:
                    let cats = try await iptv.fetchLiveCategories()
                    await MainActor.run { self.categories = cats }
                case .movies:
                    let cats = try await iptv.fetchVODCategories()
                    await MainActor.run { self.categories = cats }
                case .series:
                    let cats = try await iptv.fetchSeriesCategories()
                    await MainActor.run { self.categories = cats }
                }
                loadStreamContent()
            } catch {
                await MainActor.run { self.loading = false }
            }
        }
    }

    private func loadStreamContent() {
        loading = true
        let cat = selectedCategoryId == "all" ? nil : selectedCategoryId
        Task {
            do {
                switch selectedSection {
                case .live:
                    let streams = try await iptv.fetchLiveStreams(categoryID: cat)
                    await MainActor.run {
                        self.liveStreams = streams
                        self.loading = false
                    }
                case .movies:
                    let streams = try await iptv.fetchVODStreams(categoryID: cat)
                    await MainActor.run {
                        self.vodStreams = streams
                        self.loading = false
                    }
                case .series:
                    let series = try await iptv.fetchSeries(categoryID: cat)
                    await MainActor.run {
                        self.seriesList = series
                        self.loading = false
                    }
                }
            } catch {
                await MainActor.run { self.loading = false }
            }
        }
    }
}
