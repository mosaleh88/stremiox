import Foundation
import Combine

/// High-resolution media item resolved from TMDB / MDBList / Cinemeta
struct TMDBMediaItem: Identifiable, Hashable {
    let id: String
    let tmdbId: Int
    let imdbId: String?
    let title: String
    let overview: String?
    let posterURL: URL?
    let backdropURL: URL?
    let rating: String?
    let releaseYear: String?
    let type: String // "movie" or "series"

    var meta: PlaybackMeta {
        PlaybackMeta(
            libraryId: imdbId ?? id,
            videoId: imdbId ?? id,
            type: type,
            name: title,
            poster: posterURL?.absoluteString,
            season: nil,
            episode: nil
        )
    }
}

public struct ResolvedTrailer {
    public let videoURL: URL
    public let audioURL: URL?
    public init(videoURL: URL, audioURL: URL? = nil) {
        self.videoURL = videoURL
        self.audioURL = audioURL
    }
}

/// Central Metadata and Recommendation Service (Cinemeta + Metahub + TMDB + MDBList)
final class MetadataService: ObservableObject {
    static let shared = MetadataService()

    private static let defaultTMDBKey = ""

    // In-memory caches to avoid redundant network hits
    private var backdropCache: [String: URL] = [:]
    private var trailerCache: [String: ResolvedTrailer] = [:]
    private var tmdbIdCache: [String: (id: Int, isMovie: Bool)] = [:]
    private var recommendationsCache: [String: [TMDBMediaItem]] = [:]
    private var trendingCache: [TMDBMediaItem] = []
    private var lastTrendingFetch: Date = .distantPast

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    private var activeTMDBKey: String {
        AppSettings.shared.tmdbApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Backdrop Resolution (True 16:9 Landscape)

    /// Resolves high-resolution 16:9 backdrop wallpaper for any IMDb ID (e.g. "tt0944947")
    func resolveBackdrop(for id: String) async -> URL? {
        let cleanId = id.hasPrefix("tt") ? id : id.replacingOccurrences(of: "movie:", with: "").replacingOccurrences(of: "series:", with: "")
        if let cached = backdropCache[cleanId] { return cached }

        // Metahub provides instant, high-res 16:9 landscape art for all IMDb IDs without requiring an API key
        if cleanId.hasPrefix("tt") {
            if let metahub = URL(string: "https://images.metahub.space/background/big/\(cleanId)/img") {
                await MainActor.run { self.backdropCache[cleanId] = metahub }
                return metahub
            }
        }

        // If custom TMDB key is set, query TMDB backdrop
        if !activeTMDBKey.isEmpty, let tmdbInfo = await resolveTMDBInfo(for: cleanId) {
            let endpoint = tmdbInfo.isMovie ? "movie" : "tv"
            guard let url = URL(string: "https://api.themoviedb.org/3/\(endpoint)/\(tmdbInfo.id)?api_key=\(activeTMDBKey)&append_to_response=images") else { return nil }

            do {
                let (data, _) = try await session.data(from: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let backdropPath = json["backdrop_path"] as? String, !backdropPath.isEmpty {
                    let fullURL = URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
                    if let fullURL {
                        await MainActor.run { self.backdropCache[cleanId] = fullURL }
                        return fullURL
                    }
                }
            } catch {}
        }
        return nil
    }

    // MARK: - Trailer Resolution (Direct Playable Stream)

    /// Resolves full trailer streams (video stream + synchronized audio stream if separate)
    func resolveTrailer(for id: String) async -> ResolvedTrailer? {
        let cleanId = id.hasPrefix("tt") ? id : id.replacingOccurrences(of: "movie:", with: "").replacingOccurrences(of: "series:", with: "")
        if let cached = trailerCache[cleanId] { return cached }

        var ytKey: String? = nil

        // 1. If custom TMDB key is set, query TMDB videos
        if !activeTMDBKey.isEmpty, let tmdbInfo = await resolveTMDBInfo(for: cleanId) {
            let endpoint = tmdbInfo.isMovie ? "movie" : "tv"
            if let url = URL(string: "https://api.themoviedb.org/3/\(endpoint)/\(tmdbInfo.id)/videos?api_key=\(activeTMDBKey)") {
                if let (data, _) = try? await session.data(from: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]] {
                    let trailer = results.first { ($0["type"] as? String) == "Trailer" && ($0["site"] as? String) == "YouTube" }
                        ?? results.first { ($0["site"] as? String) == "YouTube" }
                    ytKey = trailer?["key"] as? String
                }
            }
        }

        // 2. Cinemeta fallback (official Stremio metadata source for all titles)
        if ytKey == nil && cleanId.hasPrefix("tt") {
            for type in ["movie", "series"] {
                if let u = URL(string: "https://v3-cinemeta.strem.io/meta/\(type)/\(cleanId).json") {
                    if let (data, _) = try? await session.data(from: u),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let meta = json["meta"] as? [String: Any],
                       let trailers = meta["trailers"] as? [[String: Any]] {
                        if let first = trailers.first, let src = first["source"] as? String, !src.isEmpty {
                            ytKey = src
                            break
                        }
                    }
                }
            }
        }

        guard let key = ytKey, !key.isEmpty else { return nil }

        // 3. Resolve direct playable streams via Invidious / Piped instances
        if let trailer = await resolveInvidiousStreams(ytKey: key) {
            await MainActor.run { self.trailerCache[cleanId] = trailer }
            return trailer
        }

        return nil
    }

    /// Resolves a direct, playable video stream URL for a trailer (used by backdrop and AVPlayer)
    func resolveTrailerURL(for id: String) async -> URL? {
        await resolveTrailer(for: id)?.videoURL
    }

    private func resolveInvidiousStreams(ytKey: String) async -> ResolvedTrailer? {
        var baseInstances = [
            AppSettings.shared.invidiousInstance.trimmingCharacters(in: .whitespacesAndNewlines),
            "https://yt.chocolatemoo53.com",
            "https://inv.nadeko.net",
            "https://invidious.nerdvpn.de",
            "https://invidious.tiekoetter.com"
        ].filter { !$0.isEmpty }

        var uniqueBases: [String] = []
        for b in baseInstances {
            let trimmed = b.hasSuffix("/") ? String(b.dropLast()) : b
            if !uniqueBases.contains(trimmed) { uniqueBases.append(trimmed) }
        }

        for base in uniqueBases {
            guard let apiURL = URL(string: "\(base)/api/v1/videos/\(ytKey)") else { continue }
            do {
                let (data, resp) = try await session.data(from: apiURL)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { continue }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                // Check formatStreams (combined video + audio)
                if let formatStreams = json["formatStreams"] as? [[String: Any]] {
                    for s in formatStreams {
                        if let rawURL = s["url"] as? String,
                           let proxied = proxyInvidiousURL(rawURL, base: base) {
                            return ResolvedTrailer(videoURL: proxied, audioURL: nil)
                        }
                    }
                }

                // Adaptive formats: find best video (prefer 720p/1080p mp4) & best audio (mp4)
                if let adaptive = json["adaptiveFormats"] as? [[String: Any]] {
                    var bestVideoURL: URL? = nil
                    var bestVideoHeight: Int = 0
                    var bestAudioURL: URL? = nil

                    for a in adaptive {
                        guard let type = a["type"] as? String, let rawURL = a["url"] as? String else { continue }
                        guard let proxied = proxyInvidiousURL(rawURL, base: base) else { continue }

                        if type.contains("video/mp4") {
                            let res = (a["resolution"] as? String) ?? (a["qualityLabel"] as? String) ?? ""
                            let height = Int(res.filter { $0.isNumber }) ?? 0
                            if bestVideoURL == nil || (height > bestVideoHeight && height <= 1080) || (bestVideoHeight < 720 && height > bestVideoHeight) {
                                bestVideoHeight = height
                                bestVideoURL = proxied
                            }
                        } else if type.contains("audio/mp4") && bestAudioURL == nil {
                            bestAudioURL = proxied
                        }
                    }

                    if let videoURL = bestVideoURL {
                        return ResolvedTrailer(videoURL: videoURL, audioURL: bestAudioURL)
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func proxyInvidiousURL(_ rawURL: String, base: String) -> URL? {
        if rawURL.contains("googlevideo.com") {
            let parts = rawURL.components(separatedBy: "googlevideo.com")
            if parts.count >= 2 {
                return URL(string: "\(base)\(parts[1])")
            }
        }
        if rawURL.hasPrefix("/") {
            return URL(string: "\(base)\(rawURL)")
        }
        return URL(string: rawURL)
    }

    // MARK: - Smart Recommendations ("Because You Watched...")

    /// Fetches genuine recommendations based on an IMDb ID
    func fetchRecommendations(for id: String, type: String) async -> [TMDBMediaItem] {
        let cleanId = id.hasPrefix("tt") ? id : id.replacingOccurrences(of: "movie:", with: "").replacingOccurrences(of: "series:", with: "")
        if let cached = recommendationsCache[cleanId] { return cached }

        // 1. If custom TMDB key is available, query TMDB recommendations
        if !activeTMDBKey.isEmpty, let tmdbInfo = await resolveTMDBInfo(for: cleanId) {
            let endpoint = tmdbInfo.isMovie ? "movie" : "tv"
            if let url = URL(string: "https://api.themoviedb.org/3/\(endpoint)/\(tmdbInfo.id)/recommendations?api_key=\(activeTMDBKey)") {
                if let (data, _) = try? await session.data(from: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]] {
                    var list: [TMDBMediaItem] = []
                    for item in results.prefix(12) {
                        guard let tmdbId = item["id"] as? Int else { continue }
                        let title = (item["title"] as? String) ?? (item["name"] as? String) ?? "Untitled"
                        let overview = item["overview"] as? String
                        let posterPath = item["poster_path"] as? String
                        let backdropPath = item["backdrop_path"] as? String
                        let poster = posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
                        let backdrop = backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") }
                        let ratingVal = item["vote_average"] as? Double
                        let ratingStr = ratingVal.map { String(format: "%.1f", $0) }
                        let dateStr = (item["release_date"] as? String) ?? (item["first_air_date"] as? String)
                        let year = dateStr.flatMap { String($0.prefix(4)) }

                        list.append(TMDBMediaItem(
                            id: "tmdb:\(tmdbId)",
                            tmdbId: tmdbId,
                            imdbId: nil,
                            title: title,
                            overview: overview,
                            posterURL: poster,
                            backdropURL: backdrop,
                            rating: ratingStr,
                            releaseYear: year,
                            type: tmdbInfo.isMovie ? "movie" : "series"
                        ))
                    }
                    if !list.isEmpty {
                        await MainActor.run { self.recommendationsCache[cleanId] = list }
                        return list
                    }
                }
            }
        }

        // 2. Cinemeta recommendations fallback: fetch curated top catalog
        let catalogType = (type == "series") ? "series" : "movie"
        if let u = URL(string: "https://cinemeta-catalogs.strem.io/top/catalog/\(catalogType)/top.json") {
            if let (data, _) = try? await session.data(from: u),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let metas = json["metas"] as? [[String: Any]] {
                var list: [TMDBMediaItem] = []
                for item in metas.filter({ ($0["imdb_id"] as? String) != cleanId }).prefix(10) {
                    guard let imdbId = item["imdb_id"] as? String else { continue }
                    let title = (item["name"] as? String) ?? "Recommended"
                    let overview = item["description"] as? String
                    let posterURL = item["poster"] as? String
                    let rating = item["imdbRating"] as? String
                    let year = (item["year"] as? String) ?? (item["releaseInfo"] as? String)
                    let backdrop = URL(string: "https://images.metahub.space/background/big/\(imdbId)/img")

                    list.append(TMDBMediaItem(
                        id: imdbId,
                        tmdbId: 0,
                        imdbId: imdbId,
                        title: title,
                        overview: overview,
                        posterURL: posterURL.flatMap { URL(string: $0) },
                        backdropURL: backdrop,
                        rating: rating,
                        releaseYear: year,
                        type: catalogType
                    ))
                }
                await MainActor.run { self.recommendationsCache[cleanId] = list }
                return list
            }
        }
        return []
    }

    // MARK: - Top 10 Trending (True Widescreen Backdrops)

    /// Fetches the real Global Top 10 Trending Movies & TV Shows with authentic backdrops
    func fetchTopTrending() async -> [TMDBMediaItem] {
        if !trendingCache.isEmpty && Date().timeIntervalSince(lastTrendingFetch) < 3600 {
            return trendingCache
        }

        // 1. If custom TMDB key is set, query TMDB trending
        if !activeTMDBKey.isEmpty, let url = URL(string: "https://api.themoviedb.org/3/trending/all/day?api_key=\(activeTMDBKey)") {
            if let (data, _) = try? await session.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {
                var list: [TMDBMediaItem] = []
                for item in results.prefix(10) {
                    guard let tmdbId = item["id"] as? Int else { continue }
                    let mediaType = (item["media_type"] as? String) ?? "movie"
                    let isMovie = mediaType != "tv"
                    let title = (item["title"] as? String) ?? (item["name"] as? String) ?? "Featured"
                    let overview = item["overview"] as? String
                    let posterPath = item["poster_path"] as? String
                    let backdropPath = item["backdrop_path"] as? String
                    let poster = posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
                    let backdrop = backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") }
                    let ratingVal = item["vote_average"] as? Double
                    let ratingStr = ratingVal.map { String(format: "%.1f", $0) }
                    let dateStr = (item["release_date"] as? String) ?? (item["first_air_date"] as? String)
                    let year = dateStr.flatMap { String($0.prefix(4)) }

                    list.append(TMDBMediaItem(
                        id: "tmdb:\(tmdbId)",
                        tmdbId: tmdbId,
                        imdbId: nil,
                        title: title,
                        overview: overview,
                        posterURL: poster,
                        backdropURL: backdrop,
                        rating: ratingStr,
                        releaseYear: year,
                        type: isMovie ? "movie" : "series"
                    ))
                }
                if !list.isEmpty {
                    await MainActor.run {
                        self.trendingCache = list
                        self.lastTrendingFetch = Date()
                    }
                    return list
                }
            }
        }

        // 2. Cinemeta Top Movies & Series catalogs (official Stremio rankings with Metahub backdrops)
        guard let url = URL(string: "https://cinemeta-catalogs.strem.io/top/catalog/movie/top.json") else { return [] }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let metas = json["metas"] as? [[String: Any]] else { return [] }

            var list: [TMDBMediaItem] = []
            for item in metas.prefix(10) {
                guard let imdbId = item["imdb_id"] as? String else { continue }
                let title = (item["name"] as? String) ?? "Featured"
                let overview = item["description"] as? String
                let posterURL = item["poster"] as? String
                let rating = item["imdbRating"] as? String
                let year = (item["year"] as? String) ?? (item["releaseInfo"] as? String)
                let type = (item["type"] as? String) ?? "movie"
                let backdrop = URL(string: "https://images.metahub.space/background/big/\(imdbId)/img")

                list.append(TMDBMediaItem(
                    id: imdbId,
                    tmdbId: 0,
                    imdbId: imdbId,
                    title: title,
                    overview: overview,
                    posterURL: posterURL.flatMap { URL(string: $0) },
                    backdropURL: backdrop,
                    rating: rating,
                    releaseYear: year,
                    type: type
                ))
            }
            await MainActor.run {
                self.trendingCache = list
                self.lastTrendingFetch = Date()
            }
            return list
        } catch {
            return []
        }
    }

    // MARK: - MDBList API Integration

    /// Queries MDBList for comprehensive ratings and scores
    func fetchMDBListInfo(for imdbId: String) async -> [String: Any]? {
        let key = AppSettings.shared.mdblistApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let url = URL(string: "https://mdblist.com/api/?apikey=\(key)&i=\(imdbId)") else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    // MARK: - TMDB Lookup Helper

    private func resolveTMDBInfo(for id: String) async -> (id: Int, isMovie: Bool)? {
        if let cached = tmdbIdCache[id] { return cached }
        guard !activeTMDBKey.isEmpty else { return nil }

        if id.hasPrefix("tmdb:"), let rawId = Int(id.dropFirst(5)) {
            let res = (id: rawId, isMovie: true)
            await MainActor.run { self.tmdbIdCache[id] = res }
            return res
        }

        guard let url = URL(string: "https://api.themoviedb.org/3/find/\(id)?api_key=\(activeTMDBKey)&external_source=imdb_id") else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            if let movies = json["movie_results"] as? [[String: Any]], let first = movies.first, let tId = first["id"] as? Int {
                let res = (id: tId, isMovie: true)
                await MainActor.run { self.tmdbIdCache[id] = res }
                return res
            }
            if let tvs = json["tv_results"] as? [[String: Any]], let first = tvs.first, let tId = first["id"] as? Int {
                let res = (id: tId, isMovie: false)
                await MainActor.run { self.tmdbIdCache[id] = res }
                return res
            }
        } catch {}
        return nil
    }
}
