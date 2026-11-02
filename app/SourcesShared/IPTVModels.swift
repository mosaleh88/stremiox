import Foundation

// MARK: - IPTV Configuration & State

public struct IPTVConfig: Codable, Equatable, Sendable {
    public var serverURL: String
    public var username: String
    public var password: String
    public var serverName: String?
    public var expiryDate: String?
    public var maxConnections: String?
    public var activeCons: String?
    public var isConnected: Bool

    public static let storageKey = "stremiox.iptv.config"

    public init(serverURL: String = "",
                username: String = "",
                password: String = "",
                serverName: String? = nil,
                expiryDate: String? = nil,
                maxConnections: String? = nil,
                activeCons: String? = nil,
                isConnected: Bool = false) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.serverName = serverName
        self.expiryDate = expiryDate
        self.maxConnections = maxConnections
        self.activeCons = activeCons
        self.isConnected = isConnected
    }

    public static var current: IPTVConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(IPTVConfig.self, from: data) else {
            return IPTVConfig()
        }
        return config
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    public var normalizedBaseURL: String {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

// MARK: - IPTV Xtream Data Models

public struct IPTVCategory: Identifiable, Codable, Hashable {
    public let categoryId: String
    public let categoryName: String

    public var id: String { categoryId }

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
    }

    public init(categoryId: String, categoryName: String) {
        self.categoryId = categoryId
        self.categoryName = categoryName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let idStr = try? container.decode(String.self, forKey: .categoryId) {
            self.categoryId = idStr
        } else if let idInt = try? container.decode(Int.self, forKey: .categoryId) {
            self.categoryId = String(idInt)
        } else {
            self.categoryId = UUID().uuidString
        }
        self.categoryName = (try? container.decode(String.self, forKey: .categoryName)) ?? "Unknown"
    }
}

public struct IPTVLiveStream: Identifiable, Codable, Hashable {
    public let streamId: Int
    public let num: Int?
    public let name: String
    public let streamIcon: String?
    public let categoryId: String?
    public let epgChannelId: String?

    public var id: Int { streamId }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case num
        case name
        case streamIcon = "stream_icon"
        case categoryId = "category_id"
        case epgChannelId = "epg_channel_id"
    }

    public init(streamId: Int, num: Int?, name: String, streamIcon: String?, categoryId: String?, epgChannelId: String?) {
        self.streamId = streamId
        self.num = num
        self.name = name
        self.streamIcon = streamIcon
        self.categoryId = categoryId
        self.epgChannelId = epgChannelId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let sId = try? container.decode(Int.self, forKey: .streamId) {
            self.streamId = sId
        } else if let sStr = try? container.decode(String.self, forKey: .streamId), let sId = Int(sStr) {
            self.streamId = sId
        } else {
            self.streamId = 0
        }
        self.num = try? container.decode(Int.self, forKey: .num)
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Channel"
        self.streamIcon = try? container.decode(String.self, forKey: .streamIcon)
        if let catStr = try? container.decode(String.self, forKey: .categoryId) {
            self.categoryId = catStr
        } else if let catInt = try? container.decode(Int.self, forKey: .categoryId) {
            self.categoryId = String(catInt)
        } else {
            self.categoryId = nil
        }
        self.epgChannelId = try? container.decode(String.self, forKey: .epgChannelId)
    }
}

public struct IPTVVODStream: Identifiable, Codable, Hashable {
    public let streamId: Int
    public let name: String
    public let streamIcon: String?
    public let rating: String?
    public let categoryId: String?
    public let containerExtension: String?

    public var id: Int { streamId }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case rating
        case categoryId = "category_id"
        case containerExtension = "container_extension"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let sId = try? container.decode(Int.self, forKey: .streamId) {
            self.streamId = sId
        } else if let sStr = try? container.decode(String.self, forKey: .streamId), let sId = Int(sStr) {
            self.streamId = sId
        } else {
            self.streamId = 0
        }
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Movie"
        self.streamIcon = try? container.decode(String.self, forKey: .streamIcon)
        if let rStr = try? container.decode(String.self, forKey: .rating) {
            self.rating = rStr
        } else if let rDouble = try? container.decode(Double.self, forKey: .rating) {
            self.rating = String(format: "%.1f", rDouble)
        } else {
            self.rating = nil
        }
        if let catStr = try? container.decode(String.self, forKey: .categoryId) {
            self.categoryId = catStr
        } else if let catInt = try? container.decode(Int.self, forKey: .categoryId) {
            self.categoryId = String(catInt)
        } else {
            self.categoryId = nil
        }
        self.containerExtension = try? container.decode(String.self, forKey: .containerExtension)
    }
}

public struct IPTVSeries: Identifiable, Codable, Hashable {
    public let seriesId: Int
    public let name: String
    public let cover: String?
    public let plot: String?
    public let rating: String?
    public let categoryId: String?

    public var id: Int { seriesId }

    enum CodingKeys: String, CodingKey {
        case seriesId = "series_id"
        case name
        case cover
        case plot
        case rating
        case categoryId = "category_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let sId = try? container.decode(Int.self, forKey: .seriesId) {
            self.seriesId = sId
        } else if let sStr = try? container.decode(String.self, forKey: .seriesId), let sId = Int(sStr) {
            self.seriesId = sId
        } else {
            self.seriesId = 0
        }
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Series"
        self.cover = try? container.decode(String.self, forKey: .cover)
        self.plot = try? container.decode(String.self, forKey: .plot)
        if let rStr = try? container.decode(String.self, forKey: .rating) {
            self.rating = rStr
        } else if let rDouble = try? container.decode(Double.self, forKey: .rating) {
            self.rating = String(format: "%.1f", rDouble)
        } else {
            self.rating = nil
        }
        if let catStr = try? container.decode(String.self, forKey: .categoryId) {
            self.categoryId = catStr
        } else if let catInt = try? container.decode(Int.self, forKey: .categoryId) {
            self.categoryId = String(catInt)
        } else {
            self.categoryId = nil
        }
    }
}

public struct IPTVEpisode: Identifiable, Codable, Hashable {
    public let id: String
    public let episodeNum: Int
    public let title: String
    public let containerExtension: String?
    public let info: IPTVEpisodeInfo?

    public struct IPTVEpisodeInfo: Codable, Hashable {
        public let plot: String?
        public let duration: String?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case episodeNum = "episode_num"
        case title
        case containerExtension = "container_extension"
        case info
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let idStr = try? container.decode(String.self, forKey: .id) {
            self.id = idStr
        } else if let idInt = try? container.decode(Int.self, forKey: .id) {
            self.id = String(idInt)
        } else {
            self.id = UUID().uuidString
        }
        if let epInt = try? container.decode(Int.self, forKey: .episodeNum) {
            self.episodeNum = epInt
        } else if let epStr = try? container.decode(String.self, forKey: .episodeNum), let epInt = Int(epStr) {
            self.episodeNum = epInt
        } else {
            self.episodeNum = 1
        }
        self.title = (try? container.decode(String.self, forKey: .title)) ?? "Episode \(self.episodeNum)"
        self.containerExtension = try? container.decode(String.self, forKey: .containerExtension)
        self.info = try? container.decode(IPTVEpisodeInfo.self, forKey: .info)
    }
}

public struct IPTVSeriesSeason: Identifiable, Hashable {
    public let seasonNumber: Int
    public let episodes: [IPTVEpisode]

    public var id: Int { seasonNumber }
}

public struct IPTVAccountAuthResponse: Decodable {
    public struct UserInfo: Decodable {
        public let username: String?
        public let status: String?
        public let auth: Int?
        public let expDate: String?
        public let activeCons: String?
        public let maxConnections: String?

        enum CodingKeys: String, CodingKey {
            case username
            case status
            case auth
            case expDate = "exp_date"
            case activeCons = "active_cons"
            case maxConnections = "max_connections"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.username = try? container.decode(String.self, forKey: .username)
            self.status = try? container.decode(String.self, forKey: .status)
            if let aInt = try? container.decode(Int.self, forKey: .auth) {
                self.auth = aInt
            } else if let aStr = try? container.decode(String.self, forKey: .auth), let aInt = Int(aStr) {
                self.auth = aInt
            } else {
                self.auth = nil
            }
            if let eStr = try? container.decode(String.self, forKey: .expDate) {
                self.expDate = eStr
            } else if let eInt = try? container.decode(Int.self, forKey: .expDate) {
                self.expDate = String(eInt)
            } else if let eDbl = try? container.decode(Double.self, forKey: .expDate) {
                self.expDate = String(Int(eDbl))
            } else {
                self.expDate = nil
            }
            if let acStr = try? container.decode(String.self, forKey: .activeCons) {
                self.activeCons = acStr
            } else if let acInt = try? container.decode(Int.self, forKey: .activeCons) {
                self.activeCons = String(acInt)
            } else {
                self.activeCons = nil
            }
            if let mcStr = try? container.decode(String.self, forKey: .maxConnections) {
                self.maxConnections = mcStr
            } else if let mcInt = try? container.decode(Int.self, forKey: .maxConnections) {
                self.maxConnections = String(mcInt)
            } else {
                self.maxConnections = nil
            }
        }
    }

    public struct ServerInfo: Decodable {
        public let url: String?
        public let port: String?
        public let serverProtocol: String?
        public let timezone: String?

        enum CodingKeys: String, CodingKey {
            case url
            case port
            case serverProtocol = "server_protocol"
            case timezone
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.url = try? container.decode(String.self, forKey: .url)
            if let pStr = try? container.decode(String.self, forKey: .port) {
                self.port = pStr
            } else if let pInt = try? container.decode(Int.self, forKey: .port) {
                self.port = String(pInt)
            } else {
                self.port = nil
            }
            self.serverProtocol = try? container.decode(String.self, forKey: .serverProtocol)
            self.timezone = try? container.decode(String.self, forKey: .timezone)
        }
    }

    public let userInfo: UserInfo?
    public let serverInfo: ServerInfo?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }
}
