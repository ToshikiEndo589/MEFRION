import Foundation
import Vision
import CoreGraphics
import OSLog

enum PetVisualError:LocalizedError {
    case photo, species, index, processing
    var errorDescription:String? {
        switch self {
        case .photo:return "犬・猫が大きく、明るく写った写真を選んでください。"
        case .species:return "わんちゃんか猫ちゃんのお顔が見える写真で試してね 🐾"
        case .index:return "検索用の素材を読み込めません。再試行してください。"
        case .processing:return "画像の認識処理を開始できませんでした。もう一度お試しください。"
        }
    }
}

enum PetVisualFeature {
    static let revision=2
    static let elements=768
    // Provisional feature-distance cutoffs, not validated resemblance scores.
    static let maximumDistance:Float=1.1
    static let duplicateDistance:Float=0.08
    static func extract(_ image:CGImage,species:String,requireSingleSubject:Bool=true,subjects:[PetSubjectCrop.Subject]?=nil) throws->[Float] {
        guard min(image.width,image.height)>=80, ["dog","cat"].contains(species) else {throw PetVisualError.photo}
        let observations=try (subjects ?? PetSubjectCrop.locate(image,species:species)).filter{$0.species==species}
        if requireSingleSubject && observations.count>1 {throw PetVisualError.photo}
        guard let animal=observations.max(by:{$0.confidence<$1.confidence}) else {throw PetVisualError.species}
        let box=animal.boundingBox
        let rectangle=CGRect(x:box.minX*Double(image.width),y:(1-box.maxY)*Double(image.height),width:box.width*Double(image.width),height:box.height*Double(image.height)).integral.intersection(CGRect(x:0,y:0,width:image.width,height:image.height))
        guard let cropped=image.cropping(to:rectangle),min(cropped.width,cropped.height)>=32 else {throw PetVisualError.photo}
        let request=VNGenerateImageFeaturePrintRequest();request.revision=revision;request.imageCropAndScaleOption = .scaleFit
        configure(request)
        try perform(request,image:cropped,stage:"feature")
        guard let result=request.results?.first,result.elementCount==elements,result.elementType == .float else {throw PetVisualError.index}
        let values=result.data.withUnsafeBytes{Array($0.bindMemory(to:Float.self))}
        guard values.count==elements,values.allSatisfy(\.isFinite) else {throw PetVisualError.index}
        return values
    }
    private static func configure(_ request:VNRequest) {
        // CPU-only is useful for deterministic desktop indexing and Simulator tests.
        // Physical iOS devices must let Vision choose supported GPU/ANE/CPU stages.
        #if targetEnvironment(simulator) || os(macOS)
        request.usesCPUOnly=true
        #elseif DEBUG
        if ProcessInfo.processInfo.arguments.contains("--twins-vision-cpu-probe") {request.usesCPUOnly=true}
        #endif
    }
    private static func perform(_ request:VNRequest,image:CGImage,stage:String) throws {
        do {try VNImageRequestHandler(cgImage:image).perform([request])}
        catch {
            let error=error as NSError
            Logger(subsystem:"dev.local.mefrion.prototype",category:"TwinsVision").error("Vision failed stage=\(stage,privacy:.public) domain=\(error.domain,privacy:.public) code=\(error.code,privacy:.public)")
            throw PetVisualError.processing
        }
    }
    static func distance(_ a:[Float],_ b:[Float])->Float {
        guard a.count==elements,b.count==elements else{return .infinity}
        return sqrt(zip(a,b).reduce(Float(0)){$0+($1.0-$1.1)*($1.0-$1.1)})
    }
    // A small image fingerprint excludes the same stock photo even when CPU/GPU
    // inference or a resize produces different Vision feature distances.
    struct Fingerprint {let edges:[Bool];let mean:Double}
    static func fingerprint(_ image:CGImage)->Fingerprint? {
        var pixels=[UInt8](repeating:0,count:81)
        let drawn=pixels.withUnsafeMutableBytes {buffer->Bool in
            guard let context=CGContext(data:buffer.baseAddress,width:9,height:9,bitsPerComponent:8,bytesPerRow:9,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else{return false}
            context.interpolationQuality = .high;context.draw(image,in:CGRect(x:0,y:0,width:9,height:9));return true
        }
        guard drawn else{return nil}
        var edges:[Bool]=[]
        for y in 0..<9 {for x in 0..<8 {edges.append(pixels[y*9+x]>pixels[y*9+x+1])}}
        for y in 0..<8 {for x in 0..<9 {edges.append(pixels[y*9+x]>pixels[(y+1)*9+x])}}
        return Fingerprint(edges:edges,mean:Double(pixels.reduce(0){$0+Int($1)})/81)
    }
    static func samePhoto(_ a:Fingerprint,_ b:Fingerprint)->Bool {
        abs(a.mean-b.mean)<=4 && zip(a.edges,b.edges).filter{$0 != $1}.count<=12
    }
}
