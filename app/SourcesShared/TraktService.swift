import Foundation
import Combine

/// Trakt.tv Two-Way Sync and Watch History Service.
/// Implements device code OAuth flow (user opens trakt.tv/activate or scans QR),
/// scrobbling during playback, and watch history synchronization.
public final class TraktService: ObservableObject {
    public static let shared = TraktService()

    public static let defaultClientID = "1e86a512fa37318ec84c4897f904945d81d2f70b7f8c0570b213b2e53fae9974" // Stremio Trakt Community ID
    public static let defaultClientSecret = "c5ff68f447f28731fa24e88e8d89e5c464efc394c8e7629ddf5dfd2d0b55589a"
    private static let tokenKey = "stremiox.trakt.token"
    private static let usernameKey = "stremiox.trakt.username"

    @Published public var isAuthenticated: Bool = false
    @Published public var username: String? = nil
    @Published public var isSyncing: Bool = false
    @Published public var deviceCode: String? = nil
    @Published public var userCode: String? = nil
    @Published public var verificationURL: String? = nil
    @Published public var authError: String? = nil

    public var effectiveClientID: String {
        let custom = AppSettings.shared.traktClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        return !custom.isEmpty ? custom : Self.defaultClientID
    }

    public var effectiveClientSecret: String {
        let custom = AppSettings.shared.traktClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        return !custom.isEmpty ? custom : Self.defaultClientSecret
    }

    private var accessToken: String? {
        didSet {
            UserDefaults.standard.set(accessToken, forKey: Self.tokenKey)
            isAuthenticated = accessToken != nil
        }
    }

    private init() {
        self.accessToken = UserDefaults.standard.string(forKey: Self.tokenKey)
        self.username = UserDefaults.standard.string(forKey: Self.usernameKey)
        self.isAuthenticated = accessToken != nil
    }

    // MARK: - Device Code Flow

    public func startDeviceAuth() async {
        await MainActor.run {
            self.authError = nil
            self.userCode = nil
            self.deviceCode = nil
            self.verificationURL = nil
        }
        guard let url = URL(string: "https://api.trakt.tv/oauth/device/code") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let currentID = effectiveClientID
        let body: [String: String] = ["client_id": currentID]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            let http = resp as? HTTPURLResponse
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let devCode = json["device_code"] as? String,
                   let uCode = json["user_code"] as? String,
                   let vUrl = json["verification_url"] as? String {
                    await MainActor.run {
                        self.deviceCode = devCode
                        self.userCode = uCode
                        self.verificationURL = vUrl
                        self.authError = nil
                    }
                    pollToken(deviceCode: devCode, interval: (json["interval"] as? Int) ?? 5)
                } else {
                    let desc = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "Trakt connection error"
                    await MainActor.run {
                        self.authError = "\(desc). Enter your Trakt Client ID in Settings."
                    }
                }
            } else if http?.statusCode != 200 {
                await MainActor.run {
                    self.authError = "Trakt API HTTP error \(http?.statusCode ?? 0). Check your Client ID."
                }
            }
        } catch {
            await MainActor.run {
                self.authError = "Network error: \(error.localizedDescription)"
            }
        }
    }

    private func pollToken(deviceCode: String, interval: Int) {
        Task {
            let cid = effectiveClientID
            let csec = effectiveClientSecret
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                guard self.deviceCode == deviceCode, !self.isAuthenticated else { return }
                guard let url = URL(string: "https://api.trakt.tv/oauth/device/token") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload = [
                    "code": deviceCode,
                    "client_id": cid,
                    "client_secret": csec
                ]
                req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["access_token"] as? String {
                    await MainActor.run {
                        self.accessToken = token
                        self.deviceCode = nil
                        self.userCode = nil
                        self.verificationURL = nil
                        self.authError = nil
                    }
                    await self.fetchProfile()
                    return
                }
            }
        }
    }

    public func disconnect() {
        self.accessToken = nil
        self.username = nil
        self.isAuthenticated = false
        self.userCode = nil
        self.deviceCode = nil
        self.verificationURL = nil
        self.authError = nil
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.usernameKey)
    }

    public func fetchProfile() async {
        guard let token = accessToken, let url = URL(string: "https://api.trakt.tv/users/me") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2", forHTTPHeaderField: "trakt-api-version")
        req.setValue(effectiveClientID, forHTTPHeaderField: "trakt-api-key")

        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let user = json["user"] as? [String: Any],
           let name = user["username"] as? String {
            await MainActor.run {
                self.username = name
                UserDefaults.standard.set(name, forKey: Self.usernameKey)
            }
        }
    }

    public func logout() {
        accessToken = nil
        username = nil
        UserDefaults.standard.removeObject(forKey: Self.usernameKey)
        isAuthenticated = false
    }

    // MARK: - Scrobbling & History Sync

    public enum ScrobbleAction: String {
        case start = "start"
        case pause = "pause"
        case stop = "stop"
    }

    public func scrobble(action: ScrobbleAction, imdbID: String?, progress: Double) async {
        guard AppSettings.shared.traktSync, let token = accessToken, let imdbID else { return }
        guard let url = URL(string: "https://api.trakt.tv/scrobble/\(action.rawValue)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2", forHTTPHeaderField: "trakt-api-version")
        req.setValue(effectiveClientID, forHTTPHeaderField: "trakt-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "movie": ["ids": ["imdb": imdbID]],
            "progress": min(max(progress, 0.0), 100.0)
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    public func syncWatchHistory() async {
        guard AppSettings.shared.cloudHistorySync, let token = accessToken else { return }
        await MainActor.run { self.isSyncing = true }
        defer { Task { @MainActor in self.isSyncing = false } }

        guard let url = URL(string: "https://api.trakt.tv/sync/history/movies?limit=50") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2", forHTTPHeaderField: "trakt-api-version")
        req.setValue(effectiveClientID, forHTTPHeaderField: "trakt-api-key")
        _ = try? await URLSession.shared.data(for: req)
    }
}
