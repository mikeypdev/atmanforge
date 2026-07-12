import Foundation

struct ChatHistoryMessage {
    enum Role { case user, assistant }
    let role: Role
    let text: String?
    let images: [Data]
}

struct GenerationRequest {
    let prompt: String
    let model: ModelDefinition
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let referenceImages: [Data]
    let parameters: [String: ParameterValue]
    var conversationHistory: [ChatHistoryMessage] = []
}

struct GenerationResult {
    let imageDataArray: [Data]
    var text: String? = nil
    var partialErrors: [String] = []
}

protocol AIProvider {
    func generateImage(request: GenerationRequest, parallelDelay: TimeInterval, onPredictionCreated: @Sendable @escaping (String, String?) -> Void) async throws -> GenerationResult
}
