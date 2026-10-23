import Foundation
import ImageIO
import CoreML
@main struct BuildNative {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
  let compiled=try MLModel.compileModel(at:out.appendingPathComponent("PetResemblance.mlpackage"))
  let model=try PetResemblance(url:compiled)
  let catalog=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("catalog.json"))) as! [String:Any]
  let rows=catalog["assets"] as! [[String:Any]]
  var accepted:[[String:Any]]=[],vectors=Data();let start=Date()
  for (i,row) in rows.enumerated() {try autoreleasepool {
   let id=row["id"] as! String
   guard let data=try? Data(contentsOf:out.appendingPathComponent("crops/"+id+".json")),let meta=try JSONSerialization.jsonObject(with:data) as? [String:Any],let source=CGImageSourceCreateWithURL(out.appendingPathComponent("crops/"+id+".png") as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {return}
   let values=try model.features(image)
   var updated=row;updated["kind"]=meta["kind"];updated["color"]=meta["color"];accepted.append(updated)
   values.withUnsafeBytes{vectors.append(contentsOf:$0)}
   if i%320==0 {print("native \(i+1)/\(rows.count), seconds \(Int(Date().timeIntervalSince(start)))");fflush(stdout)}
  }}
  try vectors.write(to:out.appendingPathComponent("native-vectors.bin"),options:.atomic)
  try JSONSerialization.data(withJSONObject:["algorithm":PetResemblance.algorithm,"elements":384,"assets":accepted]).write(to:out.appendingPathComponent("native-catalog.json"),options:.atomic)
  print("COMPLETE \(accepted.count), seconds \(Int(Date().timeIntervalSince(start)))")
 }
}
