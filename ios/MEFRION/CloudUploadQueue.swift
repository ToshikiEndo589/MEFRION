import Foundation
import Combine
import CryptoKit

struct CloudUploadDraft:Identifiable,Codable {
    enum State:String,Codable {case pending,uploading,complete,failed}
    let id:UUID
    let pet:String
    let captured:String?
    var jpeg:Data
    var state:State = .pending
    var message:String?
    var duplicateApproved=false
    var fingerprint:String {SHA256.hash(data:jpeg).map{String(format:"%02x",$0)}.joined()}
    init(pet:String,jpeg:Data,captured:String?,id:UUID=UUID()) {self.id=id;self.pet=pet;self.jpeg=jpeg;self.captured=captured}
}

@MainActor
final class CloudUploadQueue:ObservableObject {
    private struct Snapshot:Codable {let version:Int;let actor:String;let drafts:[CloudUploadDraft]}
    @Published private(set) var drafts:[CloudUploadDraft]=[]
    @Published private(set) var persistenceError:String?
    @Published private(set) var isSending=false
    @Published private(set) var paused=false
    private var running=false
    private var generation=UUID()
    private var actor:String?
    private let folder:URL?
    init(folder:URL?=nil) {self.folder=folder}
    static var deviceFolder:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("MEFRION/upload-queue",isDirectory:true)}
    private var file:URL? {guard let actor,let folder else{return nil};return folder.appendingPathComponent(actor+".json")}
    enum Validation:LocalizedError {
        case limit,date,size,storage,identity,duplicate
        var errorDescription:String? {switch self {
        case .limit:return "一度に選べる写真は30枚までです。未送信の写真を先に再試行してください。"
        case .date:return "撮影日を確認してください。"
        case .size:return "写真は1枚20MBまで、一度の追加は合計100MBまでです。"
        case .storage:return "再送用の写真を端末に保存できません。容量と保存データを確認してください。"
        case .identity:return "再送するアカウントを確認してください。"
        case .duplicate:return "同じ写真が未送信の一覧にあります。"}}
    }
    func activate(actor:String) throws {
        guard UUID(uuidString:actor) != nil else {throw Validation.identity}
        if self.actor==actor {return}
        generation=UUID();drafts=[];self.actor=actor;persistenceError=nil
        guard let file,FileManager.default.fileExists(atPath:file.path) else{return}
        do {
            let snapshot=try JSONDecoder().decode(Snapshot.self,from:Data(contentsOf:file))
            guard snapshot.version==1,snapshot.actor==actor,snapshot.drafts.count<=30 else {throw Validation.storage}
            drafts=snapshot.drafts.filter{$0.state != .complete}.map {var d=$0;if d.state == .uploading {d.state = .failed;d.message="送信途中で終了しました。同じ写真を再試行できます。"};return d}
            guard drafts.allSatisfy({!$0.jpeg.isEmpty && $0.jpeg.count<=20*1024*1024 && PrototypeStore.dateIsValid($0.captured ?? "")}),drafts.reduce(0,{$0+$1.jpeg.count})<=100*1024*1024 else {throw Validation.storage}
        } catch {drafts=[];persistenceError=Validation.storage.localizedDescription;throw Validation.storage}
    }
    private func persist() throws {
        guard persistenceError==nil else {throw Validation.storage}
        guard let folder,let file,let actor else {return}
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
            var dir=folder;var values=URLResourceValues();values.isExcludedFromBackup=true;try dir.setResourceValues(values)
            let bytes=try JSONEncoder().encode(Snapshot(version:1,actor:actor,drafts:drafts.filter{$0.state != .complete}))
            try bytes.write(to:file,options:[.atomic,.completeFileProtection])
        } catch {throw Validation.storage}
    }
    func append(_ items:[CloudUploadDraft]) throws {
        guard !running,items.count+drafts.filter({$0.state != .complete}).count<=30 else {throw Validation.limit}
        guard items.allSatisfy({PrototypeStore.dateIsValid($0.captured ?? "")}) else {throw Validation.date}
        let pending=drafts.filter{$0.state != .complete}
        guard items.allSatisfy({!$0.jpeg.isEmpty && $0.jpeg.count<=20*1024*1024}),(pending+items).reduce(0,{$0+$1.jpeg.count})<=100*1024*1024 else {throw Validation.size}
        let stamps=(pending+items).map{$0.pet+":"+$0.fingerprint}
        guard Set(stamps).count==stamps.count else {throw Validation.duplicate}
        let old=drafts;drafts=pending+items
        do {try persist()} catch {drafts=old;throw error}
    }
    func pendingMatch(for draft:CloudUploadDraft)->CloudUploadDraft? {
        drafts.first {$0.id==draft.id || ($0.state != .complete && $0.pet==draft.pet && $0.fingerprint==draft.fingerprint)}
    }
    func allowPublicationRetry(ids:Set<UUID>) throws {
        let before=drafts
        for index in drafts.indices where ids.contains(drafts[index].id) && drafts[index].state != .complete {
            drafts[index].duplicateApproved=true
        }
        do {try persist()} catch {drafts=before;throw error}
    }
    func send(pet:String,upload:(CloudUploadDraft) async throws->Void) async {
        guard !running,persistenceError==nil else{return};running=true;isSending=true;paused=false
        let stamp=generation;defer {running=false;isSending=false}
        for index in drafts.indices {
            guard generation==stamp,!paused else{return}
            guard drafts[index].pet==pet,drafts[index].state != .complete else{continue}
            let original=drafts[index];drafts[index].state = .uploading;drafts[index].message=nil
            do {
                try persist() // Commit the original UUID/bytes before any network mutation.
                try await upload(drafts[index])
                guard generation==stamp else{return}
                drafts[index].state = .complete;drafts[index].jpeg=Data();try persist()
            } catch {
                guard generation==stamp else{return}
                drafts[index]=original;drafts[index].state = .failed;drafts[index].message=error.localizedDescription
                do {try persist()} catch {persistenceError=Validation.storage.localizedDescription;return}
            }
        }
    }
    func pause() {if isSending {paused=true}}
    func approveDuplicates(pet:String) throws {
        let before=drafts
        for index in drafts.indices where drafts[index].pet==pet && drafts[index].state == .failed {drafts[index].duplicateApproved=true}
        do {try persist()} catch {drafts=before;throw error}
    }
    func clear() {
        generation=UUID();drafts=[];paused=false
        if let file {do {if FileManager.default.fileExists(atPath:file.path) {try FileManager.default.removeItem(at:file)}} catch {persistenceError=Validation.storage.localizedDescription;return}}
        actor=nil;persistenceError=nil
    }
}
