import Foundation
import Network

public final class IPTVWebServer: ObservableObject {
    public static let shared = IPTVWebServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var localIP: String = "127.0.0.1"
    public let port: UInt16 = 9898

    private var listener: NWListener?
    public var onConfigurationSaved: ((IPTVConfig) -> Void)?

    private init() {
        self.localIP = Self.getWiFiAddress() ?? "127.0.0.1"
    }

    public var serverURLString: String {
        "http://\(localIP):\(port)"
    }

    public func start() {
        guard !isRunning else { return }
        self.localIP = Self.getWiFiAddress() ?? "127.0.0.1"

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                    case .failed, .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            print("[IPTVWebServer] Failed to start listener: \(error)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        var accumulatedData = Data()

        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self = self else { connection.cancel(); return }
                if let data = data, !data.isEmpty {
                    accumulatedData.append(data)
                }

                if error != nil {
                    connection.cancel()
                    return
                }

                let str = String(decoding: accumulatedData, as: UTF8.self)
                guard let headerEndRange = str.range(of: "\r\n\r\n") else {
                    if isComplete {
                        connection.cancel()
                    } else {
                        readMore()
                    }
                    return
                }

                let headersPart = String(str[..<headerEndRange.lowerBound])
                let bodyPart = String(str[headerEndRange.upperBound...])

                // Check Content-Length to ensure body is completely received
                var expectedContentLength: Int? = nil
                for line in headersPart.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                        expectedContentLength = Int(valStr)
                    }
                }

                if let expected = expectedContentLength, bodyPart.utf8.count < expected && !isComplete {
                    readMore()
                    return
                }

                self.dispatchHTTPRequest(headersPart: headersPart, bodyPart: bodyPart, connection: connection)
            }
        }

        readMore()
    }

    private func dispatchHTTPRequest(headersPart: String, bodyPart: String, connection: NWConnection) {
        let lines = headersPart.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }

        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        if method == "OPTIONS" {
            let response = "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\nAccess-Control-Max-Age: 86400\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8), completion: .contentProcessed({ _ in
                connection.cancel()
            }))
            return
        }

        if method == "GET" && path == "/api/addons" {
            let addons = CoreBridge.shared.addons.map { addon in
                [
                    "name": addon.manifest.name,
                    "description": addon.capabilities,
                    "transportUrl": addon.transportUrl,
                    "isProtected": addon.isProtected,
                    "host": addon.host
                ] as [String: Any]
            }
            sendJSON(connection, status: 200, json: ["addons": addons])
            return
        }

        if method == "GET" && path == "/api/settings" {
            let s = AppSettings.shared
            sendJSON(connection, status: 200, json: [
                "tmdbApiKey": s.tmdbApiKey,
                "mdblistApiKey": s.mdblistApiKey,
                "traktClientId": s.traktClientId,
                "traktClientSecret": s.traktClientSecret,
                "invidiousInstance": s.invidiousInstance,
                "matchContent": s.matchContent,
                "bingeMode": s.bingeMode,
                "backdropTrailers": s.backdropTrailers,
                "subOffsetAuto": s.subOffsetAuto,
                "quickGuideDrawer": s.quickGuideDrawer,
                "appearanceMode": s.appearanceMode.rawValue,
                "liquidGlass": s.liquidGlass,
                "modularHomeRails": s.modularHomeRails,
                "fullBleedBanners": s.fullBleedBanners,
                "smartRecommendations": s.smartRecommendations,
                "liveHorizontalCategories": s.liveHorizontalCategories,
                "channelSortAscending": s.channelSortAscending,
                "traktSync": s.traktSync,
                "cloudHistorySync": s.cloudHistorySync
            ])
            return
        }

        if method == "GET" && (path == "/" || path.hasPrefix("/?") || path.hasPrefix("/settings") || path.hasPrefix("/addons") || path.hasPrefix("/iptv") || path.hasPrefix("/services")) {
            let initialTab = path.contains("settings") ? "settings" : (path.contains("iptv") ? "iptv" : (path.contains("services") ? "services" : "settings"))
            let html = self.renderHTMLPage(initialTab: initialTab)
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed({ _ in
                connection.cancel()
            }))
            return
        }

        if method == "POST" && (path == "/save" || path == "/connect") {
            self.processSaveRequest(body: bodyPart, connection: connection)
            return
        }

        if method == "POST" && path == "/api/addons/install" {
            self.processAddonInstall(body: bodyPart, connection: connection)
            return
        }

        if method == "POST" && path == "/api/addons/uninstall" {
            self.processAddonUninstall(body: bodyPart, connection: connection)
            return
        }

        if method == "POST" && path == "/api/settings/save" {
            self.processSettingsSave(body: bodyPart, connection: connection)
            return
        }

        let notFound = "HTTP/1.1 404 Not Found\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(notFound.utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func processSaveRequest(body: String, connection: NWConnection) {
        guard let (server, user, pass) = parsePayload(from: body) else {
            sendJSON(connection, status: 400, json: ["error": "Please provide server URL, username, and password."])
            return
        }

        Task {
            do {
                let config = try await IPTVService.shared.connect(serverURL: server, username: user, password: pass)
                self.sendJSON(connection, status: 200, json: [
                    "status": "ok",
                    "server": config.serverName ?? "",
                    "expiry": config.expiryDate ?? "Active"
                ])
                await MainActor.run {
                    self.onConfigurationSaved?(config)
                }
            } catch {
                self.sendJSON(connection, status: 400, json: ["error": error.localizedDescription])
            }
        }
    }

    private func parsePayload(from body: String) -> (server: String, user: String, pass: String)? {
        struct SavePayload: Decodable {
            let server: String?
            let username: String?
            let password: String?
        }

        if let data = body.data(using: .utf8),
           let payload = try? JSONDecoder().decode(SavePayload.self, from: data),
           let server = payload.server?.trimmingCharacters(in: .whitespacesAndNewlines), !server.isEmpty,
           let user = payload.username?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty,
           let pass = payload.password?.trimmingCharacters(in: .whitespacesAndNewlines), !pass.isEmpty {
            return (server, user, pass)
        }

        var dict: [String: String] = [:]
        for pair in body.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2,
               let key = kv[0].removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines),
               let val = kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines) {
                dict[key.lowercased()] = val
            }
        }

        if let server = dict["server"], !server.isEmpty,
           let user = dict["username"] ?? dict["user"], !user.isEmpty,
           let pass = dict["password"] ?? dict["pass"], !pass.isEmpty {
            return (server, user, pass)
        }

        return nil
    }

    private func processAddonInstall(body: String, connection: NWConnection) {
        struct InstallPayload: Decodable {
            let url: String?
        }
        guard let data = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(InstallPayload.self, from: data),
              let url = payload.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            sendJSON(connection, status: 400, json: ["error": "Please provide a valid addon manifest URL."])
            return
        }

        Task {
            do {
                try await CoreBridge.shared.installAddon(manifestURL: url)
                self.sendJSON(connection, status: 200, json: ["status": "ok", "message": "Add-on installed successfully!"])
            } catch {
                self.sendJSON(connection, status: 400, json: ["error": error.localizedDescription])
            }
        }
    }

    private func processAddonUninstall(body: String, connection: NWConnection) {
        struct UninstallPayload: Decodable {
            let transportUrl: String?
        }
        guard let data = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(UninstallPayload.self, from: data),
              let transportUrl = payload.transportUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !transportUrl.isEmpty else {
            sendJSON(connection, status: 400, json: ["error": "Please provide transportUrl."])
            return
        }

        Task { @MainActor in
            if let addon = CoreBridge.shared.addons.first(where: { $0.transportUrl == transportUrl }) {
                CoreBridge.shared.uninstallAddon(addon)
                self.sendJSON(connection, status: 200, json: ["status": "ok", "message": "Add-on removed."])
            } else {
                self.sendJSON(connection, status: 404, json: ["error": "Add-on not found."])
            }
        }
    }

    private func processSettingsSave(body: String, connection: NWConnection) {
        struct SettingsPayload: Decodable {
            let tmdbApiKey: String?
            let mdblistApiKey: String?
            let traktClientId: String?
            let traktClientSecret: String?
            let invidiousInstance: String?
            let matchContent: Bool?
            let bingeMode: Bool?
            let backdropTrailers: Bool?
            let subOffsetAuto: Bool?
            let quickGuideDrawer: Bool?
            let appearanceMode: String?
            let liquidGlass: Bool?
            let modularHomeRails: Bool?
            let fullBleedBanners: Bool?
            let smartRecommendations: Bool?
            let liveHorizontalCategories: Bool?
            let channelSortAscending: Bool?
            let traktSync: Bool?
            let cloudHistorySync: Bool?
        }
        guard let data = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SettingsPayload.self, from: data) else {
            sendJSON(connection, status: 400, json: ["error": "Invalid settings payload."])
            return
        }

        Task { @MainActor in
            let settings = AppSettings.shared
            if let tmdb = payload.tmdbApiKey { settings.tmdbApiKey = tmdb.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let mdb = payload.mdblistApiKey { settings.mdblistApiKey = mdb.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let tId = payload.traktClientId { settings.traktClientId = tId.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let tSec = payload.traktClientSecret { settings.traktClientSecret = tSec.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let inv = payload.invidiousInstance {
                let cleanInv = inv.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanInv.isEmpty { settings.invidiousInstance = cleanInv }
            }
            if let mc = payload.matchContent { settings.matchContent = mc }
            if let bm = payload.bingeMode { settings.bingeMode = bm }
            if let bt = payload.backdropTrailers { settings.backdropTrailers = bt }
            if let so = payload.subOffsetAuto { settings.subOffsetAuto = so }
            if let qg = payload.quickGuideDrawer { settings.quickGuideDrawer = qg }
            if let am = payload.appearanceMode, let mode = AppSettings.AppearanceMode(rawValue: am) { settings.appearanceMode = mode }
            if let lg = payload.liquidGlass { settings.liquidGlass = lg }
            if let mr = payload.modularHomeRails { settings.modularHomeRails = mr }
            if let fb = payload.fullBleedBanners { settings.fullBleedBanners = fb }
            if let sr = payload.smartRecommendations { settings.smartRecommendations = sr }
            if let lc = payload.liveHorizontalCategories { settings.liveHorizontalCategories = lc }
            if let ca = payload.channelSortAscending { settings.channelSortAscending = ca }
            if let ts = payload.traktSync { settings.traktSync = ts }
            if let ch = payload.cloudHistorySync { settings.cloudHistorySync = ch }

            self.sendJSON(connection, status: 200, json: ["status": "ok", "message": "Settings saved to Apple TV!"])
        }
    }

    private func sendJSON(_ connection: NWConnection, status: Int, json: [String: Any]) {
        let jsonData = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let statusText = status == 200 ? "OK" : "Bad Request"
        let response = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\nContent-Length: \(jsonData.count)\r\nConnection: close\r\n\r\n"
        var fullData = Data(response.utf8)
        fullData.append(jsonData)
        connection.send(content: fullData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func renderHTMLPage(initialTab: String = "addons") -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <title>Xtv Manager</title>
            <style>
                * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
                body {
                    margin: 0;
                    padding: 20px 16px;
                    background: #0B0E14;
                    color: #FFFFFF;
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    min-height: 100vh;
                }
                .container {
                    width: 100%;
                    max-width: 480px;
                }
                .header {
                    text-align: center;
                    margin-bottom: 20px;
                }
                .logo {
                    display: inline-block;
                    font-size: 26px;
                    font-weight: 800;
                    letter-spacing: -0.5px;
                }
                .logo span {
                    display: inline-block;
                    background: rgba(10, 132, 255, 0.2);
                    color: #0A84FF;
                    border: 1px solid rgba(10, 132, 255, 0.4);
                    border-radius: 6px;
                    padding: 1px 7px;
                    margin-left: 4px;
                    font-size: 18px;
                }
                .subtitle {
                    color: rgba(255, 255, 255, 0.6);
                    font-size: 14px;
                    margin-top: 6px;
                }
                .tabs {
                    display: flex;
                    background: rgba(255, 255, 255, 0.08);
                    border-radius: 12px;
                    padding: 4px;
                    margin-bottom: 20px;
                    gap: 4px;
                }
                .tab-btn {
                    flex: 1;
                    padding: 10px 4px;
                    background: transparent;
                    border: none;
                    color: rgba(255, 255, 255, 0.6);
                    font-size: 14px;
                    font-weight: 600;
                    border-radius: 8px;
                    cursor: pointer;
                    transition: all 0.2s;
                }
                .tab-btn.active {
                    background: #0A84FF;
                    color: #FFF;
                    box-shadow: 0 2px 8px rgba(10, 132, 255, 0.4);
                }
                .tab-content {
                    display: none;
                }
                .tab-content.active {
                    display: block;
                }
                .card {
                    background: rgba(255, 255, 255, 0.05);
                    border: 1px solid rgba(255, 255, 255, 0.1);
                    border-radius: 18px;
                    padding: 20px;
                    margin-bottom: 18px;
                    backdrop-filter: blur(20px);
                    -webkit-backdrop-filter: blur(20px);
                }
                .card h3 {
                    margin: 0 0 14px 0;
                    font-size: 17px;
                    font-weight: 700;
                    color: #FFF;
                }
                .form-group {
                    margin-bottom: 16px;
                }
                label {
                    display: block;
                    font-size: 12px;
                    font-weight: 600;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                    color: rgba(255, 255, 255, 0.7);
                    margin-bottom: 6px;
                }
                input {
                    width: 100%;
                    padding: 12px 14px;
                    background: rgba(0, 0, 0, 0.4);
                    border: 1px solid rgba(255, 255, 255, 0.15);
                    border-radius: 10px;
                    color: #FFF;
                    font-size: 15px;
                    outline: none;
                    transition: border-color 0.2s;
                }
                input:focus {
                    border-color: #0A84FF;
                }
                button.primary-btn {
                    width: 100%;
                    padding: 14px;
                    background: #0A84FF;
                    color: #FFF;
                    font-size: 16px;
                    font-weight: 700;
                    border: none;
                    border-radius: 10px;
                    cursor: pointer;
                    margin-top: 6px;
                }
                button.primary-btn:active {
                    opacity: 0.8;
                }
                .addon-item {
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    padding: 12px 0;
                    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
                }
                .addon-item:last-child {
                    border-bottom: none;
                }
                .addon-info {
                    flex: 1;
                    padding-right: 12px;
                }
                .addon-name {
                    font-size: 15px;
                    font-weight: 600;
                    color: #FFF;
                }
                .addon-desc {
                    font-size: 12px;
                    color: rgba(255, 255, 255, 0.5);
                    margin-top: 2px;
                    line-height: 1.3;
                }
                .addon-host {
                    font-size: 11px;
                    color: #0A84FF;
                    margin-top: 2px;
                    font-family: monospace;
                }
                .btn-delete {
                    background: rgba(255, 69, 58, 0.15);
                    color: #FF453A;
                    border: 1px solid rgba(255, 69, 58, 0.3);
                    border-radius: 8px;
                    padding: 6px 12px;
                    font-size: 12px;
                    font-weight: 600;
                    cursor: pointer;
                }
                .switch {
                    position: relative;
                    display: inline-block;
                    width: 48px;
                    height: 28px;
                    flex-shrink: 0;
                }
                .switch input { opacity: 0; width: 0; height: 0; }
                .slider {
                    position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0;
                    background-color: rgba(255, 255, 255, 0.2);
                    transition: .25s; border-radius: 28px;
                }
                .slider:before {
                    position: absolute; content: ""; height: 22px; width: 22px; left: 3px; bottom: 3px;
                    background-color: white; transition: .25s; border-radius: 50%;
                }
                input:checked + .slider { background-color: #30D158; }
                input:checked + .slider:before { transform: translateX(20px); }
                .setting-row {
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    padding: 13px 0;
                    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
                    gap: 12px;
                }
                .setting-row:last-child { border-bottom: none; }
                .setting-info { flex: 1; }
                .setting-title { font-size: 15px; font-weight: 600; color: #FFF; }
                .setting-desc { font-size: 12px; color: rgba(255, 255, 255, 0.5); margin-top: 2px; line-height: 1.3; }
                select.form-select {
                    width: 100%;
                    padding: 12px 14px;
                    background: rgba(0, 0, 0, 0.4);
                    border: 1px solid rgba(255, 255, 255, 0.15);
                    border-radius: 10px;
                    color: #FFF;
                    font-size: 15px;
                    outline: none;
                }
                .alert {
                    display: none;
                    padding: 12px;
                    border-radius: 10px;
                    font-size: 13px;
                    margin-top: 14px;
                    text-align: center;
                    word-break: break-word;
                }
                .alert.error {
                    background: rgba(255, 69, 58, 0.15);
                    border: 1px solid rgba(255, 69, 58, 0.3);
                    color: #FF453A;
                }
                .alert.success {
                    background: rgba(48, 209, 88, 0.15);
                    border: 1px solid rgba(48, 209, 88, 0.3);
                    color: #30D158;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <div class="logo">Xtv<span>PRO</span></div>
                    <div class="subtitle">Apple TV Companion Portal</div>
                </div>

                <div class="tabs">
                    <button class="tab-btn active" onclick="switchTab('settings')">⚙️ Settings</button>
                    <button class="tab-btn" onclick="switchTab('services')">🔑 Keys</button>
                    <button class="tab-btn" onclick="switchTab('addons')">🧩 Add-ons</button>
                    <button class="tab-btn" onclick="switchTab('iptv')">📺 IPTV</button>
                </div>

                <!-- ALL SETTINGS TAB -->
                <div id="tab-settings" class="tab-content active">
                    <form id="appSettingsForm">
                        <div class="card">
                            <h3>🎬 Playback & Video</h3>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Match Dynamic Range & Frame Rate</div>
                                    <div class="setting-desc">Switches HDMI output to 24p/SDR/HDR to match video source.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="matchContent"><span class="slider"></span></label>
                            </div>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Auto-Play Next Episode (Binge Mode)</div>
                                    <div class="setting-desc">Seamlessly queues up the next episode when credits roll.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="bingeMode"><span class="slider"></span></label>
                            </div>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Inline Video Trailers</div>
                                    <div class="setting-desc">Plays trailers inline on dwelling over hero & card items.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="backdropTrailers"><span class="slider"></span></label>
                            </div>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Automatic Subtitle Offset</div>
                                    <div class="setting-desc">Automatically adjusts subtitle delay based on cloud timing.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="subOffsetAuto"><span class="slider"></span></label>
                            </div>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Quick Guide Drawer</div>
                                    <div class="setting-desc">Shows live EPG channel drawer on swiping during Live TV.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="quickGuideDrawer"><span class="slider"></span></label>
                            </div>
                        </div>

                        <div class="card">
                            <h3>🎨 Appearance & Layout</h3>
                            <div class="form-group" style="margin-bottom: 14px;">
                                <label for="appearanceMode">Theme Mode</label>
                                <select id="appearanceMode" class="form-select">
                                    <option value="dark">Dark (Cinema)</option>
                                    <option value="light">Light (Apple TV White)</option>
                                    <option value="auto">Automatic (System)</option>
                                </select>
                            </div>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Liquid Glass Visuals</div>
                                    <div class="setting-desc">Enables Apple TV frosted live blur materials (recommended for 4K).</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="liquidGlass"><span class="slider"></span></label>
                            </div>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Full-Bleed Banners (Top 10)</div>
                                    <div class="setting-desc">Shows the ranked Top 10 carousel rail on the Home page.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="fullBleedBanners"><span class="slider"></span></label>
                            </div>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Smart Recommendations</div>
                                    <div class="setting-desc">AI-powered recommendations based on your continue watching.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="smartRecommendations"><span class="slider"></span></label>
                            </div>
                        </div>

                        <div class="card">
                            <h3>📺 Live TV & Cloud Sync</h3>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Horizontal Live TV Categories</div>
                                    <div class="setting-desc">Display categories as top horizontal tabs rather than vertical list.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="liveHorizontalCategories"><span class="slider"></span></label>
                            </div>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Channel Sort Ascending</div>
                                    <div class="setting-desc">Sorts channels numerically and alphabetically A to Z.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="channelSortAscending"><span class="slider"></span></label>
                            </div>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Trakt.tv Scrobble Sync</div>
                                    <div class="setting-desc">Automatically marks watched movies and episodes to Trakt.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="traktSync"><span class="slider"></span></label>
                            </div>
                            <div class="setting-row">
                                <div class="setting-info">
                                    <div class="setting-title">Cloud History Sync</div>
                                    <div class="setting-desc">Syncs watch progress across your Apple TVs via iCloud.</div>
                                </div>
                                <label class="switch"><input type="checkbox" id="cloudHistorySync"><span class="slider"></span></label>
                            </div>
                        </div>

                        <button type="submit" id="saveAppSettingsBtn" class="primary-btn">Save Settings to Apple TV</button>
                        <div id="appSettingsAlert" class="alert"></div>
                    </form>
                </div>

                <!-- ADD-ONS TAB -->
                <div id="tab-addons" class="tab-content active">
                    <div class="card">
                        <h3>Install Stremio Add-on</h3>
                        <form id="installAddonForm">
                            <div class="form-group">
                                <label for="addonUrl">Manifest URL</label>
                                <input type="url" id="addonUrl" placeholder="https://.../manifest.json" required autocorrect="off" autocapitalize="none">
                            </div>
                            <button type="submit" id="installBtn" class="primary-btn">Install to Apple TV</button>
                            <div id="addonAlert" class="alert"></div>
                        </form>
                    </div>

                    <div class="card">
                        <h3>Installed Add-ons</h3>
                        <div id="addonsList">
                            <div style="color: rgba(255,255,255,0.5); font-size: 13px;">Loading add-ons…</div>
                        </div>
                    </div>
                </div>

                <!-- IPTV TAB -->
                <div id="tab-iptv" class="tab-content">
                    <div class="card">
                        <h3>IPTV Xtream Codes</h3>
                        <form id="iptvForm">
                            <div class="form-group">
                                <label for="server">Server Host / URL</label>
                                <input type="text" id="server" placeholder="http://provider.com:8080" required autocorrect="off" autocapitalize="none">
                            </div>
                            <div class="form-group">
                                <label for="username">Username</label>
                                <input type="text" id="username" placeholder="Username" required autocorrect="off" autocapitalize="none">
                            </div>
                            <div class="form-group">
                                <label for="password">Password</label>
                                <input type="password" id="password" placeholder="Password" required>
                            </div>
                            <button type="submit" id="iptvBtn" class="primary-btn">Connect to Apple TV</button>
                            <div id="iptvAlert" class="alert"></div>
                        </form>
                    </div>
                </div>

                <!-- SERVICES & INTEGRATIONS TAB -->
                <div id="tab-services" class="tab-content">
                    <div class="card">
                        <h3>API Keys & Gateways</h3>
                        <form id="settingsForm">
                            <div class="form-group">
                                <label for="tmdbKey">TMDB API Key (v3)</label>
                                <input type="text" id="tmdbKey" placeholder="Your TMDB 32-char API key" autocorrect="off" autocapitalize="none">
                            </div>
                            <div class="form-group">
                                <label for="mdblistKey">MDBList API Key</label>
                                <input type="text" id="mdblistKey" placeholder="Your MDBList API key" autocorrect="off" autocapitalize="none">
                            </div>
                            <div class="form-group">
                                <label for="traktClientId">Trakt.tv Client ID</label>
                                <input type="text" id="traktClientId" placeholder="Custom Trakt Client ID" autocorrect="off" autocapitalize="none">
                            </div>
                            <div class="form-group">
                                <label for="traktClientSecret">Trakt.tv Client Secret</label>
                                <input type="password" id="traktClientSecret" placeholder="Custom Trakt Client Secret">
                            </div>
                            <div class="form-group">
                                <label for="invidiousInstance">Trailer Proxy Gateway</label>
                                <input type="url" id="invidiousInstance" placeholder="https://yt.chocolatemoo53.com" autocorrect="off" autocapitalize="none">
                            </div>
                            <button type="submit" id="saveSettingsBtn" class="primary-btn">Save to Apple TV</button>
                            <div id="settingsAlert" class="alert"></div>
                        </form>
                    </div>
                </div>
            </div>

            <script>
                function switchTab(name) {
                    const tabs = ['settings', 'services', 'addons', 'iptv'];
                    document.querySelectorAll('.tab-btn').forEach((btn, idx) => {
                        btn.classList.toggle('active', tabs[idx] === name);
                    });
                    tabs.forEach(t => {
                        const el = document.getElementById('tab-' + t);
                        if (el) el.classList.toggle('active', t === name);
                    });
                    if (name === 'addons') loadAddons();
                    if (name === 'services' || name === 'settings') loadSettings();
                }

                function showAlert(elId, text, isError) {
                    const el = document.getElementById(elId);
                    el.textContent = text;
                    el.style.display = 'block';
                    el.className = isError ? 'alert error' : 'alert success';
                }

                function hideAlert(elId) {
                    const el = document.getElementById(elId);
                    el.style.display = 'none';
                }

                // Addons Management
                async function loadAddons() {
                    try {
                        const res = await fetch('/api/addons');
                        const data = await res.json();
                        const list = document.getElementById('addonsList');
                        if (!data.addons || data.addons.length === 0) {
                            list.innerHTML = '<div style="color: rgba(255,255,255,0.5); font-size: 13px;">No installed add-ons found.</div>';
                            return;
                        }
                        list.innerHTML = data.addons.map(a => `
                            <div class="addon-item">
                                <div class="addon-info">
                                    <div class="addon-name">${a.name}</div>
                                    <div class="addon-desc">${a.description || ''}</div>
                                    <div class="addon-host">${a.host || ''}</div>
                                </div>
                                ${a.isProtected ? '' : `<button class="btn-delete" onclick="uninstallAddon('${encodeURIComponent(a.transportUrl)}')">Remove</button>`}
                            </div>
                        `).join('');
                    } catch (e) {
                        document.getElementById('addonsList').innerHTML = '<div style="color: #FF453A; font-size: 13px;">Failed to load add-ons.</div>';
                    }
                }

                async function uninstallAddon(encodedUrl) {
                    if (!confirm('Remove this add-on from Apple TV?')) return;
                    try {
                        const transportUrl = decodeURIComponent(encodedUrl);
                        const res = await fetch('/api/addons/uninstall', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ transportUrl })
                        });
                        if (res.ok) {
                            loadAddons();
                        } else {
                            alert('Failed to remove add-on.');
                        }
                    } catch (e) {
                        alert('Network error.');
                    }
                }

                document.getElementById('installAddonForm').addEventListener('submit', async (e) => {
                    e.preventDefault();
                    const btn = document.getElementById('installBtn');
                    btn.disabled = true;
                    btn.innerText = 'Installing…';
                    hideAlert('addonAlert');

                    const url = document.getElementById('addonUrl').value.trim();
                    try {
                        const res = await fetch('/api/addons/install', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ url })
                        });
                        const data = await res.json();
                        if (res.ok) {
                            showAlert('addonAlert', 'Installed successfully to Apple TV!', false);
                            document.getElementById('addonUrl').value = '';
                            loadAddons();
                        } else {
                            throw new Error(data.error || 'Failed to install add-on');
                        }
                    } catch (err) {
                        showAlert('addonAlert', err.message, true);
                    } finally {
                        btn.disabled = false;
                        btn.innerText = 'Install to Apple TV';
                    }
                });

                // IPTV Form
                document.getElementById('iptvForm').addEventListener('submit', async (e) => {
                    e.preventDefault();
                    const btn = document.getElementById('iptvBtn');
                    btn.disabled = true;
                    btn.innerText = 'Connecting…';
                    hideAlert('iptvAlert');

                    const payload = {
                        server: document.getElementById('server').value.trim(),
                        username: document.getElementById('username').value.trim(),
                        password: document.getElementById('password').value.trim()
                    };

                    try {
                        const res = await fetch('/save', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify(payload)
                        });
                        const data = await res.json().catch(() => ({}));
                        if (res.ok) {
                            showAlert('iptvAlert', 'Connected successfully! Apple TV updated.', false);
                            btn.innerText = 'Connected!';
                        } else {
                            throw new Error(data.error || 'Connection failed');
                        }
                    } catch (err) {
                        showAlert('iptvAlert', err.message, true);
                        btn.disabled = false;
                        btn.innerText = 'Connect to Apple TV';
                    }
                });

                // Settings Form
                async function loadSettings() {
                    try {
                        const res = await fetch('/api/settings');
                        const data = await res.json();
                        // Text inputs
                        if (data.tmdbApiKey !== undefined) document.getElementById('tmdbKey').value = data.tmdbApiKey;
                        if (data.mdblistApiKey !== undefined) document.getElementById('mdblistKey').value = data.mdblistApiKey;
                        if (data.traktClientId !== undefined) document.getElementById('traktClientId').value = data.traktClientId;
                        if (data.traktClientSecret !== undefined) document.getElementById('traktClientSecret').value = data.traktClientSecret;
                        if (data.invidiousInstance !== undefined) document.getElementById('invidiousInstance').value = data.invidiousInstance;

                        // Checkboxes & Selects
                        const bools = [
                            'matchContent', 'bingeMode', 'backdropTrailers', 'subOffsetAuto',
                            'quickGuideDrawer', 'liquidGlass', 'fullBleedBanners', 'smartRecommendations',
                            'liveHorizontalCategories', 'channelSortAscending', 'traktSync', 'cloudHistorySync'
                        ];
                        bools.forEach(id => {
                            const el = document.getElementById(id);
                            if (el && data[id] !== undefined) el.checked = !!data[id];
                        });
                        if (data.appearanceMode) {
                            const sel = document.getElementById('appearanceMode');
                            if (sel) sel.value = data.appearanceMode;
                        }
                    } catch (e) {}
                }

                // App Settings Form submit
                document.getElementById('appSettingsForm').addEventListener('submit', async (e) => {
                    e.preventDefault();
                    const btn = document.getElementById('saveAppSettingsBtn');
                    btn.disabled = true;
                    btn.innerText = 'Saving…';
                    hideAlert('appSettingsAlert');

                    const payload = {
                        matchContent: document.getElementById('matchContent').checked,
                        bingeMode: document.getElementById('bingeMode').checked,
                        backdropTrailers: document.getElementById('backdropTrailers').checked,
                        subOffsetAuto: document.getElementById('subOffsetAuto').checked,
                        quickGuideDrawer: document.getElementById('quickGuideDrawer').checked,
                        appearanceMode: document.getElementById('appearanceMode').value,
                        liquidGlass: document.getElementById('liquidGlass').checked,
                        fullBleedBanners: document.getElementById('fullBleedBanners').checked,
                        smartRecommendations: document.getElementById('smartRecommendations').checked,
                        liveHorizontalCategories: document.getElementById('liveHorizontalCategories').checked,
                        channelSortAscending: document.getElementById('channelSortAscending').checked,
                        traktSync: document.getElementById('traktSync').checked,
                        cloudHistorySync: document.getElementById('cloudHistorySync').checked
                    };

                    try {
                        const res = await fetch('/api/settings/save', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify(payload)
                        });
                        if (res.ok) {
                            showAlert('appSettingsAlert', 'Settings saved to Apple TV!', false);
                        } else {
                            throw new Error('Failed to save settings');
                        }
                    } catch (err) {
                        showAlert('appSettingsAlert', err.message, true);
                    } finally {
                        btn.disabled = false;
                        btn.innerText = 'Save Settings to Apple TV';
                    }
                });

                document.getElementById('settingsForm').addEventListener('submit', async (e) => {
                    e.preventDefault();
                    const btn = document.getElementById('saveSettingsBtn');
                    btn.disabled = true;
                    btn.innerText = 'Saving…';
                    hideAlert('settingsAlert');

                    const payload = {
                        tmdbApiKey: document.getElementById('tmdbKey').value.trim(),
                        mdblistApiKey: document.getElementById('mdblistKey').value.trim(),
                        traktClientId: document.getElementById('traktClientId').value.trim(),
                        traktClientSecret: document.getElementById('traktClientSecret').value.trim(),
                        invidiousInstance: document.getElementById('invidiousInstance').value.trim()
                    };

                    try {
                        const res = await fetch('/api/settings/save', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify(payload)
                        });
                        if (res.ok) {
                            showAlert('settingsAlert', 'Keys saved to Apple TV!', false);
                        } else {
                            throw new Error('Failed to save keys');
                        }
                    } catch (err) {
                        showAlert('settingsAlert', err.message, true);
                    } finally {
                        btn.disabled = false;
                        btn.innerText = 'Save to Apple TV';
                    }
                });

                // Init tab
                switchTab('\(initialTab)');
            </script>
        </body>
        </html>
        """
    }

    public static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
}
