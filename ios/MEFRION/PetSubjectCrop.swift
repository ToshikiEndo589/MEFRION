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
    struct Subject {
        let species:String
        let confidence:Float
        /// Vision coordinates: normalized, bottom-left origin, relative to the unpadded input.
        let boundingBox:CGRect
    }
    static func detectSpecies(_ image:CGImage) throws->String {
        guard let best=try locate(image).max(by:{$0.confidence<$1.confidence}) else {throw PetVisualError.species}
        return best.species
    }
    /// Keep the original detection unchanged when it works. Only difficult close-ups
    /// pay for a second scale or image classification; no species is assumed from user input.
    static func locate(_ image:CGImage,species:String?=nil) throws->[Subject] {
        guard min(image.width,image.height)>=80 else {throw PetVisualError.photo}
        if let species,!["dog","cat"].contains(species) {throw PetVisualError.species}
        func accepted(_ values:[Subject])->[Subject] {values.filter{species==nil || $0.species==species}}
        let original=try detectObjects(image)
        let matches=accepted(original)
        if !matches.isEmpty {return matches}
        // Do not relabel an already recognized dog as a cat (or vice versa).
        if !original.isEmpty {throw PetVisualError.species}
        var views:[CGImage]=[image]
        for padding in [0.2,0.45] {
            try Task.checkCancellation()
            guard let padded=paddedView(image,padding:padding) else {continue}
            views.append(padded.image)
            let mapped=try detectObjects(padded.image).compactMap {subject->Subject? in
                let box=CGRect(x:(subject.boundingBox.minX*CGFloat(padded.image.width)-padded.content.minX)/padded.content.width,
                               y:(subject.boundingBox.minY*CGFloat(padded.image.height)-padded.content.minY)/padded.content.height,
                               width:subject.boundingBox.width*CGFloat(padded.image.width)/padded.content.width,
                               height:subject.boundingBox.height*CGFloat(padded.image.height)/padded.content.height)
                    .intersection(CGRect(x:0,y:0,width:1,height:1))
                guard !box.isNull,box.width*CGFloat(image.width)>=32,box.height*CGFloat(image.height)>=32 else{return nil}
                return Subject(species:subject.species,confidence:subject.confidence,boundingBox:box)
            }
            let matches=accepted(mapped)
            if !matches.isEmpty {return matches}
            if !mapped.isEmpty {throw PetVisualError.species}
        }
        // Object localization can fail when ears/body extend beyond the photo.
        // Classification can still recognize the portrait; retain the whole input then.
        for view in views {
            try Task.checkCancellation()
            let request=VNClassifyImageRequest();request.revision=1
            configure(request)
            do {try VNImageRequestHandler(cgImage:view).perform([request])}
            catch {throw PetVisualError.processing}
            let scores=Dictionary((request.results ?? []).map{($0.identifier.lowercased(),$0.confidence)},uniquingKeysWith:max)
            if let detected=classificationSpecies(scores),species==nil || detected==species {
                return [Subject(species:detected,confidence:scores[detected] ?? 0,boundingBox:CGRect(x:0,y:0,width:1,height:1))]
            }
        }
        throw PetVisualError.species
    }
    static func classificationSpecies(_ scores:[String:Float])->String? {
        // Exact identifiers exclude "hotdog", "prairie_dog" and "caterpillar".
        let dog=scores["dog"] ?? 0,cat=scores["cat"] ?? 0
        let best=max(dog,cat),other=min(dog,cat),overall=scores.values.max() ?? 0
        guard best>=0.55,best-other>=0.2,best>=overall*0.75 else{return nil}
        return dog>cat ? "dog" : "cat"
    }
    private static func configure(_ request:VNRequest) {
        #if targetEnvironment(simulator) || os(macOS)
        request.usesCPUOnly=true
        #endif
    }
    private static func detectObjects(_ image:CGImage) throws->[Subject] {
        let request=VNRecognizeAnimalsRequest();request.revision=2;configure(request)
        do {try VNImageRequestHandler(cgImage:image).perform([request])}
        catch {throw PetVisualError.processing}
        return (request.results ?? []).compactMap {observation in
            guard let label=observation.labels.filter({["dog","cat"].contains($0.identifier.lowercased()) && $0.confidence>=0.35})
                .max(by:{$0.confidence<$1.confidence}) else{return nil}
            return Subject(species:label.identifier.lowercased(),confidence:label.confidence,boundingBox:observation.boundingBox)
        }
    }
    private static func paddedView(_ image:CGImage,padding:Double)->(image:CGImage,content:CGRect)? {
        let scale=min(1,1024/Double(max(image.width,image.height)))
        let width=max(1,Int(Double(image.width)*scale)),height=max(1,Int(Double(image.height)*scale))
        let x=Int(Double(width)*padding),y=Int(Double(height)*padding)
        guard let context=CGContext(data:nil,width:width+2*x,height:height+2*y,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
        context.setFillColor(gray:0.5,alpha:1)
        context.fill(CGRect(x:0,y:0,width:context.width,height:context.height))
        let content=CGRect(x:x,y:y,width:width,height:height)
        context.interpolationQuality = .high;context.draw(image,in:content)
        guard let padded=context.makeImage() else{return nil}
        return (padded,content)
    }
    static func crop(_ image:CGImage,species:String,single:Bool=true,subjects:[Subject]?=nil) throws->Result {
        guard ["dog","cat"].contains(species),min(image.width,image.height)>=80 else {throw PetVisualError.photo}
        let animals=try (subjects ?? locate(image,species:species)).filter{$0.species==species}
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
