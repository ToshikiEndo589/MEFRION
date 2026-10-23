import Foundation
import ImageIO
import UniformTypeIdentifiers
@main struct BuildCrops {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
  try FileManager.default.createDirectory(at:out.appendingPathComponent("crops"),withIntermediateDirectories:true)
  let catalog=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("catalog.json"))) as! [String:Any]
  let rows=catalog["assets"] as! [[String:Any]]
  let limit=CommandLine.arguments.count>3 ? Int(CommandLine.arguments[3])! : rows.count
  let lock=NSLock(),queue=OperationQueue();queue.maxConcurrentOperationCount=2
  var completed=0,heads=0,failed=0
  for row in rows.prefix(limit) {queue.addOperation {autoreleasepool {
   let id=row["id"] as! String,record=out.appendingPathComponent("crops/"+id+".json")
   if FileManager.default.fileExists(atPath:record.path) {lock.lock();completed+=1;lock.unlock();return}
   do {
    guard let source=CGImageSourceCreateWithURL(root.appendingPathComponent("images/"+(row["file"] as! String)) as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else{throw PetVisualError.photo}
    let result=try PetSubjectCrop.crop(image,species:row["species"] as! String,single:false)
    let target=out.appendingPathComponent("crops/"+id+".png")
    guard let dest=CGImageDestinationCreateWithURL(target as CFURL,UTType.png.identifier as CFString,1,nil) else{throw PetVisualError.photo}
    CGImageDestinationAddImage(dest,result.image,nil);guard CGImageDestinationFinalize(dest) else{throw PetVisualError.photo}
    let payload:[String:Any]=["id":id,"kind":result.kind,"bounds":[result.bounds.minX,result.bounds.minY,result.bounds.width,result.bounds.height],"color":PetSubjectCrop.color(result.image)]
    try JSONSerialization.data(withJSONObject:payload).write(to:record,options:.atomic)
    lock.lock();if result.kind=="head" {heads+=1};lock.unlock()
   } catch {lock.lock();failed+=1;lock.unlock()}
   lock.lock();completed+=1;if completed%100==0 {print("processed \(completed)/\(limit), heads \(heads), failed \(failed)");fflush(stdout)};lock.unlock()
  }}}
  queue.waitUntilAllOperationsAreFinished();print("complete \(completed), heads \(heads), failed \(failed)")
 }
}
