import Foundation
import CoreGraphics
import UIKit
import ImageIO

extension UIImage {
    @MainActor func normalizedForTwins()->UIImage? {
        guard let cg=cgImage else{return nil}
        let rotated=[UIImage.Orientation.left,.right,.leftMirrored,.rightMirrored].contains(imageOrientation)
        let width=CGFloat(rotated ? cg.height : cg.width),height=CGFloat(rotated ? cg.width : cg.height)
        let scale=min(1,2048/max(width,height));let size=CGSize(width:width*scale,height:height*scale)
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        return UIGraphicsImageRenderer(size:size,format:format).image {context in UIColor.white.setFill();context.fill(CGRect(origin:.zero,size:size));draw(in:CGRect(origin:.zero,size:size))}
    }
}

struct ReferencePetAsset:Codable,Identifiable {
    let id:String
    let species:String
    let file:String
    let credit:String
    let source:String
    let demoOnly:Bool
}
struct ReferencePetCatalog:Codable {
    let version:Int
    let revision:Int
    let elements:Int
    let assets:[ReferencePetAsset]
}
struct ReferenceSearchRecord:Codable,Identifiable {
    let id:UUID
    let owner:String
    let created:Date
    let species:String
    let candidates:[String]
}

actor ReferenceTwinsEngine {
    static let shared=ReferenceTwinsEngine()
    static var resourceURL:URL? {Bundle.main.resourceURL?.appendingPathComponent("TwinsReferenceData",isDirectory:true)}
    private let root:URL?
    private var catalog:ReferencePetCatalog?
    private var vectors:[Float]=[]
    init(root:URL?=ReferenceTwinsEngine.resourceURL) {self.root=root}
    private func load() throws->ReferencePetCatalog {
        if let catalog {return catalog}
        guard let root else {throw PetVisualError.index}
        let next=try JSONDecoder().decode(ReferencePetCatalog.self,from:Data(contentsOf:root.appendingPathComponent("catalog.json")))
        guard next.version==1,next.revision==PetVisualFeature.revision,next.elements==PetVisualFeature.elements,
              !next.assets.isEmpty,Set(next.assets.map(\.id)).count==next.assets.count,
              next.assets.allSatisfy({["dog","cat"].contains($0.species) && $0.demoOnly && $0.file==$0.id+".jpg" && $0.id.hasPrefix("pexels-") && $0.id.dropFirst(7).allSatisfy(\.isNumber) && URL(string:$0.source)?.host=="www.pexels.com"}) else {throw PetVisualError.index}
        let data=try Data(contentsOf:root.appendingPathComponent("vectors.bin"),options:.mappedIfSafe)
        guard data.count==next.assets.count*PetVisualFeature.elements*MemoryLayout<Float>.size else {throw PetVisualError.index}
        let loaded=data.withUnsafeBytes{Array($0.bindMemory(to:Float.self))}
        guard loaded.allSatisfy(\.isFinite) else {throw PetVisualError.index}
        vectors=loaded;catalog=next;return next
    }
    func assets(species:String) throws->[ReferencePetAsset] {try load().assets.filter{$0.species==species}}
    #if DEBUG
    func diagnosticSelfDistance(image:CGImage,sample:ReferencePetAsset) throws->Float {
        let catalog=try load()
        guard let index=catalog.assets.firstIndex(where:{$0.id==sample.id}) else {throw PetVisualError.index}
        return PetVisualFeature.distance(try PetVisualFeature.extract(image,species:sample.species),Array(vectors[index*PetVisualFeature.elements..<(index+1)*PetVisualFeature.elements]))
    }
    #endif
    func search(image:CGImage,species:String) throws->[ReferencePetAsset] {
        try Task.checkCancellation()
        let query=try PetVisualFeature.extract(image,species:species)
        guard let queryFingerprint=PetVisualFeature.fingerprint(image) else {throw PetVisualError.photo}
        let catalog=try load()
        var scores:[(Int,Float)]=[]
        for (index,asset) in catalog.assets.enumerated() where asset.species==species {
            try Task.checkCancellation()
            let start=index*PetVisualFeature.elements
            var sum:Float=0
            for element in 0..<PetVisualFeature.elements {let delta=query[element]-vectors[start+element];sum+=delta*delta}
            let distance=sqrt(sum)
            if distance.isFinite && distance>PetVisualFeature.duplicateDistance && distance<=PetVisualFeature.maximumDistance {scores.append((index,distance))}
        }
        var accepted:[Int]=[]
        var acceptedFingerprints:[PetVisualFeature.Fingerprint]=[]
        for (index,_) in scores.sorted(by:{$0.1==$1.1 ? $0.0<$1.0 : $0.1<$1.1}) {
            try Task.checkCancellation()
            guard let root,let source=CGImageSourceCreateWithURL(root.appendingPathComponent("images/"+catalog.assets[index].file) as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil),let fingerprint=PetVisualFeature.fingerprint(image) else {throw PetVisualError.index}
            if PetVisualFeature.samePhoto(queryFingerprint,fingerprint) || acceptedFingerprints.contains(where:{PetVisualFeature.samePhoto($0,fingerprint)}) {continue}
            let candidate=Array(vectors[index*PetVisualFeature.elements..<(index+1)*PetVisualFeature.elements])
            if accepted.contains(where:{previous in PetVisualFeature.distance(candidate,Array(vectors[previous*PetVisualFeature.elements..<(previous+1)*PetVisualFeature.elements]))<=PetVisualFeature.duplicateDistance}) {continue}
            accepted.append(index)
            acceptedFingerprints.append(fingerprint)
            if accepted.count==3 {break}
        }
        return accepted.map{catalog.assets[$0]}
    }
    nonisolated func image(_ asset:ReferencePetAsset)->UIImage? {
        guard let root,asset.file==asset.id+".jpg",asset.id.hasPrefix("pexels-"),asset.id.dropFirst(7).allSatisfy(\.isNumber) else {return nil}
        return UIImage(contentsOfFile:root.appendingPathComponent("images/"+asset.file).path)
    }
}

actor VisionPetRanker {
    func rankStream(image:CGImage,candidateIDs:[String],species:String,load:@Sendable (String) async throws->CGImage?) async throws->[String] {
        let query=try PetVisualFeature.extract(image,species:species)
        var scores:[(String,Float,[Float])]=[]
        for id in candidateIDs.prefix(100) {
            try Task.checkCancellation()
            guard let candidate=try await load(id) else {continue}
            guard let feature=try? PetVisualFeature.extract(candidate,species:species) else {continue}
            let distance=PetVisualFeature.distance(query,feature)
            if distance>PetVisualFeature.duplicateDistance && distance<=PetVisualFeature.maximumDistance {scores.append((id,distance,feature))}
        }
        var accepted:[(String,Float,[Float])]=[]
        for item in scores.sorted(by:{$0.1==$1.1 ? $0.0<$1.0 : $0.1<$1.1}) {
            if accepted.contains(where:{PetVisualFeature.distance(item.2,$0.2)<=PetVisualFeature.duplicateDistance}) {continue}
            accepted.append(item);if accepted.count==3 {break}
        }
        return accepted.map(\.0)
    }
}

extension PrototypeStore {
    func saveReferenceSearch(owner:String,species:String,candidates:[String],now:Date=Date()) throws {
        guard !owner.isEmpty,["dog","cat"].contains(species),!candidates.isEmpty,candidates.count<=3,
              Set(candidates).count==candidates.count,candidates.allSatisfy({$0.hasPrefix("pexels-") && !$0.dropFirst(7).isEmpty && $0.dropFirst(7).allSatisfy(\.isNumber)}) else {throw PetVisualError.index}
        try persistMutation {
            referenceTwinsHistory=referenceTwinsHistory.filter{let age=now.timeIntervalSince($0.created);return age>=0 && age<86400}
            referenceTwinsHistory.insert(ReferenceSearchRecord(id:UUID(),owner:owner,created:now,species:species,candidates:candidates),at:0)
            referenceTwinsHistory=Array(referenceTwinsHistory.prefix(20))
        }
    }
    func eraseReferenceHistory(owner:String) throws {try persistMutation {referenceTwinsHistory.removeAll{$0.owner==owner}}}
}

struct ReferenceServerSummary:Decodable {let count:Int;let assets:[ReferencePetAsset]}
struct ReferenceQuery:Sendable {let values:[Float];let fingerprint:String;let mean:Double;var resemblance:[Float]=[];var color:[Float]=[];var cropKind:String="animal"}
actor ReferenceQueryEncoder {
    private var model:PetResemblance?
    func encode(_ image:CGImage,species:String) throws->ReferenceQuery {
        try Task.checkCancellation()
        let values=try PetVisualFeature.extract(image,species:species)
        guard let fingerprint=PetVisualFeature.fingerprint(image) else {throw PetVisualError.photo}
        let cropped=try PetSubjectCrop.crop(image,species:species)
        try Task.checkCancellation()
        if model==nil {model=try PetResemblance()}
        let descriptor=try model!.features(cropped.image)
        return ReferenceQuery(values:values,fingerprint:fingerprint.edges.map{$0 ? "1" : "0"}.joined(),mean:fingerprint.mean,resemblance:descriptor,color:PetSubjectCrop.color(cropped.image),cropKind:cropped.kind)
    }
}

/// Production-shaped development path: only a query vector leaves this device.
/// The bundled index remains a fixture for isolated tests, never a network fallback.
@MainActor final class ReferenceTwinsService {
    static let shared=ReferenceTwinsService()
    private let fixture=ReferenceTwinsEngine.shared
    private let encoder=ReferenceQueryEncoder()
    private var images:[String:UIImage]=[:]
    private var cacheOrder:[String]=[]
    private var fixtureMode:Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-test-isolated") && !ProcessInfo.processInfo.arguments.contains("--server-reference-probe")
        #else
        return false
        #endif
    }
    func summary(species:String) async throws->ReferenceServerSummary {
        if fixtureMode {let assets=try await fixture.assets(species:species);return ReferenceServerSummary(count:assets.count,assets:Array(assets.prefix(1)))}
        let summary=try await CloudFamilyClient.shared.referenceSummary(species:species)
        try await loadImages(summary.assets)
        return summary
    }
    func search(image:CGImage,species:String,consent:Bool,request:UUID) async throws->[ReferencePetAsset] {
        guard consent else {throw PetVisualError.photo}
        if fixtureMode {return try await fixture.search(image:image,species:species)}
        let query=try await encoder.encode(image,species:species)
        try Task.checkCancellation()
        let found=try await CloudFamilyClient.shared.referenceSearch(query:query,species:species,consent:consent,requestID:request)
        try Task.checkCancellation()
        // Re-check active status before rendering; withdrawn candidates disappear.
        let active=try await CloudFamilyClient.shared.referenceLookup(ids:found.map(\.id))
        try await loadImages(active)
        return active
    }
    func lookup(ids:[String]) async throws->[ReferencePetAsset] {
        if fixtureMode {let dogs=try await fixture.assets(species:"dog"),cats=try await fixture.assets(species:"cat");return (dogs+cats).filter{ids.contains($0.id)}}
        let assets=try await CloudFamilyClient.shared.referenceLookup(ids:Array(Set(ids).sorted().prefix(60)))
        try await loadImages(assets);return assets
    }
    func image(_ asset:ReferencePetAsset)->UIImage? {fixtureMode ? fixture.image(asset) : images[asset.id]}
    private func loadImages(_ assets:[ReferencePetAsset]) async throws {
        for asset in assets {
            try Task.checkCancellation()
            // Always refetch active images so a stale local cache cannot bypass withdrawal.
            images[asset.id]=try await CloudFamilyClient.shared.referenceImage(id:asset.id)
            cacheOrder.removeAll{$0==asset.id};cacheOrder.append(asset.id)
            while cacheOrder.count>64 {images.removeValue(forKey:cacheOrder.removeFirst())}
        }
    }
}
