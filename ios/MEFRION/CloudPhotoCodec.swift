import UIKit
import ImageIO
import UniformTypeIdentifiers

// Accept the raster formats ImageIO can decode on this OS, then normalize the
// first frame to a bounded JPEG without copying EXIF/GPS metadata.
enum CloudPhotoCodec {
    private static let sourceBytes=100*1024*1024
    enum Failure:LocalizedError {case sourceBytes,bytes,format,pixels,decode
        var errorDescription:String? {switch self {
        case .sourceBytes:return "元の写真が大きすぎます。100MB以内の写真を選んでください。"
        case .bytes:return "写真を投稿用の20MB以内に変換できませんでした。"
        case .format:return "この画像形式をiPhoneで読み込めませんでした。別の画像を選んでください。"
        case .pixels:return "写真の画素数が大きすぎます。5000万画素以内の写真を選んでください。"
        case .decode:return "写真を読み込めませんでした。別の写真を選んでください。"
        }}
    }
    static func preview(_ data:Data,maxPixelSize:Int=180)->UIImage? {
        guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceThumbnailMaxPixelSize:maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform:true
              ] as CFDictionary) else {return nil}
        return UIImage(cgImage:image)
    }
    static func encode(_ data:Data) throws->Data {
        // Bound Objective-C encoder temporaries even when 30 photos are imported
        // from one asynchronous task without a caller-provided autorelease pool.
        return try autoreleasepool {
        guard data.count<=sourceBytes else {throw Failure.sourceBytes}
        guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let type=CGImageSourceGetType(source) as String?,
              let imageType=UTType(type),imageType.conforms(to:.image),
              CGImageSourceGetCount(source)>0 else {throw Failure.format}
        guard let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],let width=props[kCGImagePropertyPixelWidth] as? NSNumber,let height=props[kCGImagePropertyPixelHeight] as? NSNumber,width.int64Value>0,height.int64Value>0,width.int64Value<=50_000_000/height.int64Value else {throw Failure.pixels}
        guard let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:4000,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary),let jpeg=UIImage(cgImage:image).jpegData(compressionQuality:0.9) else {throw Failure.decode}
        guard jpeg.count<=PrototypePolicy.imageBytes else {throw Failure.bytes};return jpeg
        }
    }
}
