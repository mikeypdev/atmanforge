import SwiftUI

struct CenterPanelView: View {
    @Environment(AppState.self) private var appState

    private static let thumbStops: [CGFloat] = [32, 64, 96, 128]

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
            Divider()
            statusBar
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.activity, label: "Activity", icon: "list.bullet.rectangle")
            tabButton(.library, label: "Library", icon: "photo.on.rectangle.angled")
            tabButton(.chat, label: "Chat", icon: "bubble.left.and.bubble.right")

            Spacer()

            if appState.selectedCenterTab != .chat {
                thumbnailScaleSlider
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func tabButton(_ tab: CenterTab, label: String, icon: String) -> some View {
        let isSelected = appState.selectedCenterTab == tab
        return Button {
            appState.selectedCenterTab = tab
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.1)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
    }

    private var thumbnailScaleSlider: some View {
        let sizeBinding = Binding<CGFloat>(
            get: {
                let size = appState.selectedCenterTab == .activity
                    ? appState.activityThumbnailSize
                    : appState.libraryThumbnailSize
                return CGFloat(Self.thumbStops.firstIndex(of: size) ?? 1)
            },
            set: { newValue in
                let size = Self.thumbStops[Int(newValue)]
                if appState.selectedCenterTab == .activity {
                    appState.activityThumbnailSize = size
                } else {
                    appState.libraryThumbnailSize = size
                }
            }
        )

        return HStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Slider(
                value: sizeBinding,
                in: 0...CGFloat(Self.thumbStops.count - 1),
                step: 1
            )
            .frame(width: 100)
            Image(systemName: "photo")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch appState.selectedCenterTab {
        case .activity:
            ActivityView(thumbnailMaxSize: appState.activityThumbnailSize)
        case .library:
            LibraryView(thumbnailMaxSize: appState.libraryThumbnailSize)
        case .chat:
            ChatView()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if appState.runningJobCount > 0 {
                ProgressView()
                    .controlSize(.small)
            }
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            if appState.runningJobCount > 0 {
                Text("\(appState.runningJobCount) job\(appState.runningJobCount == 1 ? "" : "s") running")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
            Spacer()
            if !appState.projectSizeText.isEmpty {
                Text(appState.projectSizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
