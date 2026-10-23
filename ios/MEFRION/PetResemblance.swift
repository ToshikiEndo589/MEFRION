import Foundation
import Vision
import CoreML
import CoreGraphics

/// A versioned descriptor; never compare it with the legacy Apple feature print.
final class PetResemblance {
    static let algorithm="dinov2-small-subject-v1"
    static let elements=384
    private let model:VNCoreMLModel
    init(url:URL?=Bundle.main.url(forResource:"MEFRIONResemblance",withExtension:"mlmodelc")) throws {
        guard let url else {throw PetVisualError.index}
        let configuration=MLModelConfiguration();configuration.computeUnits = .all
        #if targetEnvironment(simulator)
        configuration.computeUnits = .cpuOnly
        #endif
        model=try VNCoreMLModel(for:MLModel(contentsOf:url,configuration:configuration))
    }
    func features(_ image:CGImage) throws->[Float] {
        let request=VNCoreMLRequest(model:model);request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage:image).perform([request])
        guard let observations=request.results as? [VNCoreMLFeatureValueObservation],let value=observations.first(where:{$0.featureName=="embedding"})?.featureValue.multiArrayValue,value.count==Self.elements else {throw PetVisualError.index}
        let values=(0..<value.count).map{value[$0].floatValue}
        let length=sqrt(values.reduce(Float(0)){$0+$1*$1})
        guard values.allSatisfy(\.isFinite),length>0.5,length<1.5 else {throw PetVisualError.index}
        return values.map{$0/length}
    }
}
