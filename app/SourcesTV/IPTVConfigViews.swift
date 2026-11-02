import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - QR Code Configuration Modal

struct IPTVQRModal: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var webServer = IPTVWebServer.shared
    @State private var showManual = false
    @State private var success = false

    var body: some View {
        ZStack {
            Theme.Palette.canvas.opacity(0.96).ignoresSafeArea()

            if success {
                VStack(spacing: Theme.Space.lg) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(Theme.Palette.accent)
                    Text("Connected Successfully!")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("Your IPTV channels and VODs are now ready.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: Theme.Space.xxl * 1.5) {
                    // Left Column: QR Code
                    VStack(spacing: Theme.Space.md) {
                        if let qr = qrImage(for: webServer.serverURLString) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 380, height: 380)
                                .padding(Theme.Space.lg)
                                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Theme.Palette.surface1)
                                .frame(width: 380, height: 380)
                        }

                        Text(webServer.serverURLString)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Palette.accent)
                    }

                    // Right Column: Instructions & Actions
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text("Setup IPTV Xtream")
                                .font(Theme.Typography.screenTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text("Scan this code with your phone camera to quickly enter your server credentials without typing on the remote.")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: Theme.Space.md) {
                            instructionRow(step: "1", text: "Point your phone camera at the QR code and tap the link.")
                            instructionRow(step: "2", text: "Enter your IPTV Server URL, Username, and Password.")
                            instructionRow(step: "3", text: "Tap Connect. This screen will update automatically.")
                        }
                        .padding(.vertical, Theme.Space.sm)

                        HStack(spacing: Theme.Space.md) {
                            Button("Manual Setup") {
                                showManual = true
                            }
                            .buttonStyle(ChipButtonStyle(selected: false))

                            Button("Cancel") {
                                dismiss()
                            }
                            .buttonStyle(ChipButtonStyle(selected: false))
                        }
                        .padding(.top, Theme.Space.md)
                    }
                    .frame(maxWidth: 580)
                }
                .padding(Theme.Space.xxl)
            }
        }
        .sheet(isPresented: $showManual) {
            IPTVManualConfigView {
                success = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
        }
        .onAppear {
            webServer.start()
            webServer.onConfigurationSaved = { _ in
                withAnimation { success = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
        }
        .onDisappear {
            webServer.stop()
        }
    }

    private func instructionRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Text(step)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.Palette.onAccent)
                .frame(width: 28, height: 28)
                .background(Theme.Palette.accent, in: Circle())

            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    private func qrImage(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Manual Configuration Modal

struct IPTVManualConfigView: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: (() -> Void)? = nil

    @State private var serverURL: String = IPTVConfig.current.serverURL
    @State private var username: String = IPTVConfig.current.username
    @State private var password: String = IPTVConfig.current.password
    @State private var working = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    Text("IPTV Xtream Server")
                        .font(Theme.Typography.sectionTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)

                    Text("Enter your provider's Xtream Codes credentials.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)

                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        field(label: "Server URL", placeholder: "http://provider.com:8080", text: $serverURL)
                        field(label: "Username", placeholder: "Username", text: $username)
                        field(label: "Password", placeholder: "Password", text: $password, isSecure: true)
                    }

                    if let errorMsg {
                        Text(errorMsg)
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Palette.danger)
                    }

                    HStack(spacing: Theme.Space.md) {
                        Button(working ? "Connecting…" : "Connect") {
                            connect()
                        }
                        .buttonStyle(PrimaryActionStyle())
                        .disabled(working || serverURL.isEmpty || username.isEmpty || password.isEmpty)

                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(ChipButtonStyle(selected: false))
                    }
                    .padding(.top, Theme.Space.md)
                }
                .padding(Theme.Space.xxl)
                .frame(maxWidth: 800, alignment: .leading)
            }
            .background(Theme.Palette.canvas.ignoresSafeArea())
        }
    }

    private func field(label: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textSecondary)

            if isSecure {
                SecureField(placeholder, text: text)
                    .font(Theme.Typography.body)
            } else {
                TextField(placeholder, text: text)
                    .font(Theme.Typography.body)
                    .autocorrectionDisabled(true)
            }
        }
    }

    private func connect() {
        working = true
        errorMsg = nil
        Task {
            do {
                _ = try await IPTVService.shared.connect(serverURL: serverURL, username: username, password: password)
                await MainActor.run {
                    working = false
                    dismiss()
                    onSaved?()
                }
            } catch {
                await MainActor.run {
                    working = false
                    errorMsg = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Series Seasons & Episodes Sheet

struct IPTVSeriesDetailView: View {
    let series: IPTVSeries
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var presenter: PlayerPresenter

    @State private var seasons: [IPTVSeriesSeason] = []
    @State private var selectedSeasonIndex: Int = 0
    @State private var loading = true
    @State private var errorMsg: String?

    var body: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()

            HStack(alignment: .top, spacing: Theme.Space.xxl) {
                // Left Column: Series Info
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    if let cover = series.cover, let url = URL(string: cover) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Theme.Palette.surface1
                            }
                        }
                        .frame(width: 240, height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }

                    Text(series.name)
                        .font(Theme.Typography.sectionTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(2)

                    if let rating = series.rating, !rating.isEmpty {
                        Label(rating, systemImage: "star.fill")
                            .font(Theme.Typography.label)
                            .foregroundStyle(.yellow)
                    }

                    if let plot = series.plot, !plot.isEmpty {
                        Text(plot)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(6)
                    }

                    Spacer()

                    Button("Close") { dismiss() }
                        .buttonStyle(ChipButtonStyle(selected: false))
                }
                .frame(width: 320)

                // Right Column: Seasons & Episodes
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    if loading {
                        VStack {
                            Spacer()
                            BigSpinner()
                            Text("Loading episodes…")
                                .font(Theme.Typography.label)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else if let errorMsg {
                        VStack(spacing: Theme.Space.md) {
                            Text(errorMsg).foregroundStyle(Theme.Palette.danger)
                            Button("Retry") { loadSeasons() }
                                .buttonStyle(PrimaryActionStyle())
                        }
                    } else if !seasons.isEmpty {
                        // Season Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Space.sm) {
                                ForEach(Array(seasons.enumerated()), id: \.element.id) { index, season in
                                    Button("Season \(season.seasonNumber)") {
                                        selectedSeasonIndex = index
                                    }
                                    .buttonStyle(ChipButtonStyle(selected: selectedSeasonIndex == index))
                                }
                            }
                        }
                        .focusSection()

                        // Episodes List
                        let currentEpisodes = seasons[safe: selectedSeasonIndex]?.episodes ?? []
                        ScrollView {
                            LazyVStack(spacing: Theme.Space.sm) {
                                ForEach(currentEpisodes) { ep in
                                    Button {
                                        playEpisode(ep)
                                    } label: {
                                        HStack(spacing: Theme.Space.md) {
                                            Text(String(format: "%02d", ep.episodeNum))
                                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                                .foregroundStyle(Theme.Palette.accent)
                                                .frame(width: 44)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(ep.title)
                                                    .font(Theme.Typography.cardTitle)
                                                    .foregroundStyle(Theme.Palette.textPrimary)
                                                    .lineLimit(1)
                                                if let plot = ep.info?.plot, !plot.isEmpty {
                                                    Text(plot)
                                                        .font(Theme.Typography.label)
                                                        .foregroundStyle(Theme.Palette.textSecondary)
                                                        .lineLimit(2)
                                                }
                                            }

                                            Spacer()

                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 28))
                                                .foregroundStyle(Theme.Palette.accent)
                                        }
                                        .padding(.horizontal, Theme.Space.md)
                                        .padding(.vertical, Theme.Space.sm)
                                        .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                                    }
                                    .buttonStyle(CardFocusStyle())
                                }
                            }
                            .padding(.vertical, Theme.Space.md)
                        }
                    } else {
                        Text("No episodes available.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.Space.xxl)
        }
        .onAppear { loadSeasons() }
    }

    private func loadSeasons() {
        loading = true
        errorMsg = nil
        Task {
            do {
                let loaded = try await IPTVService.shared.fetchSeriesInfo(seriesID: series.seriesId)
                await MainActor.run {
                    self.seasons = loaded
                    self.loading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = error.localizedDescription
                    self.loading = false
                }
            }
        }
    }

    private func playEpisode(_ ep: IPTVEpisode) {
        guard let url = IPTVService.shared.seriesStreamURL(episodeId: ep.id, containerExtension: ep.containerExtension) else { return }
        dismiss()
        let meta = PlaybackMeta(
            libraryId: "\(series.seriesId)",
            videoId: ep.id,
            type: "series",
            name: "\(series.name) - \(ep.title)",
            poster: series.cover,
            season: seasons[safe: selectedSeasonIndex]?.seasonNumber,
            episode: ep.episodeNum
        )
        presenter.request = PlaybackRequest(url: url, title: "\(series.name) - \(ep.title)", meta: meta)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
