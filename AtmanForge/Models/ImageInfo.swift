import Foundation
import SwiftUI

struct ImageInfo: Identifiable {
    let id: UUID
    let savedImagePaths: [String]
    let thumbnailPaths: [String]
    let modelID: String
    let prompt: String
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let parameters: [String: ParameterValue]
    let createdAt: Date
    let referenceImagePaths: [String]
    let requestParamsJSON: String?
    let jobID: UUID?

    @MainActor
    var model: ModelDefinition? {
        ModelRegistry.shared.model(id: modelID)
    }

    @MainActor
    var displayName: String {
        model?.displayName ?? modelID
    }

    @MainActor
    var settingsSummary: String {
        var parts: [String] = [aspectRatio.displayName]
        if let res = resolution { parts.append(res.displayName) }
        if savedImagePaths.count > 1 { parts.append("\(savedImagePaths.count) images") }
        if let specs = model?.parameters {
            for spec in specs {
                guard let value = parameters[spec.key] else { continue }
                switch value {
                case .string(let s): parts.append("\(spec.label): \(s)")
                case .double(let d):
                    let formatted = d.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int(d))
                        : String(format: "%.2f", d)
                    parts.append("\(spec.label): \(formatted)")
                case .bool(let b): parts.append("\(spec.label): \(b ? "on" : "off")")
                }
            }
        }
        return parts.joined(separator: " · ")
    }

    @MainActor
    init(job: GenerationJob) {
        self.id = job.id
        self.savedImagePaths = job.savedImagePaths
        self.thumbnailPaths = job.thumbnailPaths
        self.modelID = job.modelID
        self.prompt = job.prompt
        self.aspectRatio = job.aspectRatio
        self.resolution = job.resolution
        self.parameters = job.parameters
        self.createdAt = job.createdAt
        self.referenceImagePaths = job.referenceImagePaths
        self.requestParamsJSON = job.requestParamsJSON
        self.jobID = job.id
    }

    init(
        savedImagePaths: [String],
        thumbnailPaths: [String],
        modelID: String,
        prompt: String,
        aspectRatio: AspectRatio,
        resolution: ImageResolution?,
        parameters: [String: ParameterValue],
        createdAt: Date,
        referenceImagePaths: [String] = [],
        requestParamsJSON: String? = nil,
        jobID: UUID? = nil
    ) {
        self.id = jobID ?? UUID()
        self.savedImagePaths = savedImagePaths
        self.thumbnailPaths = thumbnailPaths
        self.modelID = modelID
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.parameters = parameters
        self.createdAt = createdAt
        self.referenceImagePaths = referenceImagePaths
        self.requestParamsJSON = requestParamsJSON
        self.jobID = jobID
    }
}
