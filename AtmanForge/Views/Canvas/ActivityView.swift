import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ActivityView: View {
    @Environment(AppState.self) private var appState
    var thumbnailMaxSize: CGFloat = 64
    @State private var expandedJobs: Set<UUID> = []

    private var projectRoot: URL? {
        appState.projectManager.projectsRootURL
    }

    var body: some View {
        Group {
            if appState.generationJobs.isEmpty {
                emptyState
            } else {
                jobListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        .quickLookKeyHandler(appState: appState)
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No activity yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Generated images will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var jobListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.generationJobs) { job in
                    ActivityRowView(
                        job: job,
                        thumbnailMaxSize: thumbnailMaxSize,
                        projectRoot: projectRoot,
                        isExpanded: expandedJobs.contains(job.id),
                        onToggleExpanded: {
                            if expandedJobs.contains(job.id) {
                                expandedJobs.remove(job.id)
                            } else {
                                expandedJobs.insert(job.id)
                            }
                        }
                    )
                    if expandedJobs.contains(job.id), let params = job.requestParamsJSON, !params.isEmpty {
                        requestDetailsRow(job: job)
                    }
                    Divider()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: expandedJobs)
        }
    }

    private func requestDetailsView(_ params: String) -> some View {
        ScrollView(.vertical) {
            Text(params)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
        .padding(8)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func requestDetailsRow(job: GenerationJob) -> some View {
        Group {
            if let params = job.requestParamsJSON, !params.isEmpty {
                requestDetailsView(params)
                    .padding(.leading, 30)
                    .padding(.vertical, 4)
            }
        }
    }

}

/// Standalone row so hover state invalidates a single row instead of the whole
/// activity list, and rows whose inputs are unchanged can be skipped entirely
/// when the parent re-renders (new jobs, progress ticks, expansion toggles).
struct ActivityRowView: View {
    @Environment(AppState.self) private var appState
    let job: GenerationJob
    let thumbnailMaxSize: CGFloat
    let projectRoot: URL?
    let isExpanded: Bool
    var onToggleExpanded: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Status icon or spinner
            Group {
                if job.status == .running {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: job.statusIcon)
                        .foregroundStyle(job.statusColor)
                }
            }
            .frame(width: 20)
            .padding(.top, 2)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(job.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if (job.status == .completed || job.status == .failed || job.status == .cancelled) && isHovered {
                        Button {
                            appState.retryJob(info: ImageInfo(job: job))
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)

                        Button {
                            appState.loadSettingsCompatible(from: ImageInfo(job: job))
                        } label: {
                            Label("Reuse Parameters", systemImage: "doc.text.image")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)

                        #if DEBUG
                        if let params = job.requestParamsJSON, !params.isEmpty {
                            Button {
                                onToggleExpanded?()
                            } label: {
                                Label("Show Request", systemImage: "doc.text.magnifyingglass")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        }
                        #endif
                    } else if job.status != .completed {
                        Text(job.progressText)
                            .font(.caption)
                            .foregroundStyle(job.statusColor)
                    }
                    Spacer()
                    if job.status == .running || job.status == .pending {
                        elapsedTimeView(job: job)
                    } else if let elapsed = job.elapsedTime, job.startedAt != nil {
                        Text(Self.formatDuration(elapsed))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if job.status == .running || job.status == .pending {
                        Button {
                            appState.cancelJob(job)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel generation")
                    } else {
                        Text(relativeTime(job.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(alignment: .top, spacing: 4) {
                    Text(job.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !job.prompt.isEmpty {
                        Button {
                            copyToClipboard(job.prompt)
                            appState.showToast("Prompt copied", icon: "doc.on.doc")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy prompt")
                        .opacity(isHovered ? 1 : 0)
                    }
                }

                if job.status == .completed && !job.thumbnailPaths.isEmpty, let root = projectRoot {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(job.thumbnailPaths.enumerated()), id: \.element) { index, thumbPath in
                            let savedURL = index < job.savedImagePaths.count
                                ? root.appendingPathComponent(job.savedImagePaths[index])
                                : nil
                            thumbnailImage(
                                root.appendingPathComponent(thumbPath),
                                aspectRatio: job.aspectRatio,
                                isSelected: appState.selectedImageInfo?.id == job.id && appState.selectedImageIndex == index,
                                savedImageURL: savedURL,
                                onTap: {
                                    appState.selectImage(ImageInfo(job: job), index: index)
                                },
                                onPreview: {
                                    #if os(macOS)
                                    if let savedURL { QuickLookController.shared.preview(url: savedURL) }
                                    #endif
                                }
                            )
                        }
                    }
                    .padding(.top, 2)
                }

                if job.status == .completed && !job.savedImagePaths.isEmpty && job.thumbnailPaths.isEmpty {
                    Text("\(job.savedImagePaths.count) image\(job.savedImagePaths.count == 1 ? "" : "s") saved")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                if let error = job.errorMessage, job.status == .failed {
                    HStack(alignment: .top, spacing: 4) {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                        Button {
                            copyToClipboard(error)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy error message")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if appState.selectedImageInfo?.id != job.id {
                appState.selectImage(ImageInfo(job: job), index: 0)
            }
        }
        .onHover { isHovered = $0 }
        .background(
            isHovered
                ? Color.primary.opacity(0.06)
                : (job.status == .running ? Color.accentColor.opacity(0.05) : Color.clear)
        )
        .contextMenu {
            if let error = job.errorMessage, job.status == .failed {
                Button {
                    copyToClipboard(error)
                } label: {
                    Label("Copy Error", systemImage: "doc.on.doc")
                }
                Divider()
            }
            Button(role: .destructive) {
                appState.removeJob(job)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func elapsedTimeView(job: GenerationJob) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let start = job.startedAt {
                let elapsed = context.date.timeIntervalSince(start)
                Text(Self.formatDuration(elapsed))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            let remainder = seconds % 60
            return "\(minutes)m \(remainder)s"
        }
    }

    private func thumbnailImage(_ url: URL, aspectRatio: AspectRatio, isSelected: Bool = false, savedImageURL: URL? = nil, onTap: (() -> Void)? = nil, onPreview: (() -> Void)? = nil) -> some View {
        let maxDim = thumbnailMaxSize
        let (w, h) = aspectRatio.ratio
        let thumbWidth: CGFloat
        let thumbHeight: CGFloat
        if w >= h {
            thumbWidth = maxDim
            thumbHeight = maxDim * CGFloat(h) / CGFloat(w)
        } else {
            thumbHeight = maxDim
            thumbWidth = maxDim * CGFloat(w) / CGFloat(h)
        }

        let wrappedTap: (Bool, Bool) -> Void = { _, _ in onTap?() }
        return ThumbnailHoverView(url: url, width: thumbWidth, height: thumbHeight, isSelected: isSelected, savedImageURL: savedImageURL, onTap: wrappedTap, onPreview: onPreview)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
}

struct ThumbnailHoverView: View {
    @Environment(AppState.self) private var appState
    let url: URL
    let width: CGFloat
    let height: CGFloat
    var isSelected: Bool = false
    var savedImageURL: URL?
    var onTap: ((_ commandDown: Bool, _ shiftDown: Bool) -> Void)?
    var onPreview: (() -> Void)?
    var extraContextMenu: (() -> AnyView)?
    /// URLs to add as references when multi-selected (nil = single-image default)
    var multiSelectedImageURLs: [URL]?

    @State private var isHovered = false
    #if os(macOS)
    @State private var loadedImage: NSImage?
    #else
    @State private var loadedImage: UIImage?
    #endif
    @State private var loadFailed = false

    var body: some View {
        Group {
            #if os(macOS)
            if let nsImage = ThumbnailCache.shared.cachedImage(for: url) ?? loadedImage {
                imageContent(nsImage)
                    .contextMenu { contextMenuItems }
                    .onDrag {
                        guard let fileURL = savedImageURL else { return NSItemProvider() }
                        return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
                    }
            } else if loadFailed {
                Color.clear.frame(width: width, height: height)
            } else {
                placeholderThumb
            }
            #else
            if let uiImage = ThumbnailCache.shared.cachedImage(for: url) ?? loadedImage {
                imageContent(Image(uiImage: uiImage))
                    .onTapGesture(count: 2) {
                        onPreview?()
                    }
                    .contextMenu { contextMenuItems }
                    .onDrag {
                        guard let fileURL = savedImageURL else { return NSItemProvider() }
                        return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
                    }
            } else if loadFailed {
                Color.clear.frame(width: width, height: height)
            } else {
                placeholderThumb
            }
            #endif
        }
        .task(id: url) {
            if ThumbnailCache.shared.cachedImage(for: url) != nil { return }
            loadedImage = nil
            loadFailed = false
            if let image = await ThumbnailCache.shared.imageAsync(for: url) {
                loadedImage = image
            } else {
                loadFailed = true
            }
        }
    }

    private var placeholderThumb: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: width, height: height)
    }

    private var isMultiSelected: Bool {
        multiSelectedImageURLs != nil
    }

    private func updateHoveredPreviewURL(isHovered: Bool) {
        guard let previewURL = savedImageURL else { return }
        if isHovered {
            appState.hoveredPreviewURL = previewURL
            #if os(macOS)
            QuickLookController.shared.updateIfVisible(url: previewURL)
            #endif
        } else if appState.hoveredPreviewURL == previewURL {
            appState.hoveredPreviewURL = nil
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if let fileURL = savedImageURL {
            if let onPreview {
                Button {
                    onPreview()
                } label: {
                    Label("Preview", systemImage: "eye")
                }
            }

            Button {
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                #endif
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Divider()

            if let urls = multiSelectedImageURLs {
                Button {
                    var allData: [Data] = []
                    for u in urls {
                        if let data = try? Data(contentsOf: u) {
                            allData.append(data)
                        }
                    }
                    appState.addReferenceImages(allData)
                } label: {
                    Label("Add \(urls.count) to Reference", systemImage: "photo.on.rectangle.angled")
                }
            } else {
                Button {
                    if let data = try? Data(contentsOf: fileURL) {
                        appState.addReferenceImages([data])
                    }
                } label: {
                    Label("Add to Reference", systemImage: "photo.on.rectangle.angled")
                }

                Button {
                    appState.prompt = ""
                    appState.referenceImages.removeAll()
                    if let data = try? Data(contentsOf: fileURL) {
                        appState.addReferenceImages([data])
                    }
                    appState.commitUndoCheckpoint()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            if let extra = extraContextMenu {
                extra()
            }
        }
    }

    #if os(macOS)
    private func imageContent(_ nsImage: NSImage) -> some View {
        NativeHoverZoomView(
            nsImage: nsImage,
            width: width,
            height: height,
            isSelected: isSelected,
            onTap: onTap,
            onDoubleTap: onPreview
        )
        .frame(width: width, height: height)
        .onHover { isHovered in
            updateHoveredPreviewURL(isHovered: isHovered)
        }
    }
    #else
    private func imageContent(_ image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .opacity(isSelected ? 1 : 0)
            )
            .onTapGesture { onTap?(false, false) }
    }
    #endif
}

#if os(macOS)
struct NativeHoverZoomView: NSViewRepresentable {
    let nsImage: NSImage?
    let width: CGFloat
    let height: CGFloat
    var isSelected: Bool
    var onTap: ((_ commandDown: Bool, _ shiftDown: Bool) -> Void)?
    var onDoubleTap: (() -> Void)?

    func makeNSView(context: Context) -> HoverZoomNSView {
        let view = HoverZoomNSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.image = nsImage
        view.cornerRadius = 4
        view.onTap = onTap
        view.onDoubleTap = onDoubleTap
        return view
    }

    func updateNSView(_ nsView: HoverZoomNSView, context: Context) {
        nsView.onTap = onTap
        nsView.onDoubleTap = onDoubleTap
        nsView.updateSelection(isSelected)
    }
}

class HoverZoomNSView: NSView {
    var image: NSImage? {
        didSet { imageLayer.contents = image }
    }
    var cornerRadius: CGFloat = 4
    var onTap: ((_ commandDown: Bool, _ shiftDown: Bool) -> Void)?
    var onDoubleTap: (() -> Void)?

    private let imageLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.cornerRadius = cornerRadius
        layer?.addSublayer(imageLayer)

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.controlAccentColor.cgColor
        borderLayer.lineWidth = 3
        borderLayer.opacity = 0
        layer?.addSublayer(borderLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                   cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                                   transform: nil)
        CATransaction.commit()
    }

    func updateSelection(_ selected: Bool) {
        borderLayer.opacity = selected ? 1 : 0
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageLayer.setAffineTransform(CGAffineTransform(scaleX: 1.15, y: 1.15))
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageLayer.setAffineTransform(.identity)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleTap?()
        } else {
            let cmd = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            onTap?(cmd, shift)
        }
    }
}
#endif

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    /// Caches subview sizes and the computed rows so sizeThatFits and
    /// placeSubviews share a single measurement pass per layout instead of
    /// re-measuring every subview in both passes.
    struct Cache {
        var width: CGFloat = .nan
        var subviewCount: Int = -1
        var sizes: [CGSize] = []
        var rows: [[Int]] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        updateCacheIfNeeded(proposal: proposal, subviews: subviews, cache: &cache)
        var height: CGFloat = 0
        for (i, row) in cache.rows.enumerated() {
            let rowHeight = row.map { cache.sizes[$0].height }.max() ?? 0
            height += rowHeight
            if i > 0 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        updateCacheIfNeeded(proposal: proposal, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for (i, row) in cache.rows.enumerated() {
            if i > 0 { y += spacing }
            let rowHeight = row.map { cache.sizes[$0].height }.max() ?? 0
            var x = bounds.minX
            for index in row {
                let size = cache.sizes[index]
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight
        }
    }

    private func updateCacheIfNeeded(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let width = proposal.width ?? .infinity
        guard width != cache.width || subviews.count != cache.subviewCount else { return }

        cache.width = width
        cache.subviewCount = subviews.count
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        var rows: [[Int]] = [[]]
        var currentWidth: CGFloat = 0
        for (index, size) in cache.sizes.enumerated() {
            if currentWidth + size.width > width && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(index)
            currentWidth += size.width + spacing
        }
        cache.rows = rows
    }
}
