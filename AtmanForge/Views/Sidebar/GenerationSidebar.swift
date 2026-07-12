import SwiftUI

struct GenerationSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AIGenerationPanel()

            if appState.selectedCenterTab == .chat || appState.activeConversation != nil {
                ConversationList()
            }

            Spacer()
        }
        .padding()
        .frame(width: 280)
    }
}
