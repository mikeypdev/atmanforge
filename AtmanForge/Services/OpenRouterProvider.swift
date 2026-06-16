import Foundation

class OpenRouterProvider: AIProvider {
    private let apiKey: String
    private let session = URLSession.shared
    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let imagesBaseURL = URL(string: "https://openrouter.ai/api/v1/images/generations")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func generateImage(
        request: GenerationRequest,
        parallelDelay: TimeInterval = 5.0,
        onPredictionCreated: @Sendable @escaping (String, String?) -> Void
    ) async throws -> GenerationResult {
        let paramsJSON = buildParamsDebugJSON(for: request)

        if request.imageCount <= 1 {
            let imageData = try await generateSingle(request: request)
            onPredictionCreated("", paramsJSON)
            return GenerationResult(imageDataArray: imageData)
        }

        // Multiple images: fire requests sequentially with throttle, poll in parallel
        return await withTaskGroup(of: Result<(Int, [Data]), Error>.self) { group in
            for i in 0..<request.imageCount {
                if i > 0 && parallelDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(parallelDelay * 1_000_000_000))
                }
                onPredictionCreated("", paramsJSON)
                group.addTask { [self] in
                    do {
                        let images = try await generateSingle(request: request)
                        return .success((i, images))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var successes: [(Int, [Data])] = []
            var errors: [String] = []
            for await result in group {
                switch result {
                case .success(let value): successes.append(value)
                case .failure(let error): errors.append(error.localizedDescription)
                }
            }
            if successes.isEmpty {
                return GenerationResult(imageDataArray: [], partialErrors: errors.isEmpty ? ["All requests failed"] : errors)
            }
            successes.sort { $0.0 < $1.0 }
            let allImageData = successes.flatMap(\.1)
            return GenerationResult(imageDataArray: allImageData, partialErrors: errors)
        }
    }

    // MARK: - Single request

    private func generateSingle(request: GenerationRequest) async throws -> [Data] {
        if request.model.usesImagesEndpoint {
            return try await generateSingleImages(request: request)
        }
        let body = try buildRequestBody(for: request)

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("AtmanForge", forHTTPHeaderField: "X-Title")
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = 300

        let (data, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: data)

        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let message = result.choices.first?.message else {
            throw OpenRouterError.noOutput
        }

        let images: [Data] = try (message.images ?? []).compactMap { img in
            guard let dataURL = img.image_url?.url else { return nil }
            return try? extractBase64Data(from: dataURL)
        }

        if images.isEmpty {
            // Some models might return images embedded differently; check content
            throw OpenRouterError.noOutput
        }

        return images
    }

    // MARK: - Images endpoint (FLUX, Recraft, etc.)

    private func generateSingleImages(request: GenerationRequest) async throws -> [Data] {
        let body = try buildImagesRequestBody(for: request)

        var urlRequest = URLRequest(url: imagesBaseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("AtmanForge", forHTTPHeaderField: "X-Title")
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = 300

        let (data, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: data)

        let result = try JSONDecoder().decode(ImagesResponse.self, from: data)

        let images: [Data] = result.data.compactMap { item in
            if let b64 = item.b64_json, let imgData = Data(base64Encoded: b64) {
                return imgData
            }
            if let urlString = item.url, let url = URL(string: urlString) {
                return try? Data(contentsOf: url)
            }
            return nil
        }

        if images.isEmpty {
            throw OpenRouterError.noOutput
        }

        return images
    }

    private func buildImagesRequestBody(for request: GenerationRequest) throws -> Data {
        var body: [String: Any] = [
            "model": request.model.replicateModelID,
            "prompt": request.prompt,
            "n": 1,
            "response_format": "b64_json",
        ]

        // Build image_config from aspect ratio, resolution, and model parameters
        var imageConfig: [String: Any] = [:]
        imageConfig["aspect_ratio"] = request.aspectRatio.rawValue

        if request.model.supportsResolution, let resolution = request.resolution {
            imageConfig["image_size"] = resolution.rawValue
        }

        for (key, value) in request.model.staticInputs {
            imageConfig[key] = value.jsonObject
        }
        for (key, value) in request.parameters {
            imageConfig[key] = value.jsonObject
        }

        if !imageConfig.isEmpty {
            body["image_config"] = imageConfig
        }

        // Include reference images if supported (e.g. FLUX img2img)
        if !request.referenceImages.isEmpty {
            let refKey = request.model.referenceKey?.name ?? "image"
            if request.model.referenceKey?.kind == .array {
                body[refKey] = request.referenceImages.map { img in
                    "data:image/png;base64,\(img.base64EncodedString())"
                }
            } else {
                if let first = request.referenceImages.first {
                    body[refKey] = "data:image/png;base64,\(first.base64EncodedString())"
                }
            }
        }

        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Request building

    private func buildRequestBody(for request: GenerationRequest) throws -> Data {
        // Build content array: text prompt + optional reference images
        var content: [Any] = [
            ["type": "text", "text": request.prompt]
        ]

        // Add reference images as base64 data URLs
        if !request.referenceImages.isEmpty {
            for imageData in request.referenceImages {
                let base64 = imageData.base64EncodedString()
                let dataURL = "data:image/png;base64,\(base64)"
                content.append([
                    "type": "image_url",
                    "image_url": ["url": dataURL]
                ])
            }
        }

        var body: [String: Any] = [
            "model": request.model.replicateModelID,
            "messages": [
                ["role": "user", "content": content]
            ],
            "modalities": ["image", "text"],
            "stream": false,
        ]

        // Build image_config from aspect ratio, resolution, and model parameters
        var imageConfig: [String: Any] = [:]

        imageConfig["aspect_ratio"] = request.aspectRatio.rawValue

        if request.model.supportsResolution, let resolution = request.resolution {
            imageConfig["image_size"] = resolution.rawValue
        }

        // Map model static inputs and user parameters into image_config
        for (key, value) in request.model.staticInputs {
            imageConfig[key] = value.jsonObject
        }
        for (key, value) in request.parameters {
            imageConfig[key] = value.jsonObject
        }

        if !imageConfig.isEmpty {
            body["image_config"] = imageConfig
        }

        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Helpers

    private func extractBase64Data(from dataURL: String) throws -> Data {
        // Format: data:image/png;base64,<data>
        guard let commaIndex = dataURL.firstIndex(of: ",") else {
            throw OpenRouterError.invalidResponse
        }
        let base64String = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64String) else {
            throw OpenRouterError.invalidResponse
        }
        return data
    }

    private func buildParamsDebugJSON(for request: GenerationRequest) -> String? {
        let debugInfo: [String: Any] = [
            "model": request.model.replicateModelID,
            "aspect_ratio": request.aspectRatio.rawValue,
            "modalities": ["image", "text"],
        ]
        guard JSONSerialization.isValidJSONObject(debugInfo) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: debugInfo, options: [.prettyPrinted]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw OpenRouterError.httpError(http.statusCode, body)
        }
    }
}

// MARK: - Error

enum OpenRouterError: LocalizedError {
    case httpError(Int, String)
    case noOutput
    case invalidResponse
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "OpenRouter API error (\(code)): \(body)"
        case .noOutput:
            return "OpenRouter returned no images."
        case .invalidResponse:
            return "Invalid response from OpenRouter."
        case .noAPIKey:
            return "No OpenRouter API key configured."
        }
    }
}

// MARK: - Response Models

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]
}

private struct Choice: Decodable {
    let message: Message
}

private struct Message: Decodable {
    let content: String?
    let images: [ChatImage]?
}

private struct ChatImage: Decodable {
    let image_url: ImageURL?
}

private struct ImageURL: Decodable {
    let url: String
}

// MARK: - Images Endpoint Response

private struct ImagesResponse: Decodable {
    let data: [ImageDataItem]
}

private struct ImageDataItem: Decodable {
    let b64_json: String?
    let url: String?
}
