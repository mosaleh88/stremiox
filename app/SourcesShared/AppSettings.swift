import SwiftUI
import Combine

/// Central store for StremioX optional feature toggles and preferences.
/// All experimental/advanced features default to `false` or native defaults
/// to ensure 100% backward compatibility and retain the core native tvOS design.
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    // MARK: - Appearance & Theme Keys
    public enum AppearanceMode: String, CaseIterable, Identifiable {
        case dark = "dark"
        case light = "light"
        case auto = "auto"
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .dark: return "Dark (Cinema)"
            case .light: return "Light (Apple TV White)"
            case .auto: return "Automatic (System)"
            }
        }
    }

    @Published public var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Key.appearanceMode) }
    }
    @Published public var liquidGlass: Bool {
        didSet { UserDefaults.standard.set(liquidGlass, forKey: Key.liquidGlass) }
    }

    // MARK: - Layout & Navigation Keys
    @Published public var modularHomeRails: Bool {
        didSet { UserDefaults.standard.set(modularHomeRails, forKey: Key.modularHomeRails) }
    }
    @Published public var heroCarousel: Bool {
        didSet { UserDefaults.standard.set(heroCarousel, forKey: Key.heroCarousel) }
    }
    @Published public var cinematicSpotlight: Bool {
        didSet { UserDefaults.standard.set(cinematicSpotlight, forKey: Key.cinematicSpotlight) }
    }
    @Published public var fullBleedBanners: Bool {
        didSet { UserDefaults.standard.set(fullBleedBanners, forKey: Key.fullBleedBanners) }
    }
    @Published public var peekAndPopDrawer: Bool {
        didSet { UserDefaults.standard.set(peekAndPopDrawer, forKey: Key.peekAndPopDrawer) }
    }
    @Published public var smartRecommendations: Bool {
        didSet { UserDefaults.standard.set(smartRecommendations, forKey: Key.smartRecommendations) }
    }

    // MARK: - Metadata & External Services
    @Published public var tmdbApiKey: String {
        didSet { UserDefaults.standard.set(tmdbApiKey, forKey: Key.tmdbApiKey) }
    }
    @Published public var mdblistApiKey: String {
        didSet { UserDefaults.standard.set(mdblistApiKey, forKey: Key.mdblistApiKey) }
    }
    @Published public var invidiousInstance: String {
        didSet { UserDefaults.standard.set(invidiousInstance, forKey: Key.invidiousInstance) }
    }
    @Published public var traktClientId: String {
        didSet { UserDefaults.standard.set(traktClientId, forKey: Key.traktClientId) }
    }
    @Published public var traktClientSecret: String {
        didSet { UserDefaults.standard.set(traktClientSecret, forKey: Key.traktClientSecret) }
    }

    // MARK: - Live TV & IPTV Keys
    @Published public var liveHorizontalCategories: Bool {
        didSet { UserDefaults.standard.set(liveHorizontalCategories, forKey: Key.liveHorizontalCategories) }
    }
    @Published public var favoriteStreamIDs: Set<Int> {
        didSet { UserDefaults.standard.set(Array(favoriteStreamIDs), forKey: Key.favoriteStreamIDs) }
    }
    @Published public var channelSortAscending: Bool {
        didSet { UserDefaults.standard.set(channelSortAscending, forKey: Key.channelSortAscending) }
    }

    // MARK: - Player & Playback Keys
    @Published public var matchContent: Bool {
        didSet { UserDefaults.standard.set(matchContent, forKey: Key.matchContent) }
    }
    @Published public var bingeMode: Bool {
        didSet { UserDefaults.standard.set(bingeMode, forKey: Key.bingeMode) }
    }
    @Published public var quickGuideDrawer: Bool {
        didSet { UserDefaults.standard.set(quickGuideDrawer, forKey: Key.quickGuideDrawer) }
    }
    @Published public var subOffsetAuto: Bool {
        didSet { UserDefaults.standard.set(subOffsetAuto, forKey: Key.subOffsetAuto) }
    }
    @Published public var backdropTrailers: Bool {
        didSet { UserDefaults.standard.set(backdropTrailers, forKey: Key.backdropTrailers) }
    }

    // MARK: - Sync Keys
    @Published public var traktSync: Bool {
        didSet { UserDefaults.standard.set(traktSync, forKey: Key.traktSync) }
    }
    @Published public var cloudHistorySync: Bool {
        didSet { UserDefaults.standard.set(cloudHistorySync, forKey: Key.cloudHistorySync) }
    }

    // MARK: - Storage Keys
    public enum Key {
        public static let appearanceMode = "stremiox.theme.appearanceMode"
        public static let liquidGlass = "stremiox.theme.liquidGlass"
        public static let modularHomeRails = "stremiox.feature.modularHomeRails"
        public static let heroCarousel = "stremiox.feature.heroCarousel"
        public static let cinematicSpotlight = "stremiox.feature.cinematicSpotlight"
        public static let fullBleedBanners = "stremiox.feature.fullBleedBanners"
        public static let peekAndPopDrawer = "stremiox.feature.peekAndPopDrawer"
        public static let smartRecommendations = "stremiox.feature.smartRecommendations"
        public static let tmdbApiKey = "stremiox.metadata.tmdbKey"
        public static let mdblistApiKey = "stremiox.metadata.mdblistKey"
        public static let invidiousInstance = "stremiox.metadata.invidiousInstance"
        public static let traktClientId = "stremiox.sync.traktClientId"
        public static let traktClientSecret = "stremiox.sync.traktClientSecret"
        public static let liveHorizontalCategories = "stremiox.feature.liveHorizontalCategories"
        public static let favoriteStreamIDs = "stremiox.iptv.favorites"
        public static let channelSortAscending = "stremiox.iptv.sortAscending"
        public static let matchContent = "stremiox.player.matchContent"
        public static let bingeMode = "stremiox.player.bingeMode"
        public static let quickGuideDrawer = "stremiox.player.quickGuideDrawer"
        public static let subOffsetAuto = "stremiox.player.subOffsetAuto"
        public static let backdropTrailers = "stremiox.player.backdropTrailers"
        public static let traktSync = "stremiox.sync.traktSync"
        public static let cloudHistorySync = "stremiox.sync.cloudHistorySync"
    }

    private init() {
        let rawMode = UserDefaults.standard.string(forKey: Key.appearanceMode) ?? AppearanceMode.dark.rawValue
        self.appearanceMode = AppearanceMode(rawValue: rawMode) ?? .dark
        self.liquidGlass = UserDefaults.standard.bool(forKey: Key.liquidGlass)

        self.modularHomeRails = UserDefaults.standard.bool(forKey: Key.modularHomeRails)
        self.heroCarousel = UserDefaults.standard.bool(forKey: Key.heroCarousel)
        self.cinematicSpotlight = UserDefaults.standard.bool(forKey: Key.cinematicSpotlight)
        self.fullBleedBanners = UserDefaults.standard.bool(forKey: Key.fullBleedBanners)
        self.peekAndPopDrawer = UserDefaults.standard.bool(forKey: Key.peekAndPopDrawer)
        self.smartRecommendations = UserDefaults.standard.bool(forKey: Key.smartRecommendations)

        self.tmdbApiKey = UserDefaults.standard.string(forKey: Key.tmdbApiKey) ?? ""
        self.mdblistApiKey = UserDefaults.standard.string(forKey: Key.mdblistApiKey) ?? ""
        self.invidiousInstance = UserDefaults.standard.string(forKey: Key.invidiousInstance) ?? "https://yt.chocolatemoo53.com"
        self.traktClientId = UserDefaults.standard.string(forKey: Key.traktClientId) ?? ""
        self.traktClientSecret = UserDefaults.standard.string(forKey: Key.traktClientSecret) ?? ""

        self.liveHorizontalCategories = UserDefaults.standard.bool(forKey: Key.liveHorizontalCategories)
        let favs = UserDefaults.standard.array(forKey: Key.favoriteStreamIDs) as? [Int] ?? []
        self.favoriteStreamIDs = Set(favs)
        self.channelSortAscending = UserDefaults.standard.bool(forKey: Key.channelSortAscending)

        self.matchContent = UserDefaults.standard.bool(forKey: Key.matchContent)
        self.bingeMode = UserDefaults.standard.bool(forKey: Key.bingeMode)
        self.quickGuideDrawer = UserDefaults.standard.bool(forKey: Key.quickGuideDrawer)
        self.subOffsetAuto = UserDefaults.standard.bool(forKey: Key.subOffsetAuto)
        self.backdropTrailers = UserDefaults.standard.bool(forKey: Key.backdropTrailers)

        self.traktSync = UserDefaults.standard.bool(forKey: Key.traktSync)
        self.cloudHistorySync = UserDefaults.standard.bool(forKey: Key.cloudHistorySync)
    }

    public func toggleFavorite(streamId: Int) {
        if favoriteStreamIDs.contains(streamId) {
            favoriteStreamIDs.remove(streamId)
        } else {
            favoriteStreamIDs.insert(streamId)
        }
    }

    public func isFavorite(streamId: Int) -> Bool {
        favoriteStreamIDs.contains(streamId)
    }

    public func toggleFavorite(streamID: Int) { toggleFavorite(streamId: streamID) }
    public func isFavorite(streamID: Int) -> Bool { isFavorite(streamId: streamID) }
}
