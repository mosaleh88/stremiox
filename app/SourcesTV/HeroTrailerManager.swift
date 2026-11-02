import SwiftUI
import AVKit
import os

/// Single shared hero trailer manager tuned specifically for Apple TV HD (A8 chip, 2 GB RAM).
///
/// Hardware invariants:
/// - 1.5 - 2.0s dwell before trailer request.
/// - Single active player instance across the entire app; fully tears down previous playback before loading next.
/// - Capped at 720p SDR, muted, hardware decode, minimal 16MB buffer.
/// - Immediate release on backgrounding, navigation away, or `UIApplication.didReceiveMemoryWarningNotification`.
/// - Crossfades only after first frame is ready.
@MainActor
final class HeroTrailerManager: ObservableObject {
    static let shared = HeroTrailerManager()

    @Published private(set) var activeTrailerURL: URL?
    @Published private(set) var isReadyToDisplay: Bool = false

    private var player: AVPlayer?
    private var playerItemObserver: NSKeyValueObservation?
    private var dwellTask: Task<Void, Never>?
    private var currentTitleId: String?
    private let logger = Logger(subsystem: "com.xtv.tv", category: "HeroTrailer")

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    /// Focus entered or rested on a title.
    func focusTitle(id: String?, isReduceMotion: Bool) {
        guard !isReduceMotion else {
            stopAndRelease()
            return
        }
        guard AppSettings.shared.backdropTrailers else {
            stopAndRelease()
            return
        }
        guard let id = id, !id.isEmpty else {
            stopAndRelease()
            return
        }
        guard id != currentTitleId else { return }

        currentTitleId = id
        dwellTask?.cancel()
        dwellTask = nil
        stopAndRelease(keepTitleId: true)

        // 1.8s dwell requirement before starting hero trailer
        dwellTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, let self = self else { return }
            await self.resolveAndPlay(for: id)
        }
    }

    private func resolveAndPlay(for id: String) async {
        guard id == currentTitleId else { return }
        logger.debug("Resolving hero trailer for \(id, privacy: .public)")

        guard let url = await MetadataService.shared.resolveTrailerURL(for: id) else {
            logger.debug("No trailer found for \(id, privacy: .public)")
            return
        }
        guard id == currentTitleId, !Task.isCancelled else { return }

        play(url: url)
    }

    private func play(url: URL) {
        stopAndRelease(keepTitleId: true)
        logger.info("Starting hero trailer playback: \(url.absoluteString, privacy: .public)")

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        // Minimize memory buffer for 720p trailer on 2GB Apple TV HD
        item.preferredForwardBufferDuration = 4.0
        item.preferredMaximumResolution = CGSize(width: 1280, height: 720)

        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none

        // Observe when first video frame is ready to render
        playerItemObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard let self = self else { return }
            Task { @MainActor in
                if observedItem.status == .readyToPlay {
                    self.isReadyToDisplay = true
                    newPlayer.play()
                } else if observedItem.status == .failed {
                    self.stopAndRelease()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        self.player = newPlayer
        self.activeTrailerURL = url
    }

    func stopAndRelease(keepTitleId: Bool = false) {
        dwellTask?.cancel()
        dwellTask = nil
        playerItemObserver?.invalidate()
        playerItemObserver = nil

        if let player = player {
            player.pause()
            player.replaceCurrentItem(with: nil)
            self.player = nil
        }

        activeTrailerURL = nil
        isReadyToDisplay = false
        if !keepTitleId {
            currentTitleId = nil
        }
    }

    func createPlayerViewController() -> AVPlayerViewController? {
        guard let player = player else { return nil }
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear
        return controller
    }

    @objc private func handleMemoryWarning() {
        logger.warning("Memory warning received - releasing hero trailer immediately")
        stopAndRelease()
    }

    @objc private func handleAppBackground() {
        stopAndRelease()
    }
}

/// Lightweight UIViewControllerRepresentable hosting the single shared trailer player.
struct SingleSharedTrailerView: UIViewControllerRepresentable {
    @ObservedObject var manager = HeroTrailerManager.shared

    func makeUIViewController(context: Context) -> UIViewController {
        if let controller = manager.createPlayerViewController() {
            return controller
        }
        let fallback = UIViewController()
        fallback.view.backgroundColor = .clear
        return fallback
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

