import CoreML
import Vision
import CoreGraphics

enum ClassifierError: Error {
    case noResult
}

/// Runs the bundled NSFW.mlmodel (LOVOO NSFWDetector, BSD license) fully on-device
/// through Vision + Core ML. Output: probability 0...1 that an image is explicit.
final class NSFWClassifier {
    static let shared: NSFWClassifier? = {
        do {
            return try NSFWClassifier()
        } catch {
            appLog("AI model failed to load: \(error.localizedDescription)")
            return nil
        }
    }()

    private let model: VNCoreMLModel

    init() throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let coreMLModel = try NSFW(configuration: configuration).model
        model = try VNCoreMLModel(for: coreMLModel)
    }

    /// Thread-safe: every call builds its own request + handler.
    func score(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> Float {
        try autoreleasepool {
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill   // look at the whole frame, no cropping
            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            try handler.perform([request])

            guard let results = request.results as? [VNClassificationObservation] else {
                throw ClassifierError.noResult
            }
            if let nsfw = results.first(where: { $0.identifier == "NSFW" }) {
                return nsfw.confidence
            }
            if let sfw = results.first(where: { $0.identifier == "SFW" }) {
                return 1 - sfw.confidence
            }
            throw ClassifierError.noResult
        }
    }
}
