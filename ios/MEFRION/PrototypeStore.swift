import SwiftUI
import PhotosUI
import ImageIO
import CryptoKit

enum Species: String, CaseIterable, Identifiable, Codable {
    case dog, cat
    var id: String { rawValue }
    var title: String { self == .dog ? "犬" : "猫" }
}

struct PetRecord: Identifiable, Codable {
    let id: UUID
    var name: String
    var species: Species
    var breed = ""
    var introduction = ""
    var isPublic = false
    var sex:String?=nil
    var birthday:String?=nil
    var coverPhotoID:UUID?=nil
    var iconPhotoID:UUID?=nil
}

struct TwinsHistoryRecord:Identifiable,Codable {
    let id:UUID
    let created:Date
    let species:Species
    let state:String
    let mode:String
    let candidateIDs:[Int]
}

struct PhotoRecord: Identifiable {
    let id: UUID
    let petID: UUID
    let image: UIImage
    let fingerprint: String
    var captured: String?
    var title: String
    var eventKind:String?=nil
    var note:String?=nil
    // Every local prototype photo is private. No public export API is provided.
}

struct PhotoDraft: Identifiable {
    let id: UUID
    let image: UIImage
    let fingerprint: String
    var captured: String
    var title = ""
    var error: String?
    var saved = false
}

struct MemoryRecord: Identifiable, Codable {
    let id: UUID
    let petID: UUID
    let photos: [UUID]
    let text: String
    let zooms: [Double]
    let offsets: [Double]
}

struct PrototypeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class PrototypeStore: ObservableObject {
    let storageURL: URL?
    @Published var storageError: String?
    @Published var operationError: String?
    @Published var pets: [PetRecord] = []
    @Published var photos: [PhotoRecord] = []
    @Published var cards: [MemoryRecord] = []
    @Published var drafts: [PhotoDraft] = []
    @Published var selectedPet: UUID?
    @Published var failedImports = 0
    @Published var searches = 0
    @Published var failures = 0
    @Published var twinsHistory:[TwinsHistoryRecord]=[]
    @Published var referenceTwinsHistory:[ReferenceSearchRecord]=[]
    @Published var feedback: [String] = []

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL
        do { try restorePrivateState() }
        catch { storageError = "保存済みデータを読み込めません。既存ファイルは保持しています。" }
    }

    func createPet(name: String, species: Species, breed: String = "", introduction: String = "",sex:String?=nil,birthday:String?=nil) throws {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= PrototypePolicy.petNameCharacters else { throw PrototypeError(message: "名前は1〜40文字で入力してください。") }
        guard pets.count < PrototypePolicy.pets else { throw PrototypeError(message: "試作ではPetは5匹までです。既存記録は保持します。") }
        guard breed.count<=100,introduction.count<=500,birthday==nil || Self.dateIsValid(birthday ?? ""),sex==nil || ["male","female"].contains(sex ?? "") else {throw PrototypeError(message:"基本情報を確認してください。")}
        let pet = PetRecord(id: UUID(), name: value, species: species, breed: breed, introduction: introduction,sex:sex,birthday:birthday)
        try persistMutation { pets.append(pet); selectedPet = pet.id }
    }

    func updatePet(id:UUID,name:String,breed:String,introduction:String,sex:String?=nil,birthday:String?=nil,pictures:(UUID?,UUID?)?=nil) throws {
        let value=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty,value.count<=PrototypePolicy.petNameCharacters,breed.count<=100,introduction.count<=500,
              birthday==nil || Self.dateIsValid(birthday ?? ""),sex==nil || ["male","female"].contains(sex ?? ""),
              let index=pets.firstIndex(where:{$0.id==id}) else {throw PrototypeError(message:"名前・紹介文を確認してください。")}
        if let pictures {for selected in [pictures.0,pictures.1].compactMap({$0}) {guard photos.contains(where:{$0.id==selected && $0.petID==id}) else {throw PrototypeError(message:"このPetのアルバム写真を選んでください。")}}}
        try persistMutation {pets[index].name=value;pets[index].breed=breed;pets[index].introduction=introduction;pets[index].sex=sex;pets[index].birthday=birthday;if let pictures {pets[index].coverPhotoID=pictures.0;pets[index].iconPhotoID=pictures.1}}
    }

    func recordTwinsSearch(species:Species,state:String,mode:String,candidates:[Int],now:Date=Date()) throws {
        guard ["results","insufficient","poor_photo","failure"].contains(state),["local","fixture"].contains(mode),candidates.count<=3,Set(candidates).count==candidates.count,candidates.allSatisfy({(0..<10).contains($0) && ($0 % 2==0)==(species == .dog)}),state=="results" || candidates.isEmpty else {throw PrototypeError(message:"検索履歴の内容を確認してください。")}
        try persistMutation {
            twinsHistory=Self.recentTwinsHistory(twinsHistory,now:now)
            twinsHistory.insert(TwinsHistoryRecord(id:UUID(),created:now,species:species,state:state,mode:mode,candidateIDs:candidates),at:0)
            twinsHistory=Array(twinsHistory.prefix(20))
        }
    }
    static func recentTwinsHistory(_ records:[TwinsHistoryRecord],now:Date=Date())->[TwinsHistoryRecord] {
        Array(records.filter{let age=now.timeIntervalSince($0.created);return age>=0 && age<24*60*60}.prefix(20))
    }
    func clearTwinsHistory() throws {try persistMutation {twinsHistory=[];referenceTwinsHistory=[]}}

    static func dateIsValid(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }) else { return false }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count <= 3, parts[0].count == 4,
              let year = Int(parts[0]), (1...9999).contains(year) else { return false }
        if parts.count == 1 { return true }
        guard parts[1].count == 2, let month = Int(parts[1]), (1...12).contains(month) else { return false }
        if parts.count == 2 { return true }
        guard parts[2].count == 2, let day = Int(parts[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else { return false }
        return range.contains(day)
    }

    static func capturedDate(from data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = info[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return "" }
        let candidate = String(raw.prefix(10)).replacingOccurrences(of: ":", with: "-")
        return dateIsValid(candidate) ? candidate : ""
    }

    func importPhotos(_ items: [PhotosPickerItem]) async {
        // A selected subset is loaded; no library-wide permission or external upload.
        for item in items.prefix(PrototypePolicy.albumBatch) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), data.count <= PrototypePolicy.imageBytes,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0,
                        [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceThumbnailMaxPixelSize: PrototypePolicy.thumbnailPixels,
                         kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else {
                    throw PrototypeError(message: "20MB以内の読み取れる画像を選んでください。")
                }
                let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                drafts.append(PhotoDraft(id: UUID(), image: UIImage(cgImage: thumb), fingerprint: fingerprint,
                                         captured: Self.capturedDate(from: data)))
            } catch { failedImports += 1 }
        }
    }

    func addDemoDrafts() {
        for i in 0..<2 {
            if let image = UIImage(named: "pet-\(i)") {
                drafts.append(PhotoDraft(id: UUID(), image: image, fingerprint: "demo-\(i)",
                                         captured: i == 0 ? "2020" : "2026-10", title: "テストイラスト"))
            }
        }
    }

    func saveDrafts(allowDuplicates: Bool) throws {
        guard let petID = selectedPet, pets.contains(where: { $0.id == petID }) else {
            throw PrototypeError(message: "写真を保持しています。先にPetを作成してください。")
        }
        guard drafts.filter({ !$0.saved }).count <= PrototypePolicy.albumBatch else { throw PrototypeError(message: "1回30枚までです。選択を減らしてください。") }
        try persistMutation {
        for i in drafts.indices where !drafts[i].saved {
            drafts[i].error = nil
            guard Self.dateIsValid(drafts[i].captured) else {
                drafts[i].error = "日付を確認してください。未入力は日付不明です。"; continue
            }
            if photos.contains(where: { $0.petID == petID && $0.fingerprint == drafts[i].fingerprint }) && !allowDuplicates {
                drafts[i].error = "同じ画像の候補です。追加する場合は重複確認をオンにしてください。"; continue
            }
            let draft = drafts[i]
            photos.append(PhotoRecord(id: draft.id, petID: petID, image: draft.image,
                                      fingerprint: draft.fingerprint,
                                      captured: draft.captured.isEmpty ? nil : draft.captured, title: draft.title))
            drafts[i].saved = true
        }
        }
    }

    func album(_ petID: UUID) -> [PhotoRecord] {
        photos.filter { $0.petID == petID }.sorted {
            if $0.captured == nil { return false }
            if $1.captured == nil { return true }
            if $0.captured == $1.captured { return $0.id.uuidString < $1.id.uuidString }
            return $0.captured! < $1.captured!
        }
    }

    func memories(_ petID: UUID, today: Date = Date()) -> [PhotoRecord] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: today) else { return [] }
        let target = formatter.string(from: lastYear)
        return album(petID).filter { $0.captured?.count == 10 && $0.captured == target }
    }

    func updatePhoto(_ id: UUID, title: String, captured: String,eventKind:String?=nil,note:String?=nil) throws {
        guard eventKind==nil || ["","birthday","anniversary","arrival","hospital","other"].contains(eventKind ?? ""),(note?.count ?? 0)<=200 else {throw PrototypeError(message:"記念日の種類・メモを確認してください。")}
        guard Self.dateIsValid(captured) else { throw PrototypeError(message: "日付形式を確認してください。") }
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        try persistMutation { photos[i].title = title; photos[i].captured = captured.isEmpty ? nil : captured;if let eventKind {photos[i].eventKind=eventKind.isEmpty ? nil : eventKind};if let note {photos[i].note=note.isEmpty ? nil : note} }
    }

    @discardableResult
    func deletePhoto(_ id: UUID) -> Bool {
        do { try persistMutation {
            photos.removeAll { $0.id == id }
            for index in pets.indices {if pets[index].coverPhotoID==id {pets[index].coverPhotoID=nil};if pets[index].iconPhotoID==id {pets[index].iconPhotoID=nil}}
            cards.removeAll { $0.photos.contains(id) }
        }; operationError=nil; return true } catch { operationError = "削除を保存できません。記録は保持しています。"; return false }
    }

    func saveCard(petID: UUID, ids: [UUID], text: String, zooms: [Double] = [1, 1], offsets: [Double] = [0, 0]) throws {
        guard ids.count == 2, Set(ids).count == 2,
              ids.allSatisfy({ id in photos.contains { $0.id == id && $0.petID == petID } }) else {
            throw PrototypeError(message: "同じPetの写真を2枚選択してください。")
        }
        guard zooms.count == 2, offsets.count == 2, zooms.allSatisfy({ (1...3).contains($0) }),
              offsets.allSatisfy({ (-0.25...0.25).contains($0) }), text.count <= PrototypePolicy.cardTextCharacters else {
            throw PrototypeError(message: "切り抜き位置と100文字以内の文章を確認してください。")
        }
        try persistMutation { cards.append(MemoryRecord(id: UUID(), petID: petID, photos: ids, text: text, zooms: zooms, offsets: offsets)) }
    }
}
