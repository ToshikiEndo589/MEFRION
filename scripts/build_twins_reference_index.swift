import Foundation
import ImageIO

@main struct BuildReferenceIndex {
    static func main() throws {
        let input=URL(fileURLWithPath:CommandLine.arguments[1])
        let output=URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:output.appendingPathComponent("images"),withIntermediateDirectories:true)
        let lines=try String(contentsOf:input.appendingPathComponent("manifest.jsonl"),encoding:.utf8).split(separator:"\n")
        var metadata:[[String:Any]]=[];var vectors=Data();var rejected:[[String:Any]]=[]
        var accepted:[Int:([String:Any],[Float])]=[:];var completed=0
        let lock=NSLock();let queue=OperationQueue();queue.maxConcurrentOperationCount=4
        var reuse:[String:[Float]]=[:]
        if let bytes=try? Data(contentsOf:output.appendingPathComponent("catalog.json")),let previous=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],let rows=previous["assets"] as? [[String:Any]],previous["revision"] as? Int==2,let raw=try? Data(contentsOf:output.appendingPathComponent("vectors.bin")),raw.count==rows.count*768*4 {
            let floats=raw.withUnsafeBytes{Array($0.bindMemory(to:Float.self))}
            for (index,row) in rows.enumerated() {if let id=row["id"] as? String {reuse[id]=Array(floats[index*768..<(index+1)*768])}}
        }
        let reused=reuse
        for (i,line) in lines.enumerated() {
            queue.addOperation {autoreleasepool {
                let row=try! JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any]
                let id=row["asset_id"] as! String,species=row["species_hint"] as! String
                do {
                    let file=input.appendingPathComponent(row["thumbnail_path"] as! String)
                    guard let source=CGImageSourceCreateWithURL(file as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {throw PetVisualError.photo}
                    let feature=try reused[id] ?? PetVisualFeature.extract(image,species:species,requireSingleSubject:false)
                    guard let fingerprint=PetVisualFeature.fingerprint(image) else {throw PetVisualError.photo}
                    let name=id+".jpg"
                    let destination=output.appendingPathComponent("images/"+name)
                    if FileManager.default.fileExists(atPath:destination.path) {try FileManager.default.removeItem(at:destination)}
                    try FileManager.default.copyItem(at:file,to:destination)
                    lock.lock();accepted[i]=(["id":id,"species":species,"file":name,"credit":row["credit"]!,"source":row["source_page"]!,"demoOnly":true,"fingerprint":fingerprint.edges.map{$0 ? "1":"0"}.joined(),"mean":fingerprint.mean],feature);lock.unlock()
                } catch {lock.lock();rejected.append(["id":id,"state":"animal_or_feature_not_confirmed"]);lock.unlock()}
                lock.lock();completed+=1;if completed%100==0 {print("processed \(completed), accepted \(accepted.count)");fflush(stdout)};lock.unlock()
            }}
        }
        queue.waitUntilAllOperationsAreFinished()
        for i in accepted.keys.sorted() {let pair=accepted[i]!;metadata.append(pair.0);pair.1.withUnsafeBytes{vectors.append(contentsOf:$0)}}
        let files=Set(metadata.map{$0["file"] as! String})
        for file in try FileManager.default.contentsOfDirectory(at:output.appendingPathComponent("images"),includingPropertiesForKeys:nil) where !files.contains(file.lastPathComponent) {try FileManager.default.removeItem(at:file)}
        let catalog:[String:Any]=["version":1,"revision":2,"elements":768,"assets":metadata]
        try JSONSerialization.data(withJSONObject:catalog,options:[.sortedKeys]).write(to:output.appendingPathComponent("catalog.json"),options:.atomic)
        try vectors.write(to:output.appendingPathComponent("vectors.bin"),options:.atomic)
        let permission=try Data(contentsOf:input.appendingPathComponent("permission.json"));try permission.write(to:output.appendingPathComponent("permission.json"),options:.atomic)
        let report:[String:Any]=["input":lines.count,"indexed":metadata.count,"rejected":rejected,"vectorBytes":vectors.count,"revision":2,"elements":768]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("build-report.json"))
        print("Indexed \(metadata.count), rejected \(rejected.count)")
    }
}
