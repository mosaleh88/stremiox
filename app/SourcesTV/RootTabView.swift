import SwiftUI
import UIKit
import os

/// A request to play something full-screen.
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    var meta: PlaybackMeta? = nil
    var episodes: [CoreVideo] = []
    /// Quality signature of the stream being played, so auto-next can prefer the
    /// same release family for the following episode.
    var sourceHint: String? = nil
    /// True when the stream rides the embedded torrent engine, which needs warm-up
    /// patience the player gives it.
    var torrent: Bool = false
    /// The add-on's release-group tag for the playing stream, so auto-next can lock
    /// the next episode to the same release.
    var bingeGroup: String? = nil
    /// HTTP request headers the stream's add-on requires (behaviorHints.proxyHeaders).
    var headers: [String: String]? = nil
    /// External audio stream URL (for split-track media like YouTube trailers).
    var audioURL: URL? = nil
}

/// Holds the active playback request. Set it to present the player; clear it to dismiss.
final class PlayerPresenter: ObservableObject {
    @Published var request: PlaybackRequest? {
        didSet {
            if request?.torrent == true && PlaybackSettings.torrentsDisabled {
                request = nil
            }
        }
    }
}

/// App root, three focus rules learned the hard way:
///  - The shell (and its UITabBarController) is mounted ONCE and never torn down. Conditionally
///    recreating the TabView (the 0.2.9 "root replacement" picker) made UIKit initialize the tab
///    bar's auto-hide offsets against a mid-transition layout, intermittently parking the bar
///    absurdly far offscreen (observed live at y = -1288) where the focus engine cannot summon it:
///    THE vanishing tab bar bug, which did not exist while the shell was permanent (through 0.2.8).
///  - The profile picker presents as a REAL modal (fullScreenCover). UIKit moves focus into actual
///    presentations natively on a Siri remote; the hand-rolled ZStack overlay it replaces could
///    never receive focus on device. (The editor and login covers prove modal focus works here.)
///  - The player presents OVER the live but hidden + disabled shell, so closing it returns to the
///    exact page playback started from; the player's catcher window owns the remote (TVPlayerView).
struct RootView: View {
    @EnvironmentObject private var presenter: PlayerPresenter
    @EnvironmentObject private var profiles: ProfileStore
    @State private var splashDone = false

    var body: some View {
        ZStack {
            // Brand canvas behind everything, so the moment between the splash fading
            // and the profile picker animating in shows the app's own background, never
            // a flash of the main profile's Home underneath.
            Theme.Palette.canvas.ignoresSafeArea()
            RootTabView()
                .opacity(shellVisible ? 1 : 0)
                .disabled(!shellVisible)
            if let req = presenter.request {
                TVPlayerView(url: req.url, title: req.title, meta: req.meta, episodes: req.episodes,
                             sourceHint: req.sourceHint, torrent: req.torrent, bingeGroup: req.bingeGroup,
                             headers: req.headers, audioURL: req.audioURL,
                             onClose: { presenter.request = nil })
                    .id(req.id)   // clean player teardown per request
            }
            // The launch splash sits above everything for its ~2 seconds. It has no
            // focusable content, so the focus engine settles on the shell underneath
            // and nothing fights it; the profile picker waits for it (binding below).
            if !splashDone {
                SplashView { splashDone = true }
                    .zIndex(10)
            }
        }
        .fullScreenCover(isPresented: pickerPresented) { ProfilePickerView() }
        // Re-sync the bar's visibility after playback ends: two shots, because the desync can
        // assert itself after the first layout settles.
        .onChange(of: presenter.request?.id) {
            guard presenter.request == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { TabBarHealer.heal("player-closed") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { TabBarHealer.heal("player-closed+3s") }
        }
    }

    /// Cold start with a real choice, or Settings' "Switch Profile". Dismissing with Menu counts
    /// as picking the current profile, so the binding's setter just marks the launch as picked.
    /// Home stays hidden until a profile is settled: while the picker is owed (more
    /// than one profile, none chosen this launch) the shell is invisible, so nothing
    /// of the main profile leaks out before the picker arrives.
    private var shellVisible: Bool {
        presenter.request == nil && !profiles.needsPicker
    }

    private var pickerPresented: Binding<Bool> {
        Binding(
            get: { splashDone && profiles.needsPicker && presenter.request == nil },
            set: { presented in if !presented { profiles.pickedThisLaunch = true } }
        )
    }
}

/// The app shell: Home · Discover · Library · Add-ons · Search · Settings.
///
/// Uses the native tvOS `TabView` so the top tab bar gets correct focus behaviour for free: tabs switch
/// as focus crosses them, and focus moves cleanly between the tab bar and the page content (up/down). The
/// player no longer depends on the shell being a custom bar, it locks focus on its own catcher while up,
/// so the native tab bar can't steal the remote.
/// The app shell with native Apple TV left sidebar navigation and quick "Home" / tab pill.
struct RootTabView: View {
    @EnvironmentObject private var account: StremioAccount
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var sidebarState = SidebarState.shared
    @State private var selectedTab: TabItem = .home
    @FocusState private var sidebarFocusedItem: TabItem?
    @FocusState private var focusedNavTab: TabItem?
    @State private var resetTokens = [Int](repeating: 0, count: 7)

    var body: some View {
        ZStack(alignment: .top) {
            // Main content based on selected tab
            Group {
                switch selectedTab {
                case .home:
                    HomeView().id(resetTokens[TabItem.home.rawValue])
                case .discover:
                    DiscoverView().id(resetTokens[TabItem.discover.rawValue])
                case .live:
                    LiveView().id(resetTokens[TabItem.live.rawValue])
                case .library:
                    LibraryView().id(resetTokens[TabItem.library.rawValue])
                case .search:
                    NavigationStack { SearchView() }.id(resetTokens[TabItem.search.rawValue])
                case .addons:
                    AddonsView().id(resetTokens[TabItem.addons.rawValue])
                case .settings:
                    SettingsView().id(resetTokens[TabItem.settings.rawValue])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(sidebarState.isOpen)

            // Native Apple TV Top Navigation Bar
            TopNavigationBar(
                selectedTab: $selectedTab,
                focusedTab: $focusedNavTab
            )
            .opacity(sidebarState.isOpen ? 0 : 1)
            .zIndex(20)

            // Dimmed scrim behind open sidebar
            if sidebarState.isOpen {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .zIndex(30)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            sidebarState.isOpen = false
                        }
                    }
            }

            // Left Sidebar Panel
            if sidebarState.isOpen {
                SidebarView(
                    selectedTab: $selectedTab,
                    isOpen: $sidebarState.isOpen,
                    focusedItem: $sidebarFocusedItem
                )
                .padding(.leading, 40)
                .zIndex(40)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onExitCommand {
            handleMenuPress()
        }
        .onChange(of: selectedTab) { old, _ in
            if old.rawValue >= 0, old.rawValue < resetTokens.count {
                resetTokens[old.rawValue] += 1
            }
        }
        .onChange(of: sidebarState.isOpen) { _, open in
            if open {
                sidebarFocusedItem = selectedTab
            }
        }
        .onChange(of: theme.accentID) { ProfileStore.shared.captureTheme() }
        .onChange(of: theme.oled) { ProfileStore.shared.captureTheme() }
        .onChange(of: theme.textScale) { ProfileStore.shared.captureTheme() }
    }

    private func handleMenuPress() {
        if sidebarState.isOpen {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                sidebarState.isOpen = false
            }
        } else if focusedNavTab == nil {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                focusedNavTab = selectedTab
            }
        } else if selectedTab != .home {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedTab = .home
                focusedNavTab = .home
            }
        }
    }

    /// The focused / selected tab pill is system white by default; recolor it to the active accent
    /// with dark on-accent ink, and push the appearance onto any live tab bars so an accent change
    /// repaints without a relaunch.
    private func applyTabBarAccent() {
        let isLight = theme.isLight
        let item = UITabBarItemAppearance()
        let normalColor = isLight ? UIColor(white: 0.25, alpha: 0.85) : UIColor(Theme.Palette.textSecondary)
        item.normal.titleTextAttributes = [.foregroundColor: normalColor]
        item.normal.iconColor = normalColor
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.Palette.onAccent)]
        item.selected.iconColor = UIColor(Theme.Palette.onAccent)
        item.focused.titleTextAttributes = [.foregroundColor: UIColor(Theme.Palette.onAccent)]
        item.focused.iconColor = UIColor(Theme.Palette.onAccent)
        let appearance = UITabBarAppearance()
        if isLight {
            appearance.configureWithDefaultBackground()
            appearance.backgroundColor = UIColor(white: 0.94, alpha: 0.85)
        } else {
            appearance.configureWithDefaultBackground()
        }
        appearance.selectionIndicatorTintColor = UIColor(Theme.Palette.accent)
        appearance.inlineLayoutAppearance = item
        appearance.stackedLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { retintTabBars(under: window.rootViewController, with: appearance) }
        }
    }

    private func retintTabBars(under controller: UIViewController?, with appearance: UITabBarAppearance) {
        guard let controller else { return }
        if let tabs = controller as? UITabBarController {
            tabs.tabBar.standardAppearance = appearance
            tabs.tabBar.scrollEdgeAppearance = appearance
            tabs.tabBar.setNeedsLayout()
        }
        controller.children.forEach { retintTabBars(under: $0, with: appearance) }
        retintTabBars(under: controller.presentedViewController, with: appearance)
    }
}

/// Re-sync the tab bar's visibility after something full-screen (the player, the system keyboard)
/// takes focus and gives it back. Symptom caught live: focus could sit ON the bar's pills (Right
/// switched tabs) while the bar itself stayed invisible, its container parked offscreen, until a
/// tab change forced a real layout pass. The heal uses the SUPPORTED visibility API (frame surgery
/// on the private container gets stomped by the next layout pass) and logs what it saw, so a
/// failed heal explains itself in the log.
enum TabBarHealer {
    private static let log = Logger(subsystem: "com.stremiox.app", category: "tabbar")

    static func heal(_ reason: String) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                guard let tabs = firstTabBarController(under: window.rootViewController) else { continue }
                let bar = tabs.tabBar
                let container = bar.superview
                let containerY = container?.frame.origin.y ?? .nan
                if #available(tvOS 18.0, *) {
                    log.info("heal(\(reason, privacy: .public)): containerY=\(containerY, privacy: .public) barHidden=\(bar.isHidden) controllerHidden=\(tabs.isTabBarHidden)")
                    if tabs.isTabBarHidden {
                        tabs.setTabBarHidden(false, animated: false)
                        log.info("heal: setTabBarHidden(false) applied")
                    }
                } else {
                    log.info("heal(\(reason, privacy: .public)): containerY=\(containerY, privacy: .public) barHidden=\(bar.isHidden)")
                }
                // Re-home a parked container as well; harmless if the layout pass recomputes it.
                if let container, container.frame.origin.y < -(max(container.frame.height, 68) * 3) {
                    container.frame.origin.y = -max(container.frame.height, 68)
                    log.info("heal: re-homed parked container")
                }
                tabs.view.setNeedsLayout()
                tabs.view.layoutIfNeeded()
                return
            }
        }
        log.info("heal(\(reason, privacy: .public)): no tab bar controller found")
    }

    private static func firstTabBarController(under controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tabs = controller as? UITabBarController { return tabs }
        for child in controller.children {
            if let tabs = firstTabBarController(under: child) { return tabs }
        }
        return firstTabBarController(under: controller.presentedViewController)
    }
}
