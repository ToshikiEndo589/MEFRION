import Foundation
import Vision
import CoreGraphics
import AVFoundation
import UIKit

enum PetPostValidationError:LocalizedError {
    case imageNotRecognized,videoNotRecognized,unreadable
    var errorDescription:String? {switch self {
    case .imageNotRecognized:return "わんちゃんか猫ちゃんが写った写真を選んでね 🐾"
    case .videoNotRecognized:return "わんちゃんか猫ちゃんが映った動画を選んでね 🐾"
    case .unreadable:return "写真・動画をもう一度選んでね 🐾"
    }}
}

/// Publication gate. Runs off the main actor; every selected item is checked before upload.
/// Sample spacing is 0.5 s so a continuous one-second appearance contains a sampled frame.
actor PetPostValidator {
    static let shared=PetPostValidator()
    private var verifiedVideos:Set<URL>=[]

    func validatePhoto(_ jpeg:Data) throws {
        guard let image=UIImage(data:jpeg)?.cgImage else {throw PetPostValidationError.unreadable}
        guard containsPet(image,includeTiles:true) else {throw PetPostValidationError.imageNotRecognized}
    }

    func validateVideo(_ url:URL,duration:Double) throws {
        guard duration.isFinite,duration>0 else {throw PetPostValidationError.unreadable}
        if verifiedVideos.contains(url) {return}
        let generator=AVAssetImageGenerator(asset:AVURLAsset(url:url))
        generator.appliesPreferredTrackTransform=true
        generator.maximumSize=CGSize(width:960,height:960)
        generator.requestedTimeToleranceBefore=CMTime(seconds:0.2,preferredTimescale:600)
        generator.requestedTimeToleranceAfter=CMTime(seconds:0.2,preferredTimescale:600)
        // Check whole frames first, then half-second offsets. Tiled checks are a
        // second pass to catch animals occupying only a small part of a frame.
        let whole=Self.sampleTimes(duration:duration)
        var readable=false
        for tiled in [false,true] {
            for second in whole {
                try Task.checkCancellation()
                guard let frame=try? generator.copyCGImage(at:CMTime(seconds:second,preferredTimescale:600),actualTime:nil) else {continue}
                readable=true
                if containsPet(frame,includeTiles:tiled) {verifiedVideos.insert(url);return}
            }
        }
        guard readable else {throw PetPostValidationError.unreadable}
        throw PetPostValidationError.videoNotRecognized
    }

    static func sampleTimes(duration:Double)->[Double] {
        guard duration.isFinite,duration>0 else {return []}
        var times:[Double]=[]
        var second=0.0
        while second<duration {times.append(second);second+=1}
        second=0.5
        while second<duration {times.append(second);second+=1}
        return times
    }

    private func containsPet(_ image:CGImage,includeTiles:Bool)->Bool {
        if recognizesPet(image) {return true}
        guard includeTiles,min(image.width,image.height)>=320 else {return false}
        let width=image.width,height=image.height
        // Overlapping 2x2 regions make a small or edge-positioned pet larger
        // without excluding either the full image or the centre.
        let tileWidth=width*2/3,tileHeight=height*2/3
        let positions=[(0,0),(width-tileWidth,0),(0,height-tileHeight),(width-tileWidth,height-tileHeight)]
        for (x,y) in positions {
            if let crop=image.cropping(to:CGRect(x:x,y:y,width:tileWidth,height:tileHeight)),recognizesPet(crop) {return true}
        }
        return false
    }

    private func recognizesPet(_ image:CGImage)->Bool {
        let request=VNRecognizeAnimalsRequest();request.revision=2
        #if targetEnvironment(simulator)
        request.usesCPUOnly=true
        #endif
        guard (try? VNImageRequestHandler(cgImage:image).perform([request])) != nil else {return false}
        return (request.results ?? []).contains {observation in
            observation.labels.contains {label in
                ["dog","cat"].contains(label.identifier.lowercased()) && label.confidence>=0.25
            }
        }
    }
}

/// Identical preprocessing on desktop indexing and iPhone queries.
/// Pose landmarks are used only when a sufficiently confident head is visible.
/// Otherwise the detected animal region is retained, without inventing a face.
enum PetSubjectCrop {
    struct Result {let image:CGImage;let kind:String;let bounds:CGRect}
    static func detectSpecies(_ image:CGImage) throws->String {
        let request=VNRecognizeAnimalsRequest();request.revision=2
        #if targetEnvironment(simulator)
        request.usesCPUOnly=true
        #endif
        do {try VNImageRequestHandler(cgImage:image).perform([request])}
        catch {throw PetVisualError.processing}
        let labels=(request.results ?? []).flatMap(\.labels)
            .filter{["dog","cat"].contains($0.identifier.lowercased()) && $0.confidence>=0.35}
        guard let best=labels.max(by:{$0.confidence<$1.confidence}) else {throw PetVisualError.species}
        return best.identifier.lowercased()
    }
    static func crop(_ image:CGImage,species:String,single:Bool=true) throws->Result {
        guard ["dog","cat"].contains(species),min(image.width,image.height)>=80 else {throw PetVisualError.photo}
        let request=VNRecognizeAnimalsRequest();request.revision=2
        #if targetEnvironment(simulator)
        request.usesCPUOnly=true
        #endif
        try VNImageRequestHandler(cgImage:image).perform([request])
        let animals=(request.results ?? []).filter{$0.labels.contains{$0.identifier.lowercased()==species && $0.confidence>=0.35}}
        guard !animals.isEmpty else {throw PetVisualError.species}
        if single && animals.count>1 {throw PetVisualError.photo}
        let animal=animals.max{$0.boundingBox.width*$0.boundingBox.height < $1.boundingBox.width*$1.boundingBox.height}!
        let width=CGFloat(image.width),height=CGFloat(image.height)
        let canvas=CGRect(x:0,y:0,width:width,height:height)
        func pixels(_ r:CGRect)->CGRect {CGRect(x:r.minX*width,y:(1-r.maxY)*height,width:r.width*width,height:r.height*height).integral.intersection(canvas)}
        var box=pixels(animal.boundingBox);var kind="animal"
        let pose=VNDetectAnimalBodyPoseRequest();pose.revision=1
        #if targetEnvironment(simulator)
        pose.usesCPUOnly=true
        #endif
        // Some valid close-up portraits have no body pose. This is an expected fallback.
        if (try? VNImageRequestHandler(cgImage:image).perform([pose])) != nil {
            var heads:[CGRect]=[]
            for observation in pose.results ?? [] {
                func point(_ name:VNAnimalBodyPoseObservation.JointName)->CGPoint? {
                    guard let p=try? observation.recognizedPoint(name),p.confidence>=0.35,animal.boundingBox.insetBy(dx:-0.03,dy:-0.03).contains(p.location) else{return nil}
                    return CGPoint(x:p.location.x*width,y:(1-p.location.y)*height)
                }
                guard let nose=point(.nose),let eye=point(.leftEye) ?? point(.rightEye) else{continue}
                let names:[VNAnimalBodyPoseObservation.JointName]=[.leftEye,.rightEye,.nose,.leftEarTop,.rightEarTop,.leftEarMiddle,.rightEarMiddle]
                let points=names.compactMap(point)
                guard points.count>=3 else{continue}
                let minX=points.map(\.x).min()!,maxX=points.map(\.x).max()!,minY=points.map(\.y).min()!,maxY=points.map(\.y).max()!
                let eyeNose=hypot(nose.x-eye.x,nose.y-eye.y)
                let side=max(maxX-minX,maxY-minY,eyeNose*2.5)*1.35
                let candidate=CGRect(x:(minX+maxX-side)/2,y:(minY+maxY-side)/2,width:side,height:side).integral.intersection(canvas)
                guard min(candidate.width,candidate.height)>=48,candidate.width*candidate.height>=box.width*box.height*0.025 else{continue}
                heads.append(candidate)
            }
            if single && heads.count>1 {throw PetVisualError.photo}
            if let head=heads.max(by:{$0.width*$0.height < $1.width*$1.height}) {box=head;kind="head"}
        }
        guard min(box.width,box.height)>=32,let cropped=image.cropping(to:box) else {throw PetVisualError.photo}
        return Result(image:cropped,kind:kind,bounds:box)
    }
    /// Root histogram of coarse RGB bins. Explicit low weight prevents color dominating shape.
    static func color(_ image:CGImage)->[Float] {
        var bytes=[UInt8](repeating:0,count:32*32*4)
        let ok=bytes.withUnsafeMutableBytes {buffer->Bool in
            guard let context=CGContext(data:buffer.baseAddress,width:32,height:32,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return false}
            context.interpolationQuality = .high;context.draw(image,in:CGRect(x:0,y:0,width:32,height:32));return true
        }
        guard ok else{return []}
        var histogram=[Float](repeating:0,count:64)
        // Central region reduces background without assuming a segmentation mask.
        for y in 4..<28 {for x in 4..<28 {let i=(y*32+x)*4;let bin=Int(bytes[i])/64*16+Int(bytes[i+1])/64*4+Int(bytes[i+2])/64;histogram[bin]+=1}}
        return histogram.map{sqrt($0/576)}
    }
}

actor PetSpeciesDetection {
    static let shared=PetSpeciesDetection()
    func detect(_ image:CGImage) throws->String {try PetSubjectCrop.detectSpecies(image)}
}
