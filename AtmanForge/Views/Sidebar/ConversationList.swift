import SwiftUI

struct ConversationList: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if !appState.conversations.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Conversations")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.conversations) { conversation in
                            ConversationRow(conversation: conversation)
                        }
                    }
                }
            }
        }
    }
}

private struct ConversationRow: View {
    @Environment(AppState.self) private var appState
    let conversation: ChatConversation

    private var isActive: Bool {
        appState.activeConversation?.id == conversation.id
    }

    var body: some View {
        Button {
            appState.selectConversation(conversation)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(isActive ? Color.white : .primary)

                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 9))
                    Text("\(imageCount) image\(imageCount == 1 ? "" : "s")")
                        .font(.system(size: 10))
                }
                .foregroundStyle(isActive ? Color.white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.8) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var imageCount: Int {
        conversation.turns.flatMap(\.savedPaths).count
    }
}
