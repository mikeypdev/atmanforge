import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ChatView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let model = appState.selectedModel, model.conversationSupport == .none {
                ChatUnavailableView()
            } else if let conversation = appState.activeConversation, !conversation.turns.isEmpty {
                ChatConversationView(conversation: conversation)
            } else {
                ChatEmptyStateView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
    }
}

// MARK: - Active Conversation

private struct ChatConversationView: View {
    @Environment(AppState.self) private var appState
    let conversation: ChatConversation

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()
            messageList
            Divider()
            chatInputBar
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(conversation.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer()
            Text(conversation.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            if appState.isChatGenerating {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                appState.startNewConversation()
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New conversation")
            .disabled(appState.isChatGenerating)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(conversation.turns) { turn in
                        ChatTurnView(turn: turn)
                            .id(turn.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: conversation.turns.count) { _, _ in
                if let lastTurn = conversation.turns.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastTurn.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var chatInputBar: some View {
        @Bindable var appState = appState
        return HStack(spacing: 8) {
            TextField("Type a message...", text: $appState.chatInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onSubmit {
                    appState.sendChatMessage()
                }

            Button {
                appState.sendChatMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                appState.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || appState.isChatGenerating
            )
        }
        .padding(12)
    }
}

// MARK: - Single Turn

private struct ChatTurnView: View {
    @Environment(AppState.self) private var appState
    let turn: ChatTurn

    private var projectRoot: URL? {
        appState.projectManager.projectsRootURL
    }

    var body: some View {
        switch turn.role {
        case .user:
            userBubble
        case .assistant:
            assistantContent
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)
            Text(turn.text ?? "")
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var assistantContent: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                if turn.isGenerating {
                    generatingIndicator
                } else if let error = turn.errorMessage {
                    errorView(error)
                } else {
                    if let text = turn.text, !text.isEmpty {
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.background.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if !turn.savedPaths.isEmpty {
                        imageGrid
                    }
                }
            }
            Spacer(minLength: 40)
        }
    }

    private var generatingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Generating...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Failed")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var imageGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: turn.savedPaths.count > 1 ? 2 : 1)

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Array(turn.savedPaths.enumerated()), id: \.offset) { index, path in
                if let root = projectRoot {
                    let imageURL = root.appendingPathComponent(path)
                    ChatImageView(imageURL: imageURL, jobID: turn.jobID, imageIndex: index)
                }
            }
        }
    }
}

// MARK: - Chat Image

private struct ChatImageView: View {
    @Environment(AppState.self) private var appState
    let imageURL: URL
    let jobID: UUID?
    let imageIndex: Int

    #if os(macOS)
    @State private var nsImage: NSImage?
    #else
    @State private var uiImage: UIImage?
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onDrag { NSItemProvider(contentsOf: imageURL) ?? NSItemProvider() }
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #else
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #endif
        }
        .onTapGesture {
            openInInspector()
        }
        .contextMenu {
            #if os(macOS)
            Button {
                QuickLookController.shared.preview(url: imageURL)
            } label: {
                Label("Preview", systemImage: "eye")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([imageURL])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Divider()
            #endif
            Button {
                if let data = try? Data(contentsOf: imageURL) {
                    appState.addReferenceImages([data])
                }
            } label: {
                Label("Add to Reference", systemImage: "photo.on.rectangle.angled")
            }
        }
        .onHover { isHovered in
            #if os(macOS)
            if isHovered {
                appState.hoveredPreviewURL = imageURL
                QuickLookController.shared.updateIfVisible(url: imageURL)
            } else if appState.hoveredPreviewURL == imageURL {
                appState.hoveredPreviewURL = nil
            }
            #endif
        }
        .task {
            loadImage()
        }
    }

    private func openInInspector() {
        guard let jobID else { return }
        if let job = appState.generationJobs.first(where: { $0.id == jobID }) {
            appState.selectedImageJob = job
            appState.selectedImageIndex = imageIndex
        }
    }

    private func loadImage() {
        #if os(macOS)
        nsImage = NSImage(contentsOf: imageURL)
        #else
        if let data = try? Data(contentsOf: imageURL) {
            uiImage = UIImage(data: data)
        }
        #endif
    }
}

// MARK: - Empty State

private struct ChatEmptyStateView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("Conversational Generation")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Start a conversation to iteratively refine images. The model remembers context across messages.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let model = appState.selectedModel, model.conversationSupport == .limited {
                Label("This model has limited conversation support. Results may vary.", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer().frame(height: 8)

            HStack(spacing: 8) {
                TextField("Describe an image to start...", text: $appState.chatInput)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: 400)
                    .onSubmit {
                        appState.sendChatMessage()
                    }

                Button {
                    appState.sendChatMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }
}

// MARK: - Unavailable State

private struct ChatUnavailableView: View {
    @Environment(AppState.self) private var appState

    private var chatModels: [ModelDefinition] {
        appState.visibleGenerationModels.filter { $0.conversationSupport != .none }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.slash")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("Chat Not Available")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Conversational generation works with OpenRouter models that support multi-turn image editing.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if !chatModels.isEmpty {
                VStack(spacing: 8) {
                    Text("Switch to a supported model:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chatModels, id: \.id) { model in
                                Button {
                                    appState.selectedModelID = model.id
                                    appState.onModelChanged()
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(model.displayName)
                                            .font(.caption)
                                        Image(systemName: "arrow.right.circle")
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}
