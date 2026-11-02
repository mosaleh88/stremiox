import SwiftUI
import Combine

/// Available navigation tabs matching the Apple TV sidebar order.
enum TabItem: Int, CaseIterable, Identifiable {
    case search = 0
    case home = 1
    case discover = 2
    case live = 3
    case library = 4
    case addons = 5
    case settings = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .search: return "Search"
        case .home: return "Home"
        case .discover: return "Discover"
        case .live: return "Live TV"
        case .library: return "Library"
        case .addons: return "Add-ons"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .search: return "magnifyingglass"
        case .home: return "house.fill"
        case .discover: return "safari.fill"
        case .live: return "dot.radiowaves.left.and.right"
        case .library: return "books.vertical.fill"
        case .addons: return "puzzlepiece.extension.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Native-styled tvOS left sidebar panel.
///
/// Features:
/// - Rounded panel floating on the left with solid dark, semi-opaque fill (no live blur for Apple TV HD).
/// - Profile avatar + real-time clock at the top.
/// - Circular icon badges with label text.
/// - Selected item: soft light highlight. Focused item: solid white with dark text.
struct SidebarView: View {
    @Binding var selectedTab: TabItem
    @Binding var isOpen: Bool
    @FocusState.Binding var focusedItem: TabItem?
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Profile Avatar + Username + Real-time Clock
            HStack(spacing: Theme.Space.sm) {
                // Profile Avatar Circle
                profileAvatar
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profiles.active?.name ?? "User")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text("Profile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                Spacer()

                // Real-time Clock
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(timeString(from: timeline.date))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Divider Hairline
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            // Navigation Items
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(TabItem.allCases) { tab in
                        SidebarItemButton(
                            tab: tab,
                            isSelected: selectedTab == tab,
                            focusedItem: $focusedItem,
                            onSelect: {
                                selectedTab = tab
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    isOpen = false
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 16)

            // Bottom Brand Footnote
            HStack(spacing: 8) {
                Text("Xtv")
                    .font(.system(size: 14, weight: .black, design: .serif))
                    .foregroundStyle(theme.accent)
                Text("tvOS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(width: 380)
        .frame(maxHeight: 1000)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                // Solid dark semi-opaque fill on HD to avoid live blur overhead
                .fill(Color(red: 0.08, green: 0.07, blue: 0.06).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.6), radius: 36, x: 12, y: 0)
    }

    private var profileAvatar: some View {
        ZStack {
            Circle()
                .fill(theme.accent)
            Text(String((profiles.active?.name ?? "U").prefix(1)).uppercased())
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Color.white)
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// An individual item in the left sidebar.
private struct SidebarItemButton: View {
    let tab: TabItem
    let isSelected: Bool
    @FocusState.Binding var focusedItem: TabItem?
    let onSelect: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Circular icon
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor)
                        .frame(width: 42, height: 42)
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(iconForegroundColor)
                }

                // Label
                Text(tab.title)
                    .font(.system(size: 20, weight: isFocused ? .bold : (isSelected ? .semibold : .medium)))
                    .foregroundStyle(labelForegroundColor)

                Spacer()

                if isSelected && !isFocused {
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($focusedItem, equals: tab)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isFocused {
            // Focused item: solid white
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
        } else if isSelected {
            // Selected item: soft light highlight
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.12))
        } else {
            Color.clear
        }
    }

    private var labelForegroundColor: Color {
        if isFocused {
            return Color.black
        } else if isSelected {
            return Color.white
        } else {
            return Color.white.opacity(0.72)
        }
    }

    private var iconBackgroundColor: Color {
        if isFocused {
            return Color.black.opacity(0.12)
        } else if isSelected {
            return Color.white.opacity(0.20)
        } else {
            return Color.white.opacity(0.10)
        }
    }

    private var iconForegroundColor: Color {
        if isFocused {
            return Color.black
        } else if isSelected {
            return Color.white
        } else {
            return Color.white.opacity(0.85)
        }
    }
}

