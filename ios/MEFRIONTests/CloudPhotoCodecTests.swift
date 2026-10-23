import XCTest
import UIKit
import ImageIO
@testable import MEFRION

final class CloudPhotoCodecTests:XCTestCase {
    func source(width:Int=4,height:Int=2,metadata:[CFString:Any]=[:]) throws->Data {
        let renderer=UIGraphicsImageRenderer(size:CGSize(width:width,height:height),format:{let f=UIGraphicsImageRendererFormat();f.scale=1;return f}())
        let image=renderer.image {ctx in UIColor.red.setFill();ctx.fill(CGRect(x:0,y:0,width:width/2,height:height));UIColor.blue.setFill();ctx.fill(CGRect(x:width/2,y:0,width:width-width/2,height:height))}
        let data=NSMutableData();let destination=try XCTUnwrap(CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil));CGImageDestinationAddImage(destination,try XCTUnwrap(image.cgImage),metadata as CFDictionary);XCTAssertTrue(CGImageDestinationFinalize(destination));return data as Data
    }
    func testOrientationIsBakedWithoutGPSOrEXIF() throws {
        let original=try source(metadata:[kCGImagePropertyOrientation:6,kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:35.0,kCGImagePropertyGPSLatitudeRef:"N"],kCGImagePropertyExifDictionary:[kCGImagePropertyExifDateTimeOriginal:"2020:01:02 03:04:05"]])
        let result=try CloudPhotoCodec.encode(original);let decoded=try XCTUnwrap(UIImage(data:result)?.cgImage);XCTAssertEqual(decoded.width,2);XCTAssertEqual(decoded.height,4)
        let source=try XCTUnwrap(CGImageSourceCreateWithData(result as CFData,nil));let properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any]);XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        // JPEG encoders can synthesize technical ColorSpace/PixelDimension
        // fields. The source's identifying metadata must not be copied.
        let exif=properties[kCGImagePropertyExifDictionary] as? [CFString:Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal])
        let tiff=properties[kCGImagePropertyTIFFDictionary] as? [CFString:Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFMake]);XCTAssertNil(tiff?[kCGImagePropertyTIFFModel]);XCTAssertNil(tiff?[kCGImagePropertyTIFFDateTime])
    }
    func testLargeSupportedPhotoIsBoundedAndRetryDeterministic() throws {
        let original=try source(width:4096,height:512);let first=try CloudPhotoCodec.encode(original);let second=try CloudPhotoCodec.encode(original)
        XCTAssertEqual(first,second);let image=try XCTUnwrap(UIImage(data:first)?.cgImage);XCTAssertLessThanOrEqual(max(image.width,image.height),4000)
    }
    func testThirtyTwelveMegapixelPhotosPerformance() throws {
        let original=try source(width:4000,height:3000,metadata:[kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:35.0]])
        let options=XCTMeasureOptions();options.iterationCount=3
        measure(metrics:[XCTClockMetric(),XCTMemoryMetric()],options:options) {
            for _ in 0..<30 {
                do {let encoded=try CloudPhotoCodec.encode(original);XCTAssertFalse(encoded.isEmpty)}
                catch {XCTFail("Owned image processing failed: \(error)")}
            }
        }
    }
    func testCorruptAndOversizedInputNeverDecodes() {
        XCTAssertThrowsError(try CloudPhotoCodec.encode(Data("not an image".utf8)))
        XCTAssertThrowsError(try CloudPhotoCodec.encode(Data(count:PrototypePolicy.imageBytes+1)))
    }
    func testGIFAndTIFFImportAsStillJPEG() throws {
        let image=UIGraphicsImageRenderer(size:CGSize(width:120,height:80)).image {context in
            UIColor.systemPink.setFill();context.fill(CGRect(x:0,y:0,width:120,height:80))
        }
        for type in ["com.compuserve.gif","public.tiff"] {
            let source=NSMutableData()
            let destination=try XCTUnwrap(CGImageDestinationCreateWithData(source,type as CFString,1,nil),"Encoder unavailable for \(type)")
            CGImageDestinationAddImage(destination,try XCTUnwrap(image.cgImage),nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let encoded=try CloudPhotoCodec.encode(source as Data)
            let decoded=try XCTUnwrap(CGImageSourceCreateWithData(encoded as CFData,nil))
            XCTAssertEqual(CGImageSourceGetType(decoded) as String?,"public.jpeg")
            XCTAssertEqual(try XCTUnwrap(UIImage(data:encoded)?.cgImage).width,image.cgImage?.width)
        }
    }
    func testLargeSourceCanBeNormalizedUnderUploadLimit() throws {
        let original=try source(width:200,height:100)
        let padded=original+Data(repeating:0,count:PrototypePolicy.imageBytes)
        XCTAssertGreaterThan(padded.count,PrototypePolicy.imageBytes)
        let normalized=try CloudPhotoCodec.encode(padded)
        XCTAssertLessThan(normalized.count,PrototypePolicy.imageBytes)
    }
}
