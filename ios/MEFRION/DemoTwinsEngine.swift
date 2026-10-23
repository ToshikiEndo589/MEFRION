import UIKit
import CryptoKit

// Provisional prototype settings, not a validated pet-resemblance quality threshold.
enum DemoTwinsPolicy {
    static let minimumPixels = PrototypePolicy.twinsMinimumPixels
    static let maximumDistance: Float = PrototypePolicy.twinsMaximumDistance
    static let duplicateDistance: Float = PrototypePolicy.twinsDuplicateDistance
    static let maximumCandidates = PrototypePolicy.twinsCandidates
}

enum DemoTwinsError: LocalizedError {
    case photoQuality
    var errorDescription: String? { "明るく、顔と輪郭が大きくはっきり写った写真で試してください。" }
}

struct TwinsMatch: Identifiable {
    let id: Int
    let distance: Float // Internal ranking only. Never shown as a percentage.
}

actor DemoTwinsEngine {
    // Initial, reproducible visual comparison. This measures colour and local
    // contours; it is not a trained pet identity/resemblance model.
    private struct VisualFeature {let values:[Float];let fingerprint:SHA256.Digest?}
    private func visualFeature(_ image:CGImage) throws->VisualFeature {
        let size=32
        guard let context=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw DemoTwinsError.photoQuality}
        context.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1));context.fill(CGRect(x:0,y:0,width:size,height:size));context.interpolationQuality = .high
        context.draw(image,in:CGRect(x:0,y:0,width:size,height:size))
        guard let bytes=context.data else {throw DemoTwinsError.photoQuality}
        let pixels=bytes.bindMemory(to:UInt8.self,capacity:size*size*4)
        var values:[Float]=[];values.reserveCapacity(size*size*4)
        for y in 0..<size {for x in 0..<size {
            let i=(y*size+x)*4
            for channel in 0..<3 {values.append(Float(pixels[i+channel])/255)}
            let next=(y*size+min(size-1,x+1))*4
            let below=(min(size-1,y+1)*size+x)*4
            let luminance=(Float(pixels[i])+Float(pixels[i+1])+Float(pixels[i+2]))/765
            let horizontal=(Float(pixels[next])+Float(pixels[next+1])+Float(pixels[next+2]))/765
            let vertical=(Float(pixels[below])+Float(pixels[below+1])+Float(pixels[below+2]))/765
            values.append((abs(luminance-horizontal)+abs(luminance-vertical))*2)
        }}
        return VisualFeature(values:values,fingerprint:pixelFingerprint(image))
    }
    private func distance(_ a:VisualFeature,_ b:VisualFeature)->Float {
        sqrt(zip(a.values,b.values).reduce(Float(0)) {$0+($1.0-$1.1)*($1.0-$1.1)}/Float(a.values.count))*3
    }
    private func selected(_ scored:[(String,Float,VisualFeature)])->[(String,Float)] {
        var accepted:[(String,Float,VisualFeature)]=[]
        for item in scored.sorted(by:{$0.1 == $1.1 ? $0.0<$1.0 : $0.1<$1.1}) {
            if !accepted.contains(where:{distance(item.2,$0.2)<=DemoTwinsPolicy.duplicateDistance}) {accepted.append(item)}
            if accepted.count==DemoTwinsPolicy.maximumCandidates {break}
        }
        return accepted.map{($0.0,$0.1)}
    }
    private func queryFeature(_ image:CGImage) throws->VisualFeature {
        guard image.width>=DemoTwinsPolicy.minimumPixels,image.height>=DemoTwinsPolicy.minimumPixels else {throw DemoTwinsError.photoQuality}
        let feature=try visualFeature(image)
        let colour=stride(from:0,to:feature.values.count,by:4).map{(feature.values[$0]+feature.values[$0+1]+feature.values[$0+2])/3}
        let mean=colour.reduce(0,+)/Float(colour.count)
        let variance=colour.reduce(Float(0)){$0+($1-mean)*($1-mean)}/Float(colour.count)
        guard mean>0.02,variance>0.0001 else {throw DemoTwinsError.photoQuality}
        return feature
    }
    private func score(_ id:String,_ candidate:CGImage,_ query:VisualFeature) throws->(String,Float,VisualFeature)? {
        let feature=try visualFeature(candidate)
        if let fingerprint=query.fingerprint,fingerprint==feature.fingerprint {return nil}
        let value=distance(query,feature)
        return value.isFinite && value>DemoTwinsPolicy.duplicateDistance && value<=DemoTwinsPolicy.maximumDistance ? (id,value,feature) : nil
    }
    func search(image:CGImage,species:Species,excluding excludedID:Int?=nil) throws->[TwinsMatch] {
        let query=try queryFeature(image);var scored:[(String,Float,VisualFeature)]=[]
        for id in 0..<10 where id != excludedID && (id%2==0)==(species == .dog) {
            if let image=UIImage(named:"pet-\(id)")?.cgImage,let item=try score(String(id),image,query) {scored.append(item)}
        }
        return selected(scored).compactMap {id,distance in Int(id).map{TwinsMatch(id:$0,distance:distance)}}
    }
    func rank(image:CGImage,candidates:[(String,CGImage)]) throws->[String] {
        let query=try queryFeature(image)
        return try selected(candidates.prefix(100).compactMap{try score($0.0,$0.1,query)}).map(\.0)
    }
    // Only compact descriptors are retained. Each decoded candidate is released
    // before the next network request; the UI loads the selected three separately.
    func rankStream(image:CGImage,candidateIDs:[String],load:@Sendable (String) async throws->CGImage?) async throws->[String] {
        let query=try queryFeature(image);var scored:[(String,Float,VisualFeature)]=[]
        for id in candidateIDs.prefix(100) {
            try Task.checkCancellation()
            if let image=try await load(id),let item=try score(id,image,query) {scored.append(item)}
        }
        return selected(scored).map(\.0)
    }

    func pixelFingerprint(_ image: CGImage) -> SHA256.Digest? {
        guard let context = CGContext(data: nil, width: 64, height: 64,
                                      bitsPerComponent: 8, bytesPerRow: 256,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1));context.fill(CGRect(x:0,y:0,width:64,height:64))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let bytes = context.data else { return nil }
        return SHA256.hash(data: Data(bytes: bytes, count: 64 * 256))
    }

}
