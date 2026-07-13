import Foundation
import SwiftUI

@MainActor
@Observable
class ChatConversation: Identifiable {
    let id: UUID
    let modelID: String
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    var turns: [ChatTurn] = []
    var title: String
    let createdAt: Date

    init(modelID: String, aspectRatio: AspectRatio, resolution: ImageResolution?) {
        self.id = UUID()
        self.modelID = modelID
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.title = "New Conversation"
        self.createdAt = Date()
    }

    private init(id: UUID, modelID: String, aspectRatio: AspectRatio, resolution: ImageResolution?, turns: [ChatTurn], title: String, createdAt: Date) {
        self.id = id
        self.modelID = modelID
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.turns = turns
        self.title = title
        self.createdAt = createdAt
    }

    static func restore(id: UUID, modelID: String, aspectRatio: AspectRatio, resolution: ImageResolution?, turns: [ChatTurn], title: String, createdAt: Date) -> ChatConversation {
        ChatConversation(id: id, modelID: modelID, aspectRatio: aspectRatio, resolution: resolution, turns: turns, title: title, createdAt: createdAt)
    }

    var model: ModelDefinition? {
        ModelRegistry.shared.model(id: modelID)
    }

    var isEmpty: Bool {
        turns.isEmpty
    }

    var displayName: String {
        model?.displayName ?? modelID
    }

    func loadImageData(from projectRoot: URL) {
        for i in turns.indices {
            guard turns[i].images.isEmpty, !turns[i].savedPaths.isEmpty else { continue }
            turns[i].images = turns[i].savedPaths.compactMap { path in
                let url = projectRoot.appendingPathComponent(path)
                return try? Data(contentsOf: url)
            }
        }
    }
}

struct ChatTurn: Identifiable {
    var id: UUID
    let role: Role
    var text: String?
    var images: [Data]
    var savedPaths: [String]
    var thumbnailPaths: [String]
    var jobID: UUID?
    var settingsSummary: String?
    var isGenerating: Bool
    var errorMessage: String?
    var timestamp: Date

    enum Role: String {
        case user
        case assistant
    }

    init(
        role: Role,
        text: String? = nil,
        images: [Data] = [],
        savedPaths: [String] = [],
        thumbnailPaths: [String] = [],
        jobID: UUID? = nil,
        settingsSummary: String? = nil,
        isGenerating: Bool = false,
        errorMessage: String? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.images = images
        self.savedPaths = savedPaths
        self.thumbnailPaths = thumbnailPaths
        self.jobID = jobID
        self.settingsSummary = settingsSummary
        self.isGenerating = isGenerating
        self.errorMessage = errorMessage
        self.timestamp = Date()
    }
}

struct PersistableConversation: Codable {
    let id: UUID
    let modelID: String
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let turns: [PersistableTurn]
    let title: String
    let createdAt: Date
}

struct PersistableTurn: Codable {
    let id: UUID
    let role: String
    let text: String?
    let savedPaths: [String]
    let thumbnailPaths: [String]
    let jobID: UUID?
    let settingsSummary: String?
    let timestamp: Date
}

@MainActor
func toPersistable(_ conversation: ChatConversation) -> PersistableConversation {
    PersistableConversation(
        id: conversation.id,
        modelID: conversation.modelID,
        aspectRatio: conversation.aspectRatio,
        resolution: conversation.resolution,
        turns: conversation.turns.map { toPersistable($0) },
        title: conversation.title,
        createdAt: conversation.createdAt
    )
}

func toPersistable(_ turn: ChatTurn) -> PersistableTurn {
    PersistableTurn(
        id: turn.id,
        role: turn.role.rawValue,
        text: turn.text,
        savedPaths: turn.savedPaths,
        thumbnailPaths: turn.thumbnailPaths,
        jobID: turn.jobID,
        settingsSummary: turn.settingsSummary,
        timestamp: turn.timestamp
    )
}

@MainActor
func fromPersistable(_ p: PersistableConversation) -> ChatConversation {
    ChatConversation.restore(
        id: p.id,
        modelID: p.modelID,
        aspectRatio: p.aspectRatio,
        resolution: p.resolution,
        turns: p.turns.map { fromPersistable($0) },
        title: p.title,
        createdAt: p.createdAt
    )
}

func fromPersistable(_ p: PersistableTurn) -> ChatTurn {
    var turn = ChatTurn(
        role: ChatTurn.Role(rawValue: p.role) ?? .assistant,
        text: p.text,
        savedPaths: p.savedPaths,
        thumbnailPaths: p.thumbnailPaths,
        jobID: p.jobID,
        settingsSummary: p.settingsSummary
    )
    turn.id = p.id
    turn.timestamp = p.timestamp
    return turn
}
