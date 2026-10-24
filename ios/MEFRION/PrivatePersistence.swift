import Foundation
import UIKit

private struct StoredPhoto: Codable {
    let id: UUID
    let petID: UUID
    let image: Data
    let fingerprint: String
    let captured: String?
    let title: String
    var eventKind:String?=nil
    var note:String?=nil
}
private struct PrivateSnapshot: Codable {
    let schema: Int
    let pets: [PetRecord]
    let photos: [StoredPhoto]
    let cards: [MemoryRecord]
    let selectedPet: UUID?
    let twinsHistory:[TwinsHistoryRecord]?
    let referenceTwinsHistory:[ReferenceSearchRecord]?
}

extension PrototypeStore {
    func erasePrivateState() throws {
        try persistMutation {pets=[];photos=[];cards=[];drafts=[];selectedPet=nil;twinsHistory=[];referenceTwinsHistory=[]}
    }
    static var deviceStorageURL: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("MEFRION",isDirectory:true).appendingPathComponent("private-state.json")
    }

    func restorePrivateState() throws {
        guard let storageURL, FileManager.default.fileExists(atPath:storageURL.path) else { return }
        let snapshot = try JSONDecoder().decode(PrivateSnapshot.self,from:Data(contentsOf:storageURL))
        guard snapshot.schema == 1 else { throw PrototypeError(message:"保存形式を確認してください。") }
        let restored = try snapshot.photos.map { photo -> PhotoRecord in
            guard let image=UIImage(data:photo.image) else { throw PrototypeError(message:"画像を読み込めません。") }
            return PhotoRecord(id:photo.id,petID:photo.petID,image:image,fingerprint:photo.fingerprint,captured:photo.captured,title:photo.title,eventKind:photo.eventKind,note:photo.note)
        }
        pets=snapshot.pets;photos=restored;cards=snapshot.cards;selectedPet=snapshot.selectedPet;twinsHistory=Self.recentTwinsHistory(snapshot.twinsHistory ?? [])
        referenceTwinsHistory=snapshot.referenceTwinsHistory ?? []
        try pruneReferenceHistory()
    }

    func persistMutation(_ body: () throws -> Void) throws {
        guard storageError == nil else { throw PrototypeError(message:"保存データの読み込みエラーを解決してから変更してください。既存データの上書きを防いでいます。") }
        let before=(pets,photos,cards,drafts,selectedPet,twinsHistory,referenceTwinsHistory)
        do {
            try body()
            guard let storageURL else { return } // Isolated memory stores for unit tests.
            let stored = try photos.map { photo -> StoredPhoto in
                guard let data=photo.image.pngData() else { throw PrototypeError(message:"画像を保存できません。") }
                return StoredPhoto(id:photo.id,petID:photo.petID,image:data,fingerprint:photo.fingerprint,captured:photo.captured,title:photo.title,eventKind:photo.eventKind,note:photo.note)
            }
            let snapshot=PrivateSnapshot(schema:1,pets:pets,photos:stored,cards:cards,selectedPet:selectedPet,twinsHistory:twinsHistory,referenceTwinsHistory:referenceTwinsHistory)
            let data=try JSONEncoder().encode(snapshot)
            let folder=storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
            var excludedFolder=folder
            var values=URLResourceValues();values.isExcludedFromBackup=true
            try excludedFolder.setResourceValues(values)
            try data.write(to:storageURL,options:[.atomic,.completeFileProtection])
        } catch {
            pets=before.0;photos=before.1;cards=before.2;drafts=before.3;selectedPet=before.4;twinsHistory=before.5
            referenceTwinsHistory=before.6
            throw error
        }
    }
}
