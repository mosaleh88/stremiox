import Foundation
import Combine

public final class IPTVService: ObservableObject {
    public static let shared = IPTVService()

    @Published public private(set) var config: IPTVConfig
    @Published public private(set) var isConnected: Bool

    // In-memory caches to make UI navigation snappy
    private var liveCategoriesCache: [IPTVCategory]?
    private var vodCategoriesCache: [IPTVCategory]?
    private var seriesCategoriesCache: [IPTVCategory]?

    private var liveStreamsCache: [String: [IPTVLiveStream]] = [:]
    public var cachedLiveStreams: [IPTVLiveStream] { liveStreamsCache["all"] ?? liveStreamsCache.values.first ?? [] }
    private var vodStreamsCache: [String: [IPTVVODStream]] = [:]
    private var seriesCache: [String: [IPTVSeries]] = [:]
    private var seriesInfoCache: [Int: [IPTVSeriesSeason]] = [:]

    private let session: URLSession

    private init() {
        let current = IPTVConfig.current
        self.config = current
        self.isConnected = current.isConnected && !current.serverURL.isEmpty && !current.username.isEmpty
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    public func reloadConfig() {
        let current = IPTVConfig.current
        self.config = current
        self.isConnected = current.isConnected && !current.serverURL.isEmpty && !current.username.isEmpty
        clearCache()
    }

    public func clearCache() {
        liveCategoriesCache = nil
        vodCategoriesCache = nil
        seriesCategoriesCache = nil
        liveStreamsCache.removeAll()
        vodStreamsCache.removeAll()
        seriesCache.removeAll()
        seriesInfoCache.removeAll()
    }

    public func disconnect() {
        IPTVConfig.clear()
        config = IPTVConfig()
        isConnected = false
        clearCache()
    }

    // MARK: - Authentication & Connection

    public func connect(serverURL: String, username: String, password: String) async throws -> IPTVConfig {
        var base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var pass = password.trimmingCharacters(in: .whitespacesAndNewlines)

        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "http://" + base
        }

        // If the user pasted a full URL with query parameters (e.g. from an M3U or web link)
        if let comps = URLComponents(string: base) {
            if let userItem = comps.queryItems?.first(where: { $0.name.lowercased() == "username" })?.value, !userItem.isEmpty {
                user = userItem
            }
            if let passItem = comps.queryItems?.first(where: { $0.name.lowercased() == "password" })?.value, !passItem.isEmpty {
                pass = passItem
            }
            if let host = comps.host {
                var clean = "\(comps.scheme ?? "http")://\(host)"
                if let p = comps.port { clean += ":\(p)" }
                base = clean
            }
        }
        while base.hasSuffix("/") { base.removeLast() }

        guard let url = URL(string: "\(base)/player_api.php?username=\(enc(user))&password=\(enc(pass))") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Mozilla/5.0 (AppleTV; tvOS 18.0) AppleCoreMedia", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try? JSONDecoder().decode(IPTVAccountAuthResponse.self, from: data)
        let userInfo = decoded?.userInfo

        if let auth = userInfo?.auth, auth == 0 {
            throw NSError(domain: "IPTVService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials: IPTV server reported auth failure."])
        }
        if let status = userInfo?.status?.lowercased(), status == "disabled" || status == "banned" || status == "expired" {
            throw NSError(domain: "IPTVService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Account is \(status)."])
        }

        var expiryFormatted: String? = nil
        if let rawExp = userInfo?.expDate, let timestamp = Double(rawExp) {
            let date = Date(timeIntervalSince1970: timestamp)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            expiryFormatted = formatter.string(from: date)
        } else if let rawExp = userInfo?.expDate, !rawExp.isEmpty {
            expiryFormatted = rawExp
        }

        var newConfig = IPTVConfig(
            serverURL: base,
            username: user,
            password: pass,
            serverName: decoded?.serverInfo?.url ?? URL(string: base)?.host,
            expiryDate: expiryFormatted,
            maxConnections: userInfo?.maxConnections,
            activeCons: userInfo?.activeCons,
            isConnected: true
        )
        newConfig.save()

        await MainActor.run {
            self.config = newConfig
            self.isConnected = true
            self.clearCache()
        }
        return newConfig
    }

    // MARK: - Live TV

    public func fetchLiveCategories() async throws -> [IPTVCategory] {
        if let cached = liveCategoriesCache { return cached }
        let url = try apiURL(action: "get_live_categories")
        let (data, _) = try await session.data(from: url)
        let list = (try? JSONDecoder().decode([IPTVCategory].self, from: data)) ?? []
        liveCategoriesCache = list
        return list
    }

    public func fetchLiveStreams(categoryID: String? = nil) async throws -> [IPTVLiveStream] {
        let cacheKey = categoryID ?? "all"
        if let cached = liveStreamsCache[cacheKey] { return cached }
        var action = "get_live_streams"
        if let categoryID, !categoryID.isEmpty, categoryID != "all" {
            action += "&category_id=\(enc(categoryID))"
        }
        let url = try apiURL(action: action)
        let (data, _) = try await session.data(from: url)
        let list = (try? JSONDecoder().decode([IPTVLiveStream].self, from: data)) ?? []
        liveStreamsCache[cacheKey] = list
        return list
    }

    // MARK: - VOD Movies

    public func fetchVODCategories() async throws -> [IPTVCategory] {
        if let cached = vodCategoriesCache { return cached }
        let url = try apiURL(action: "get_vod_categories")
        let (data, _) = try await session.data(from: url)
        let list = (try? JSONDecoder().decode([IPTVCategory].self, from: data)) ?? []
        vodCategoriesCache = list
        return list
    }

    public func fetchVODStreams(categoryID: String? = nil) async throws -> [IPTVVODStream] {
        let cacheKey = categoryID ?? "all"
        if let cached = vodStreamsCache[cacheKey] { return cached }
        var action = "get_vod_streams"
        if let categoryID, !categoryID.isEmpty, categoryID != "all" {
            action += "&category_id=\(enc(categoryID))"
        }
        let url = try apiURL(action: action)
        let (data, _) = try await session.data(from: url)
        let list = (try? JSONDecoder().decode([IPTVVODStream].self, from: data)) ?? []
        vodStreamsCache[cacheKey] = list
        return list
    }

    // MARK: - Series

    public func fetchSeriesCategories() async throws -> [IPTVCategory] {
        if let cached = seriesCategoriesCache { return cached }
        let url = try apiURL(action: "get_series_categories")
        let (data, _) = try await session.data(from: url)
        let list = (try? JSONDecoder().decode([IPTVCategory].self, from: data)) ?? []
        seriesCategoriesCache = list
        return list
    }

    public func fetchSeries(categoryID: String? = nil) async throws -> [IPTVSeries] {
        let cacheKey = categoryID ?? "all"
        if let cached = seriesCache[cacheKey] { return cached }
        var action = "get_series"
        if let categoryID, !categoryID.isEmpty, categoryID != "all" {
            action += "&category_id=\(enc(categoryID))"
        }
        let url = try apiURL(action: action)
        let (data, _) = try await session.data(from: url)
        let list = (try? JSONDecoder().decode([IPTVSeries].self, from: data)) ?? []
        seriesCache[cacheKey] = list
        return list
    }

    public func fetchSeriesInfo(seriesID: Int) async throws -> [IPTVSeriesSeason] {
        if let cached = seriesInfoCache[seriesID] { return cached }
        let url = try apiURL(action: "get_series_info&series_id=\(seriesID)")
        let (data, _) = try await session.data(from: url)

        struct SeriesInfoResponse: Decodable {
            let episodes: [String: [IPTVEpisode]]?
        }

        let decoded = try JSONDecoder().decode(SeriesInfoResponse.self, from: data)
        var seasons: [IPTVSeriesSeason] = []
        if let episodesDict = decoded.episodes {
            for (seasonKey, eps) in episodesDict {
                let seasonNum = Int(seasonKey) ?? 1
                let sortedEps = eps.sorted { $0.episodeNum < $1.episodeNum }
                seasons.append(IPTVSeriesSeason(seasonNumber: seasonNum, episodes: sortedEps))
            }
            seasons.sort { $0.seasonNumber < $1.seasonNumber }
        }
        seriesInfoCache[seriesID] = seasons
        return seasons
    }

    // MARK: - Stream URLs

    public func liveStreamURL(streamID: Int) -> URL? {
        guard isConnected else { return nil }
        let base = config.normalizedBaseURL
        return URL(string: "\(base)/live/\(enc(config.username))/\(enc(config.password))/\(streamID).ts")
    }

    public func streamURL(for streamId: Int) -> URL? {
        liveStreamURL(streamID: streamId)
    }

    public func vodStreamURL(streamID: Int, containerExtension: String?) -> URL? {
        guard isConnected else { return nil }
        let base = config.normalizedBaseURL
        let ext = containerExtension?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedExt = (ext == nil || ext?.isEmpty == true) ? "mp4" : ext!
        return URL(string: "\(base)/movie/\(enc(config.username))/\(enc(config.password))/\(streamID).\(resolvedExt)")
    }

    public func seriesStreamURL(episodeId: String, containerExtension: String?) -> URL? {
        guard isConnected else { return nil }
        let base = config.normalizedBaseURL
        let ext = containerExtension?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedExt = (ext == nil || ext?.isEmpty == true) ? "mp4" : ext!
        return URL(string: "\(base)/series/\(enc(config.username))/\(enc(config.password))/\(episodeId).\(resolvedExt)")
    }

    // MARK: - Internal Helpers

    private func apiURL(action: String) throws -> URL {
        guard isConnected else {
            throw NSError(domain: "IPTVService", code: 400, userInfo: [NSLocalizedDescriptionKey: "IPTV service is not configured."])
        }
        let base = config.normalizedBaseURL
        let full = "\(base)/player_api.php?username=\(enc(config.username))&password=\(enc(config.password))&action=\(action)"
        guard let url = URL(string: full) else { throw URLError(.badURL) }
        return url
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}
