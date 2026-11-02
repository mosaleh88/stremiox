import SwiftUI

/// Categorized navigation tabs for the redesigned Settings screen.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case all = "all"
    case appearance = "appearance"
    case layout = "layout"
    case playback = "playback"
    case iptv = "iptv"
    case sync = "sync"
    case subtitles = "subtitles"
    case system = "system"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .appearance: return "Appearance"
        case .layout: return "Layout & Rails"
        case .playback: return "Playback"
        case .iptv: return "Live TV & IPTV"
        case .sync: return "Sync & Trakt"
        case .subtitles: return "Subtitles"
        case .system: return "System"
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .appearance: return "paintpalette"
        case .layout: return "rectangle.3.group"
        case .playback: return "play.tv"
        case .iptv: return "tv"
        case .sync: return "arrow.triangle.2.circlepath"
        case .subtitles: return "captions.bubble"
        case .system: return "gearshape.2"
        }
    }
}

/// Settings: Reorganized, modular, categorized native Apple TV settings.
struct SettingsView: View {
    @EnvironmentObject private var account: StremioAccount
    @EnvironmentObject private var core: CoreBridge
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var updates = UpdateChecker.shared
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var iptv = IPTVService.shared
    @ObservedObject private var trakt = TraktService.shared
    @ObservedObject private var sourcePrefs = SourcePreferences.shared

    @State private var selectedCategory: SettingsCategory = .all
    @State private var serverOnline: Bool?
    @AppStorage("stremiox.forceSDRTonemap") private var forceSDRTonemap = false
    @State private var showRestartConfirm = false
    @State private var editingProfile: UserProfile?
    @AppStorage(SubtitleStyle.Key.font) private var subFont = SubtitleStyle.defaultFont
    @AppStorage(SubtitleStyle.Key.size) private var subSize = SubtitleStyle.defaultSize
    @AppStorage(SubtitleStyle.Key.sizeScale) private var subSizeScale = 1.0
    @AppStorage(SubtitleStyle.Key.color) private var subColor = SubtitleStyle.defaultColor
    @AppStorage(SubtitleStyle.Key.background) private var subBackground = SubtitleStyle.defaultBackground
    @AppStorage(TrackPreferences.Key.forced) private var prefForced = TrackPreferences.ForcedPolicy.always.rawValue
    @AppStorage(TrackPreferences.Key.audio) private var prefAudioLang = TrackPreferences.deviceLanguages.first ?? "en"
    @AppStorage(TrackPreferences.Key.subtitle) private var prefSubLang = TrackPreferences.deviceLanguages.first ?? "en"
    @AppStorage(PlaybackSettings.Key.directLinksOnly) private var directLinksOnly = false
    @AppStorage(PerformanceMode.overrideKey) private var perfMode = "auto"
    @AppStorage(AudioOutputMode.key) private var audioOutput = AudioOutputMode.auto.rawValue

    @State private var showIPTVQR = false
    @State private var showIPTVManual = false
    @State private var showTraktAuthModal = false
    @State private var showTMDBModal = false
    @State private var showMDBListModal = false
    @State private var showTraktCredentialsModal = false
    @State private var showInvidiousModal = false
    @State private var showCompanionQRModal = false
    @State private var inputTMDBKey = ""
    @State private var inputMDBListKey = ""
    @State private var inputTraktClientId = ""
    @State private var inputTraktClientSecret = ""
    @State private var inputInvidiousInstance = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    Text("Settings").screenTitleStyle()

                    // Quick Jump Category Navigation Bar
                    categorySelectorRail

                    if selectedCategory == .all || selectedCategory == .sync {
                        profilesSection
                        accountSection
                        syncSection
                        metadataSection
                    }
                    if selectedCategory == .all || selectedCategory == .appearance {
                        appearanceSection
                    }
                    if selectedCategory == .all || selectedCategory == .layout {
                        layoutSection
                    }
                    if selectedCategory == .all || selectedCategory == .playback {
                        playbackSection
                        streamsSection
                    }
                    if selectedCategory == .all || selectedCategory == .iptv {
                        iptvSection
                    }
                    if selectedCategory == .all || selectedCategory == .subtitles {
                        audioSubtitleSection
                        subtitleSection
                    }
                    if selectedCategory == .all || selectedCategory == .system {
                        serverSection
                        aboutSection
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge)
                .padding(.vertical, Theme.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Palette.canvas.ignoresSafeArea())
        }
        .onChange(of: prefAudioLang) { StreamRanking.invalidateCaches(); ProfileStore.shared.capturePlayback() }
        .onChange(of: prefSubLang) { ProfileStore.shared.capturePlayback() }
        .onChange(of: prefForced) { ProfileStore.shared.capturePlayback() }
        .onChange(of: subFont) { ProfileStore.shared.capturePlayback() }
        .onChange(of: subSize) { ProfileStore.shared.capturePlayback() }
        .onChange(of: subColor) { ProfileStore.shared.capturePlayback() }
        .onChange(of: subBackground) { ProfileStore.shared.capturePlayback() }
        .onChange(of: sourcePrefs.useAddonOrder) { ProfileStore.shared.capturePlayback() }
        .onChange(of: sourcePrefs.typeOrder) { ProfileStore.shared.capturePlayback() }
        .task {
            while !Task.isCancelled {
                if effectiveDirectLinksOnly {
                    serverOnline = nil
                    try? await Task.sleep(for: .seconds(12))
                    continue
                }
                let online = await StremioServer.isOnline()
                serverOnline = online
                try? await Task.sleep(for: .seconds(online ? 12 : 3))
            }
        }
        .sheet(isPresented: $showIPTVQR) { IPTVQRModal() }
        .sheet(isPresented: $showIPTVManual) { IPTVManualConfigView() }
        .sheet(isPresented: $showTraktAuthModal) { traktAuthSheet }
        .sheet(isPresented: $showTMDBModal) { tmdbKeyModal }
        .sheet(isPresented: $showMDBListModal) { mdblistKeyModal }
        .sheet(isPresented: $showTraktCredentialsModal) { traktCredentialsModal }
        .sheet(isPresented: $showInvidiousModal) { invidiousModal }
        .sheet(isPresented: $showCompanionQRModal) { companionQRModal }
    }

    // MARK: - Category Selector Rail

    private var categorySelectorRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(SettingsCategory.allCases) { cat in
                    Button {
                        withAnimation { selectedCategory = cat }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: cat.icon)
                            Text(cat.label)
                        }
                    }
                    .buttonStyle(ChipButtonStyle(selected: selectedCategory == cat))
                }
            }
            .padding(.vertical, Theme.Space.xs)
        }
        .focusSection()
    }

    // MARK: - Profiles

    private var profilesSection: some View {
        section("Profiles") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(profiles.profiles) { profile in
                        Button {
                            editingProfile = profile
                        } label: {
                            HStack(spacing: 8) {
                                Text(profile.avatar)
                                Text(profile.name)
                                if profile.hasPin { Image(systemName: "lock.fill") }
                            }
                        }
                        .buttonStyle(ChipButtonStyle(selected: profile.id == profiles.activeID))
                    }
                    Button {
                        editingProfile = UserProfile(name: "New Profile", avatar: "👤")
                    } label: {
                        Label("New Profile", systemImage: "plus")
                    }
                    .buttonStyle(ChipButtonStyle(selected: false))
                }
            }
            .focusSection()
            .sheet(item: $editingProfile) { profile in
                ProfileEditorView(original: profile)
            }
            Text("Switch between profiles or edit avatars, pins, and custom subtitle styles.")
                .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        section("Stremio Account") {
            if account.isSignedIn {
                HStack(spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.email ?? "Account").font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
                        Text("Signed in  ·  Add-ons and library sync enabled").font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    Button(role: .destructive) { account.signOut() } label: { Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(ChipButtonStyle(selected: false))
                }
            } else {
                HStack(spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not signed in").font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
                        Text("Log in with QR or code to sync your library and addons from the Stremio mobile/web app.").font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    NavigationLink { LoginView(account: account) } label: { Label("Sign In", systemImage: "person.badge.key.fill") }
                        .buttonStyle(PrimaryActionStyle())
                }
            }
        }
    }

    // MARK: - Sync & Trakt Section

    private var syncSection: some View {
        section("Trakt.tv & Cloud Sync") {
            if trakt.isAuthenticated {
                HStack(spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trakt Account: \(trakt.username ?? "Connected")")
                            .font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
                        Text("Playback scrobbling and two-way watch history sync active.")
                            .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    Button(role: .destructive) { trakt.logout() } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .buttonStyle(ChipButtonStyle(selected: false))
                }
            } else {
                HStack(spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect Trakt.tv")
                            .font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
                        Text("Sync your movie and series watch history automatically across devices.")
                            .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    Button {
                        showTraktAuthModal = true
                        Task { await trakt.startDeviceAuth() }
                    } label: {
                        Label("Connect Trakt", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(PrimaryActionStyle())
                }
            }

            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Trakt API Credentials")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(appSettings.traktClientId.isEmpty ? "Community App" : "Custom App Active")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(appSettings.traktClientId.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.Palette.surface2, in: Capsule())
                    }
                    Text("Configure your own Trakt.tv Client ID and Secret (or manage easily from phone).")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Button {
                    inputTraktClientId = appSettings.traktClientId
                    inputTraktClientSecret = appSettings.traktClientSecret
                    showTraktCredentialsModal = true
                } label: {
                    Label(appSettings.traktClientId.isEmpty ? "Configure" : "Edit", systemImage: "key.fill")
                }
                .buttonStyle(ChipButtonStyle(selected: false))
            }

            toggleRow("Trakt.tv Scrobbling",
                      subtitle: "Report playback start, pause, and finish directly to your Trakt account.",
                      isOn: $appSettings.traktSync)

            toggleRow("Trakt & Stremio Cloud Watch History Sync",
                      subtitle: "Two-way sync that mirrors watch status and ratings between Trakt and Stremio.",
                      isOn: $appSettings.cloudHistorySync)
        }
    }

    private var traktAuthSheet: some View {
        VStack(spacing: Theme.Space.lg) {
            Text("Connect Trakt.tv").font(Theme.Typography.screenTitle).foregroundStyle(Theme.Palette.textPrimary)
            Text("On your phone or computer, open the URL and enter the code below:")
                .font(Theme.Typography.body).foregroundStyle(Theme.Palette.textSecondary)

            if let code = trakt.userCode {
                Text(code)
                    .font(.system(size: 64, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(Theme.Space.lg)
                    .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                Text("https://trakt.tv/activate")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
            } else if let error = trakt.authError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.Palette.danger)
                    Text(error)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 700)
                    Button {
                        showTraktAuthModal = false
                        inputTraktClientId = appSettings.traktClientId
                        inputTraktClientSecret = appSettings.traktClientSecret
                        showTraktCredentialsModal = true
                    } label: {
                        Label("Enter Custom Trakt Client ID", systemImage: "key.fill")
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .padding(.top, Theme.Space.sm)
                }
            } else {
                BigSpinner()
                Text("Requesting authorization code…").font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
            }

            Button("Done / Cancel") { showTraktAuthModal = false }
                .buttonStyle(ChipButtonStyle(selected: false))
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas.ignoresSafeArea())
    }

    // MARK: - Metadata & API Integrations

    private var metadataSection: some View {
        section("Metadata & External Services") {
            // TMDB
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("The Movie Database (TMDB)")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(appSettings.tmdbApiKey.isEmpty ? "Community Key Active" : "Custom Key Active")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.Palette.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.Palette.accent.opacity(0.15), in: Capsule())
                    }
                    Text("Powers high-res 16:9 widescreen backdrops, official YouTube video trailers, and trending charts.")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Button {
                    inputTMDBKey = appSettings.tmdbApiKey
                    showTMDBModal = true
                } label: {
                    Label(appSettings.tmdbApiKey.isEmpty ? "Custom Key" : "Edit Key", systemImage: "key.fill")
                }
                .buttonStyle(ChipButtonStyle(selected: false))

                if !appSettings.tmdbApiKey.isEmpty {
                    Button("Reset") {
                        appSettings.tmdbApiKey = ""
                    }
                    .buttonStyle(ChipButtonStyle(selected: false))
                }
            }

            // MDBList
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("MDBList Integration")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(appSettings.mdblistApiKey.isEmpty ? "Not Connected" : "Connected")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(appSettings.mdblistApiKey.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.Palette.surface2, in: Capsule())
                    }
                    Text("Enhances the Smart Recommendation Engine with external ratings and custom user lists.")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Button {
                    inputMDBListKey = appSettings.mdblistApiKey
                    showMDBListModal = true
                } label: {
                    Label(appSettings.mdblistApiKey.isEmpty ? "Connect MDBList" : "Edit Key", systemImage: "link")
                }
                .buttonStyle(ChipButtonStyle(selected: false))

                if !appSettings.mdblistApiKey.isEmpty {
                    Button("Clear") {
                        appSettings.mdblistApiKey = ""
                    }
                    .buttonStyle(ChipButtonStyle(selected: false))
                }
            }

            // Trailer Gateway (Invidious)
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Trailer Proxy Gateway")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(appSettings.invidiousInstance.contains("chocolatemoo53") ? "Default Mirror" : "Custom Gateway")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.Palette.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.Palette.surface2, in: Capsule())
                    }
                    Text("Resolves YouTube trailers natively through an Invidious proxy instance for smooth backdrop and player playback.")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Button {
                    inputInvidiousInstance = appSettings.invidiousInstance
                    showInvidiousModal = true
                } label: {
                    Label("Configure", systemImage: "network")
                }
                .buttonStyle(ChipButtonStyle(selected: false))
            }

            // Companion Phone Setup (QR)
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Setup All Keys from Phone (QR)")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("Open the local web companion portal to paste API keys, manage add-ons, or setup IPTV from your phone.")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Button {
                    showCompanionQRModal = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode")
                }
                .buttonStyle(PrimaryActionStyle())
            }
        }
    }

    private var tmdbKeyModal: some View {
        VStack(spacing: Theme.Space.md) {
            Text("The Movie Database (TMDB) API Key")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Leave blank to use the built-in community key, or enter your personal TMDB API v3 key.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)

            TextField("TMDB API Key (e.g. e366d9...)", text: $inputTMDBKey)
                .font(Theme.Typography.cardTitle)
                .padding(Theme.Space.md)
                .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .frame(maxWidth: 800)

            HStack(spacing: Theme.Space.md) {
                Button("Save Key") {
                    appSettings.tmdbApiKey = inputTMDBKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    showTMDBModal = false
                }
                .buttonStyle(PrimaryActionStyle())

                Button("Cancel") { showTMDBModal = false }
                    .buttonStyle(ChipButtonStyle(selected: false))
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas.ignoresSafeArea())
    }

    private var traktCredentialsModal: some View {
        VStack(spacing: Theme.Space.md) {
            Text("Trakt.tv API Credentials")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Enter your custom Trakt API application Client ID and Secret (from trakt.tv/oauth/applications).")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Client ID").font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                TextField("Trakt Client ID", text: $inputTraktClientId)
                    .font(Theme.Typography.cardTitle)
                    .padding(Theme.Space.md)
                    .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .frame(maxWidth: 800)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Client Secret").font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                SecureField("Trakt Client Secret", text: $inputTraktClientSecret)
                    .font(Theme.Typography.cardTitle)
                    .padding(Theme.Space.md)
                    .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .frame(maxWidth: 800)
            }

            HStack(spacing: Theme.Space.md) {
                Button("Save Credentials") {
                    appSettings.traktClientId = inputTraktClientId.trimmingCharacters(in: .whitespacesAndNewlines)
                    appSettings.traktClientSecret = inputTraktClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                    showTraktCredentialsModal = false
                }
                .buttonStyle(PrimaryActionStyle())

                if !appSettings.traktClientId.isEmpty {
                    Button("Reset to Default") {
                        appSettings.traktClientId = ""
                        appSettings.traktClientSecret = ""
                        showTraktCredentialsModal = false
                    }
                    .buttonStyle(ChipButtonStyle(selected: false))
                }

                Button("Cancel") { showTraktCredentialsModal = false }
                    .buttonStyle(ChipButtonStyle(selected: false))
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas.ignoresSafeArea())
    }

    private var invidiousModal: some View {
        VStack(spacing: Theme.Space.md) {
            Text("Trailer Proxy Gateway")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Select or enter an Invidious proxy instance for reliable trailer playback:")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)

            TextField("https://yt.chocolatemoo53.com", text: $inputInvidiousInstance)
                .font(Theme.Typography.cardTitle)
                .padding(Theme.Space.md)
                .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .frame(maxWidth: 800)

            HStack(spacing: Theme.Space.sm) {
                Button("Chocolatemoo") { inputInvidiousInstance = "https://yt.chocolatemoo53.com" }
                    .buttonStyle(ChipButtonStyle(selected: inputInvidiousInstance.contains("chocolatemoo53")))
                Button("Nadeko") { inputInvidiousInstance = "https://inv.nadeko.net" }
                    .buttonStyle(ChipButtonStyle(selected: inputInvidiousInstance.contains("nadeko")))
                Button("NerdVPN") { inputInvidiousInstance = "https://invidious.nerdvpn.de" }
                    .buttonStyle(ChipButtonStyle(selected: inputInvidiousInstance.contains("nerdvpn")))
                Button("Tiekoetter") { inputInvidiousInstance = "https://invidious.tiekoetter.com" }
                    .buttonStyle(ChipButtonStyle(selected: inputInvidiousInstance.contains("tiekoetter")))
            }

            HStack(spacing: Theme.Space.md) {
                Button("Save Gateway") {
                    let clean = inputInvidiousInstance.trimmingCharacters(in: .whitespacesAndNewlines)
                    appSettings.invidiousInstance = clean.isEmpty ? "https://yt.chocolatemoo53.com" : clean
                    showInvidiousModal = false
                }
                .buttonStyle(PrimaryActionStyle())

                Button("Cancel") { showInvidiousModal = false }
                    .buttonStyle(ChipButtonStyle(selected: false))
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas.ignoresSafeArea())
    }

    private var companionQRModal: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()
            VStack(spacing: Theme.Space.lg) {
                Text("Companion Setup Portal")
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)

                if let img = StreamLinkQRView.qrImage(for: IPTVWebServer.shared.serverURLString + "/services") {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 360, height: 360)
                        .padding(Theme.Space.md)
                        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }

                VStack(spacing: 6) {
                    Text(IPTVWebServer.shared.serverURLString + "/services")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.Palette.accent)
                    Text("Scan with your phone to configure TMDB, Trakt, MDBList, and Invidious keys easily in your mobile browser.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 750)
                }

                Button("Done") { showCompanionQRModal = false }
                    .buttonStyle(ChipButtonStyle(selected: false))
            }
            .padding(Theme.Space.xl)
        }
    }

    private var mdblistKeyModal: some View {
        VStack(spacing: Theme.Space.md) {
            Text("MDBList API Key")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Enter your MDBList API key (from mdblist.com/preferences) to enable advanced rating badges and personalized recommendations.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)

            TextField("MDBList API Key", text: $inputMDBListKey)
                .font(Theme.Typography.cardTitle)
                .padding(Theme.Space.md)
                .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .frame(maxWidth: 800)

            HStack(spacing: Theme.Space.md) {
                Button("Save Key") {
                    appSettings.mdblistApiKey = inputMDBListKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    showMDBListModal = false
                }
                .buttonStyle(PrimaryActionStyle())

                Button("Cancel") { showMDBListModal = false }
                    .buttonStyle(ChipButtonStyle(selected: false))
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas.ignoresSafeArea())
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        section("Appearance & Themes") {
            // Theme Mode
            choiceRow("Theme Appearance", AppSettings.AppearanceMode.allCases.map { ($0.rawValue, $0.label) },
                      selection: Binding(get: { appSettings.appearanceMode.rawValue },
                                         set: { if let m = AppSettings.AppearanceMode(rawValue: $0) { appSettings.appearanceMode = m; theme.objectWillChange.send() } }))

            toggleRow("Apple Liquid Glass & Frost Material",
                      subtitle: "Applies native translucent ultra-thin material blur and glass borders across cards and player sheets.",
                      isOn: $appSettings.liquidGlass)

            ThemeAccentPicker(selection: $theme.accentID).focusSection()
            ThemeBackgroundPicker(oled: $theme.oled).focusSection()
            Text("Cupertino is the Apple TV native accent. OLED Black uses true black pixels on AMOLED panels.")
                .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)

            stepperRow("App text size", value: theme.textScale,
                       range: ThemeManager.textScaleRange,
                       onMinus: { theme.adjustTextScale(-1) },
                       onPlus: { theme.adjustTextScale(1) })

            choiceRow("Performance", [("auto", "Auto"), ("full", "Full"), ("reduced", "Reduced")], selection: $perfMode)
            Text("Auto keeps the full experience on Apple TV 4K and trims footprint on Apple TV HD.")
                .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    // MARK: - Layout & Navigation

    private var layoutSection: some View {
        section("Layout & Navigation") {
            toggleRow("Apple TV+ Hero Carousel",
                      subtitle: "Displays a large interactive featured carousel at the top of Home with high-res artwork.",
                      isOn: $appSettings.heroCarousel)

            toggleRow("Cinematic Spotlight Immersive Home",
                      subtitle: "Blends full-screen dynamic backdrop lighting with rich cinematic gradients.",
                      isOn: $appSettings.cinematicSpotlight)

            toggleRow("Full-Bleed 16:9 Banner Rail",
                      subtitle: "Showcases trending titles in Netflix/Apple TV Channels style with ranking numbers.",
                      isOn: $appSettings.fullBleedBanners)

            toggleRow("Interactive Floating Detail Drawer (Peek & Pop)",
                      subtitle: "Opens a translucent floating quick-action drawer on title selection without leaving the screen.",
                      isOn: $appSettings.peekAndPopDrawer)

            toggleRow("Smart Recommendation Engine",
                      subtitle: "Generates 'Because You Watched' dynamic recommendation rails based on your watch history.",
                      isOn: $appSettings.smartRecommendations)

            toggleRow("Live TV & VODs Horizontal Category Rail",
                      subtitle: "Switches Live TV and VOD categories between horizontal chips and an Apple TV vertical sidebar.",
                      isOn: $appSettings.liveHorizontalCategories)

            toggleRow("Infuse-Inspired Modular Home Rails",
                      subtitle: "Enables customizable modular headers and flexible ordering for home screen rails.",
                      isOn: $appSettings.modularHomeRails)
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        section("Player & Playback") {
            toggleRow("Apple TV Native Match Content",
                      subtitle: "Automatically matches HDMI refresh rate (24Hz, 23.976Hz, 50Hz, 60Hz) and dynamic range (SDR/HDR) to eliminate judder.",
                      isOn: $appSettings.matchContent)

            toggleRow("Binge Mode & Intro / Credits Auto-Skip",
                      subtitle: "Automatically skips opening titles and advances to the next episode when credits roll.",
                      isOn: $appSettings.bingeMode)

            toggleRow("Split-Screen Quick Guide Drawer",
                      subtitle: "Swipe or press Down during Live TV to browse and zap channels without interrupting video playback.",
                      isOn: $appSettings.quickGuideDrawer)

            toggleRow("Live Subtitle Sync Offset Controls",
                      subtitle: "Provides on-screen subtitle delay timing (+/- 100ms) and automatic speech synchronization in the player.",
                      isOn: $appSettings.subOffsetAuto)

            toggleRow("Backdrop Video Trailers",
                      subtitle: "Silently plays cinematic preview trailers in the background when resting on hero items.",
                      isOn: $appSettings.backdropTrailers)

            Toggle(isOn: $forceSDRTonemap) {
                Text("Dolby Vision / HDR compatibility").font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(Theme.Palette.accent)
            Text("Tone-maps HDR and Dolby Vision to SDR. Turn this on only if 4K Dolby Vision remuxes look washed out on your TV.")
                .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)

            if PlaybackSettings.directLinksOnlyForced {
                directLinksOnlyRow
                    .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            } else {
                Button { setDirectLinksOnly(!directLinksOnly) } label: { directLinksOnlyRow }
                    .buttonStyle(RowFocusStyle())
            }

            choiceRow("Audio output", AudioOutputMode.allCases.map { ($0.rawValue, $0.label) }, selection: $audioOutput)
            Text(AudioOutputMode(rawValue: audioOutput)?.detail ?? "")
                .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var effectiveDirectLinksOnly: Bool { PlaybackSettings.directLinksOnly }

    private var directLinksOnlyRow: some View {
        HStack(alignment: .center, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Direct Links Only").font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
                Text(PlaybackSettings.directLinksOnlyForced
                     ? "This build does not bundle the torrent engine. Only direct and debrid links can play."
                     : "Hide torrent and magnet sources. Only direct and debrid links will play.")
                    .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.md)
            if PlaybackSettings.directLinksOnlyForced {
                UnavailableBadge(text: "Not bundled")
            } else {
                TogglePill(isOn: effectiveDirectLinksOnly)
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func setDirectLinksOnly(_ value: Bool) {
        directLinksOnly = value
        #if !STREMIOX_NO_EMBEDDED_SERVER
        if !value, !ProcessInfo.processInfo.arguments.contains("-stremiox-no-server") {
            NodeServer.startIfNeeded()
        }
        #endif
    }

    // MARK: - IPTV Xtream

    private var iptvSection: some View {
        section("Live TV & IPTV (Xtream Codes)") {
            if iptv.isConnected {
                HStack(spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(iptv.config.serverName ?? iptv.config.serverURL)
                            .font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
                        Text("User: \(iptv.config.username)  ·  Expires: \(iptv.config.expiryDate ?? "Active")")
                            .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    Text("Connected")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.accent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.Palette.surface1, in: Capsule())
                }
            } else {
                Text("Not configured. Connect your Xtream Codes IPTV provider to stream Live TV, Movies, and Series.")
                    .font(Theme.Typography.body).foregroundStyle(Theme.Palette.textSecondary)
            }

            HStack(spacing: Theme.Space.md) {
                Button { showIPTVQR = true } label: { Label("Setup via QR Code", systemImage: "qrcode") }
                    .buttonStyle(PrimaryActionStyle())

                Button { showIPTVManual = true } label: {
                    Label(iptv.isConnected ? "Edit Server Details" : "Enter Server Details", systemImage: "pencil")
                }
                .buttonStyle(ChipButtonStyle(selected: false))

                if iptv.isConnected {
                    Button { iptv.clearCache() } label: { Label("Refresh Content", systemImage: "arrow.clockwise") }
                        .buttonStyle(ChipButtonStyle(selected: false))

                    Button(role: .destructive) { iptv.disconnect() } label: { Label("Disconnect", systemImage: "xmark.circle") }
                        .buttonStyle(ChipButtonStyle(selected: false))
                }
            }
            .focusSection()

            toggleRow("Sort Channels Alphabetically",
                      subtitle: "Sorts live TV channels in A-Z alphabetical order instead of provider order.",
                      isOn: $appSettings.channelSortAscending)
        }
    }

    // MARK: - Streams

    private var streamsSection: some View {
        section("Streams & Ranking") {
            Toggle(isOn: $sourcePrefs.useAddonOrder) {
                Text("Use add-on ranking order").font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(Theme.Palette.accent)
            Text("When on, streams appear in the order your add-ons return them. Useful with AIOStreams.")
                .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)

            if !sourcePrefs.useAddonOrder {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Source type priority").font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
                    ForEach(Array(sourcePrefs.typeOrder.enumerated()), id: \.element) { index, sourceType in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sourceType.label).font(Theme.Typography.body).foregroundStyle(Theme.Palette.textPrimary)
                                Text(sourceType.detail).font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Button { sourcePrefs.moveType(at: index, direction: -1) } label: { Image(systemName: "chevron.up") }
                                    .buttonStyle(ChipButtonStyle(selected: false))
                                    .opacity(index == 0 ? 0.3 : 1).disabled(index == 0)
                                Button { sourcePrefs.moveType(at: index, direction: 1) } label: { Image(systemName: "chevron.down") }
                                    .buttonStyle(ChipButtonStyle(selected: false))
                                    .opacity(index == sourcePrefs.typeOrder.count - 1 ? 0.3 : 1).disabled(index == sourcePrefs.typeOrder.count - 1)
                            }
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                }
                .focusSection()
            }
        }
    }

    // MARK: - Subtitles & Audio

    private var audioSubtitleSection: some View {
        section("Audio & Subtitle Preferences") {
            choiceRow("Audio language", TrackPreferences.commonLanguages, selection: $prefAudioLang)
            choiceRow("Subtitle language", TrackPreferences.commonLanguages, selection: $prefSubLang)
            choiceRow("Subtitles", TrackPreferences.ForcedPolicy.allCases.map { ($0.rawValue, $0.label) }, selection: $prefForced)
            Text("Subtitles are ON by default. The player auto-picks these when a title starts.")
                .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var subtitleSection: some View {
        section("Subtitle Styling") {
            choiceRow("Font", SubtitleStyle.fonts.map { ($0.id, $0.label) }, selection: $subFont)
            choiceRow("Size", SubtitleStyle.sizes.map { ($0.id, $0.label) }, selection: $subSize)
            stepperRow("Fine size", value: subSizeScale,
                       range: SubtitleStyle.sizeScaleRange,
                       onMinus: { adjustSubScale(-1) },
                       onPlus: { adjustSubScale(1) })
            choiceRow("Color", SubtitleStyle.colors.map { ($0.id, $0.label) }, selection: $subColor)
            choiceRow("Background", SubtitleStyle.backgrounds.map { ($0.id, $0.label) }, selection: $subBackground)
        }
    }

    private func adjustSubScale(_ direction: Int) {
        let next = subSizeScale + Double(direction) * SubtitleStyle.sizeScaleStep
        let clamped = min(max(next, SubtitleStyle.sizeScaleRange.lowerBound), SubtitleStyle.sizeScaleRange.upperBound)
        subSizeScale = (clamped * 100).rounded() / 100
        ProfileStore.shared.capturePlayback()
    }

    // MARK: - Streaming Server

    private var serverSection: some View {
        section("Streaming Server") {
            HStack(spacing: Theme.Space.sm) {
                Circle().fill(serverColor).frame(width: 16, height: 16)
                Text(serverText).font(Theme.Typography.body).foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text(serverBadgeText)
                    .font(Theme.Typography.eyebrow).tracking(1)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.Palette.surface3, in: Capsule())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            if effectiveDirectLinksOnly {
                Text("Direct Links Only is enabled, so torrent streaming and server configuration are inactive.")
                    .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
            } else {
                Text(StremioServer.base)
                    .font(.system(size: 18, design: .monospaced)).foregroundStyle(Theme.Palette.textTertiary)
                HStack(spacing: Theme.Space.md) {
                    Button { showRestartConfirm = true } label: { Label("Restart App", systemImage: "arrow.clockwise.circle") }
                        .buttonStyle(ChipButtonStyle())
                        .confirmationDialog("Restart StremioX?", isPresented: $showRestartConfirm, titleVisibility: .visible) {
                            Button("Quit Now", role: .destructive) { exit(0) }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("The app quits immediately. Open it again from the Home Screen to restart the streaming server.")
                        }

                    NavigationLink {
                        ServerConfigView { Task { serverOnline = await StremioServer.isOnline() } }
                    } label: {
                        Label("Configure server", systemImage: "server.rack")
                    }
                    .buttonStyle(PrimaryActionStyle())
                }
                .focusSection()
            }
        }
    }

    private var serverColor: Color {
        if effectiveDirectLinksOnly { return Theme.Palette.textTertiary }
        switch serverOnline {
        case .some(true): return Color(.sRGB, red: 0.45, green: 0.72, blue: 0.42)
        case .some(false): return Theme.Palette.danger
        default: return Theme.Palette.accent
        }
    }

    private var serverText: String {
        if effectiveDirectLinksOnly { return "Disabled by Direct Links Only" }
        switch serverOnline { case .some(true): return "Online"; case .some(false): return "Offline"; default: return "Checking…" }
    }

    private var serverBadgeText: String {
        if effectiveDirectLinksOnly { return PlaybackSettings.directLinksOnlyForced ? "NOT BUNDLED" : "DISABLED" }
        return StremioServer.isCustom ? "CUSTOM" : "EMBEDDED"
    }

    // MARK: - About

    private var aboutSection: some View {
        section("About") {
            if let update = updates.available {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Update available: \(update.name)", systemImage: "arrow.down.circle.fill")
                        .font(Theme.Typography.body.weight(.semibold)).foregroundStyle(Theme.Palette.accent)
                    Text("Sideload the new IPA from GitHub releases; your sign-in and settings carry over.")
                        .font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(.vertical, Theme.Space.xs)
            }
            infoRow("Version", appVersion)
            infoRow("Player", "libmpv · MPVKit")
            infoRow("Live TV & IPTV", "Xtream Codes API Engine")
            infoRow("Sync", "Trakt.tv Two-Way Scrobble")
        }
        .task { updates.checkIfStale(maxAge: 30 * 60) }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    // MARK: - Helpers

    @ViewBuilder
    private func toggleRow(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
                    Text(subtitle).font(Theme.Typography.label).foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.md)
                TogglePill(isOn: isOn.wrappedValue)
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(RowFocusStyle())
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text(title).eyebrowStyle()
            content()
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .liquidGlassBackground(cornerRadius: Theme.Radius.card)
        .focusSection()
    }

    private func choiceRow(_ label: String, _ options: [(id: String, label: String)],
                           selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label).font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(options, id: \.id) { opt in
                        Button { selection.wrappedValue = opt.id } label: { Text(opt.label) }
                            .buttonStyle(ChipButtonStyle(selected: selection.wrappedValue == opt.id))
                    }
                }
            }
        }
        .focusSection()
    }

    private func stepperRow(_ label: String, value: Double, range: ClosedRange<Double>,
                            onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label).font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
            HStack(spacing: Theme.Space.md) {
                Button(action: onMinus) { Image(systemName: "minus") }
                    .buttonStyle(ChipButtonStyle(selected: false))
                    .disabled(value <= range.lowerBound + 0.001)
                    .opacity(value <= range.lowerBound + 0.001 ? 0.3 : 1)
                Text("\(Int((value * 100).rounded()))%")
                    .font(Theme.Typography.body.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(minWidth: 90)
                Button(action: onPlus) { Image(systemName: "plus") }
                    .buttonStyle(ChipButtonStyle(selected: false))
                    .disabled(value >= range.upperBound - 0.001)
                    .opacity(value >= range.upperBound - 0.001 ? 0.3 : 1)
            }
        }
        .focusSection()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Text(value).foregroundStyle(Theme.Palette.textSecondary)
        }
        .font(Theme.Typography.body)
    }
}

private struct TogglePill: View {
    let isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(isOn ? "On" : "Off")
                .font(Theme.Typography.eyebrow)
                .tracking(1)
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.Palette.accent.opacity(0.24) : Theme.Palette.surface3)
                    .frame(width: 64, height: 34)
                Circle()
                    .fill(isOn ? Theme.Palette.accent : Theme.Palette.textTertiary)
                    .frame(width: 24, height: 24)
                    .padding(.horizontal, 5)
            }
        }
        .foregroundStyle(isOn ? Theme.Palette.accent : Theme.Palette.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Palette.surface2, in: Capsule(style: .continuous))
    }
}

private struct UnavailableBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "lock.fill")
            .font(Theme.Typography.eyebrow)
            .tracking(1)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.Palette.surface2, in: Capsule(style: .continuous))
    }
}

struct ThemeAccentPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Accent Color").font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.md) {
                    ForEach(ThemeManager.accents) { opt in
                        Button { selection = opt.id } label: {
                            AccentCircle(color: opt.base, selected: selection == opt.id)
                        }
                        .buttonStyle(CardFocusStyle())
                    }
                }
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.md)
            }
        }
    }
}

struct ThemeBackgroundPicker: View {
    @Binding var oled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Background").font(Theme.Typography.cardTitle).foregroundStyle(Theme.Palette.textPrimary)
            HStack(spacing: Theme.Space.sm) {
                Button("Cinema Warm") { oled = false }
                    .buttonStyle(ChipButtonStyle(selected: !oled))
                Button("OLED True Black") { oled = true }
                    .buttonStyle(ChipButtonStyle(selected: oled))
            }
        }
    }
}

private struct AccentCircle: View {
    let color: Color
    let selected: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 58, height: 58)
            .overlay(Circle().strokeBorder(ringColor, lineWidth: ringWidth))
    }

    private var ringColor: Color {
        focused ? Theme.Palette.accentBright : Theme.Palette.textPrimary
    }

    private var ringWidth: CGFloat {
        focused || selected ? 5 : 0
    }
}
