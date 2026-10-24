import XCTest
import UIKit
import ImageIO
@testable import MEFRION

@MainActor
final class PrototypeTests: XCTestCase {
    func testProfileIconIsSquareBoundedAndStripsLocationMetadata() throws {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let image=UIGraphicsImageRenderer(size:CGSize(width:1200,height:600),format:format).image {ctx in
            UIColor.systemPink.setFill();ctx.fill(CGRect(x:0,y:0,width:1200,height:600))
        }
        let original=NSMutableData()
        let destination=try XCTUnwrap(CGImageDestinationCreateWithData(original,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(destination,try XCTUnwrap(image.cgImage),[kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:35.0,kCGImagePropertyGPSLatitudeRef:"N",kCGImagePropertyGPSLongitude:139.0,kCGImagePropertyGPSLongitudeRef:"E"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let value=try XCTUnwrap(ProfileIconCodec.encode(data:original as Data))
        let bytes=try XCTUnwrap(Data(base64Encoded:value))
        XCTAssertLessThanOrEqual(bytes.count,16384)
        let source=try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData,nil))
        let props=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int,props[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertLessThanOrEqual(try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int),256)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary])
        XCTAssertNotNil(ProfileIconCodec.image(value))
    }
    func testProfileIconRejectsInvalidAndOversizedInputsAndDecodesLegacyModels() throws {
        XCTAssertNil(ProfileIconCodec.encode(data:Data("not an image".utf8)))
        XCTAssertNil(ProfileIconCodec.image(String(repeating:"a",count:22501)))
        let pet=try JSONDecoder().decode(CloudPet.self,from:Data(#"{"id":"p","name":"こむぎ","species":"dog","breed":"柴犬","introduction":"","role":"owner"}"#.utf8))
        XCTAssertNil(pet.icon)
        let comment=try JSONDecoder().decode(CloudComment.self,from:Data(#"{"id":"c","body":"かわいい","parent":null,"display_name":"こむぎ","mine":true,"deleted":false,"created_at":"2026-10-24T00:00:00Z"}"#.utf8))
        XCTAssertNil(comment.icon)
    }
    func testNotificationDraftSerializesAndCoalescesInFlightChanges() async {
        var writes:[Int]=[];var first:CheckedContinuation<Void,Never>?
        let draft=NotificationPreferenceDraft(0) {value in
            writes.append(value)
            if writes.count==1 {await withCheckedContinuation {first=$0}}
        }
        draft.load(0);draft.change(1)
        while first==nil {await Task.yield()}
        draft.change(2);draft.change(3);first?.resume()
        await draft.waitUntilSaved()
        XCTAssertEqual(writes,[1,3]);XCTAssertEqual(draft.value,3);XCTAssertNil(draft.error)
    }
    func testNotificationDraftRollsBackFailedWriteAndRetriesIntent() async {
        var writes:[Int]=[]
        let draft=NotificationPreferenceDraft(0) {value in
            writes.append(value);if writes.count==1 {throw URLError(.notConnectedToInternet)}
        }
        draft.load(0);draft.change(2);await draft.waitUntilSaved()
        XCTAssertEqual(draft.value,0);XCTAssertNotNil(draft.error)
        draft.retry();await draft.waitUntilSaved()
        XCTAssertEqual(writes,[2,2]);XCTAssertEqual(draft.value,2);XCTAssertNil(draft.error)
    }
    func testNotificationLoadingDoesNotOverwriteServerPreferences() async {
        var writes:[Int]=[]
        let draft=NotificationPreferenceDraft(0) {writes.append($0)}
        draft.change(1);draft.load(4);await draft.waitUntilSaved()
        XCTAssertEqual(draft.value,4);XCTAssertTrue(writes.isEmpty)
    }

    func testBreedAutocompleteUsesSpeciesAndCanonicalNames() {
        XCTAssertEqual(PetBreedCatalog.canonical("といぷー",species:"dog"),"トイ・プードル")
        XCTAssertEqual(PetBreedCatalog.canonical("アメショ",species:"cat"),"アメリカン・ショートヘア")
        XCTAssertEqual(PetBreedCatalog.canonical("雑種",species:"cat"),"ミックス猫")
        XCTAssertNil(PetBreedCatalog.canonical("アメショ",species:"dog"))
        XCTAssertTrue(PetBreedCatalog.suggestions(for:"すこ",species:"cat").contains("スコティッシュ・フォールド"))
        XCTAssertFalse(PetBreedCatalog.suggestions(for:"すこ",species:"dog").contains("スコティッシュ・フォールド"))
    }
    func testPetValidationMessagesAreSingleSentence() {
        for error in [PetPostValidationError.imageNotRecognized,.videoNotRecognized,.unreadable] {
            let text=error.localizedDescription
            XCTAssertFalse(text.contains("。"))
            XCTAssertLessThan(text.count,35)
        }
    }
    func testRecommendedFeedRefreshPromotesUnseenPostsWithoutDuplicates() {
        let posts=(0..<50).map {index in
            CloudPublicPost(id:"post-\(index)",pet_id:"pet-\(index)",name:"Pet \(index)",species:index.isMultiple(of:2) ? "dog" : "cat",breed:"",body:"",kind:"post",media:["media-\(index)"],likes:0,comments:0,liked:false,saved:false,following:false)
        }
        let first=CloudFamilyClient.recommendedOrder(posts,impressions:[:],seed:1)
        XCTAssertEqual(Set(first.map(\.id)),Set(posts.map(\.id)))
        let seen=Dictionary(uniqueKeysWithValues:first.prefix(12).map{($0.id,1)})
        let second=CloudFamilyClient.recommendedOrder(posts,impressions:seen,seed:2)
        XCTAssertEqual(Set(second.map(\.id)),Set(posts.map(\.id)))
        XCTAssertTrue(Set(first.prefix(12).map(\.id)).isDisjoint(with:Set(second.prefix(12).map(\.id))))
        XCTAssertTrue(zip(second,second.dropFirst()).prefix(20).allSatisfy{pair in pair.0.species != pair.1.species})
        XCTAssertEqual(CloudFamilyClient.recommendedOrder(Array(posts.prefix(1)),impressions:seen,seed:3).map(\.id),["post-0"])
    }
    func testSignupReportsTheUnmetConditionInsteadOfSilentlyDisabling() {
        XCTAssertTrue(SignupRequirements.validEmail("pet.owner@docomo.ne.jp"))
        XCTAssertEqual(SignupRequirements.validationMessage(email:"pet@example.com",password:"Paw12345",confirmation:"Paw12345",adult:true,confirmed:true),"パスワードは12文字以上にしてね")
        XCTAssertEqual(SignupRequirements.validationMessage(email:"pet@example.com",password:"Paw12345more",confirmation:"",adult:true,confirmed:true),"確認用のパスワードも入力してね")
        XCTAssertEqual(SignupRequirements.validationMessage(email:"pet@example.com",password:"Paw12345more",confirmation:"Paw12345other",adult:true,confirmed:true),"2つのパスワードを同じにしてね")
        XCTAssertNil(SignupRequirements.validationMessage(email:"pet.owner@docomo.ne.jp",password:"Paw12345more",confirmation:"Paw12345more",adult:true,confirmed:true))
    }
    func testSignupRequiresMatchingPasswordAndExplicitChecks() {
        let valid=SignupRequirements.valid(email:"person@example.com",password:"long-password-123",confirmation:"long-password-123",adult:true,confirmed:true)
        XCTAssertTrue(valid)
        XCTAssertFalse(SignupRequirements.valid(email:"person@example.com",password:"long-password-123",confirmation:"different-pass-123",adult:true,confirmed:true))
        XCTAssertFalse(SignupRequirements.valid(email:"person@example.com",password:"short",confirmation:"short",adult:true,confirmed:true))
        XCTAssertFalse(SignupRequirements.valid(email:"person@example.com",password:"long-password-123",confirmation:"long-password-123",adult:false,confirmed:true))
        XCTAssertFalse(SignupRequirements.valid(email:"person@example.com",password:"long-password-123",confirmation:"long-password-123",adult:true,confirmed:false))
        XCTAssertFalse(SignupRequirements.valid(email:"personexample.com",password:"long-password-123",confirmation:"long-password-123",adult:true,confirmed:true))
    }
    func testStreamedTwinsRankingMatchesBatchAndExcludesSource() async throws {
        let engine=DemoTwinsEngine();let query=try XCTUnwrap(UIImage(named:"pet-0")?.cgImage)
        var candidates:[(String,CGImage)]=[]
        for index in 0..<10 {candidates.append((String(index),try XCTUnwrap(UIImage(named:"pet-\(index)")?.cgImage)))}
        let expected=try await engine.rank(image:query,candidates:candidates)
        let indexed=Dictionary(uniqueKeysWithValues:candidates)
        let streamed=try await engine.rankStream(image:query,candidateIDs:candidates.map(\.0).reversed()) {indexed[$0]}
        XCTAssertEqual(streamed,expected);XCTAssertFalse(streamed.contains("0"));XCTAssertLessThanOrEqual(streamed.count,3)
        let missing=try await engine.rankStream(image:query,candidateIDs:["missing"]) {_ in nil};XCTAssertTrue(missing.isEmpty)
    }
    func testUploadPauseRetainsSuccessfulPhotoAndRestoresOnlyRemaining() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer {try? FileManager.default.removeItem(at:folder)}
        let actor=UUID().uuidString,queue=CloudUploadQueue(folder:folder)
        try queue.activate(actor:actor)
        let first=CloudUploadDraft(pet:"owned-pet",jpeg:Data([1]),captured:nil),second=CloudUploadDraft(pet:"owned-pet",jpeg:Data([2]),captured:nil)
        try queue.append([first,second]);var sent:[UUID]=[]
        await queue.send(pet:"owned-pet") {draft in sent.append(draft.id);queue.pause()}
        XCTAssertEqual(sent,[first.id]);XCTAssertEqual(queue.drafts[0].state,.complete);XCTAssertEqual(queue.drafts[1].state,.pending)
        let restored=CloudUploadQueue(folder:folder);try restored.activate(actor:actor);XCTAssertEqual(restored.drafts.map(\.id),[second.id])
        await restored.send(pet:"owned-pet") {draft in sent.append(draft.id)}
        XCTAssertEqual(sent,[first.id,second.id]);XCTAssertEqual(restored.drafts[0].state,.complete)
    }
    func testPKCEAndAuthenticationCallbackValidation() {
        XCTAssertEqual(CloudFamilyClient.pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(CloudFamilyClient.authCode(URL(string:"mefrion://auth?code=verified-code")!),"verified-code")
        for address in ["https://auth?code=x","mefrion://family?code=x","mefrion://auth?code=x&code=y","mefrion://auth?code=x#access_token=unsafe","mefrion://auth?error=cancelled"] {
            XCTAssertNil(CloudFamilyClient.authCode(URL(string:address)!))
        }
    }
    func testExplicitPrivateErasurePersistsAndIsIdempotent() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let path=folder.appendingPathComponent("private.json"),store=PrototypeStore(storageURL:path)
        try store.createPet(name:"Private",species:.dog);store.addDemoDrafts();try store.saveDrafts(allowDuplicates:false)
        try store.erasePrivateState();try store.erasePrivateState()
        let restored=PrototypeStore(storageURL:path)
        XCTAssertTrue(restored.pets.isEmpty);XCTAssertTrue(restored.photos.isEmpty);XCTAssertTrue(restored.cards.isEmpty);XCTAssertTrue(restored.twinsHistory.isEmpty);XCTAssertNil(restored.selectedPet)
    }
    func testPrivateProfilePicturesRequireSamePetAndDeleteWithPhoto() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let path=folder.appendingPathComponent("private.json"),store=PrototypeStore(storageURL:path)
        try store.createPet(name:"One",species:.dog);let first=try XCTUnwrap(store.pets.first?.id)
        store.addDemoDrafts();try store.saveDrafts(allowDuplicates:false);let image=try XCTUnwrap(store.photos.first?.id)
        try store.updatePet(id:first,name:"One",breed:"",introduction:"",pictures:(image,image))
        XCTAssertEqual(PrototypeStore(storageURL:path).pets.first?.coverPhotoID,image)
        try store.createPet(name:"Two",species:.cat);let second=try XCTUnwrap(store.pets.last?.id)
        XCTAssertThrowsError(try store.updatePet(id:second,name:"Two",breed:"",introduction:"",pictures:(image,image)))
        XCTAssertTrue(store.deletePhoto(image));let restored=PrototypeStore(storageURL:path)
        XCTAssertNil(restored.pets.first?.coverPhotoID);XCTAssertNil(restored.pets.first?.iconPhotoID)
        XCTAssertEqual(restored.pets.first?.isPublic,false)
    }
    func testMilestoneAndOptionalPetFieldsPersistWithOldSnapshotCompatibility() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let path=folder.appendingPathComponent("private.json"),store=PrototypeStore(storageURL:path)
        try store.createPet(name:"Private",species:.cat,sex:"female",birthday:"2020-02")
        store.addDemoDrafts();try store.saveDrafts(allowDuplicates:false)
        let photo=try XCTUnwrap(store.photos.first)
        try store.updatePhoto(photo.id,title:"Birthday",captured:"2026-10",eventKind:"birthday",note:"Family only")
        let restored=PrototypeStore(storageURL:path)
        XCTAssertEqual(restored.pets.first?.birthday,"2020-02");XCTAssertEqual(restored.pets.first?.sex,"female")
        XCTAssertEqual(restored.photos.first(where:{$0.id==photo.id})?.eventKind,"birthday")
        XCTAssertEqual(restored.photos.first(where:{$0.id==photo.id})?.note,"Family only")
        XCTAssertThrowsError(try store.updatePhoto(photo.id,title:"Changed",captured:"2026-10",eventKind:"unknown"))
        XCTAssertThrowsError(try store.updatePhoto(photo.id,title:"Changed",captured:"2026-10",note:String(repeating:"x",count:201)))
        var old=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
        old["pets"]=(old["pets"] as? [[String:Any]])?.map {item in var item=item;item.removeValue(forKey:"sex");item.removeValue(forKey:"birthday");return item}
        old["photos"]=(old["photos"] as? [[String:Any]])?.map {item in var item=item;item.removeValue(forKey:"eventKind");item.removeValue(forKey:"note");return item}
        try JSONSerialization.data(withJSONObject:old).write(to:path)
        let compatible=PrototypeStore(storageURL:path)
        XCTAssertNil(compatible.storageError);XCTAssertEqual(compatible.photos.count,2);XCTAssertNil(compatible.pets.first?.birthday)
    }
    func testPetEditRetainsPrivacyAndSurvivesReload() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let path=folder.appendingPathComponent("private.json"),store=PrototypeStore(storageURL:path)
        try store.createPet(name:"Original",species:.dog)
        let id=try XCTUnwrap(store.pets.first?.id)
        try store.updatePet(id:id,name:" Updated ",breed:"Dog",introduction:"Private family memory")
        let restored=PrototypeStore(storageURL:path)
        XCTAssertEqual(restored.pets.first?.name,"Updated");XCTAssertEqual(restored.pets.first?.introduction,"Private family memory")
        XCTAssertEqual(restored.pets.first?.isPublic,false)
        XCTAssertThrowsError(try store.updatePet(id:id,name:" ",breed:"",introduction:""))
        XCTAssertThrowsError(try store.updatePet(id:id,name:"Valid",breed:"",introduction:String(repeating:"x",count:501)))
        XCTAssertEqual(PrototypeStore(storageURL:path).pets.first?.name,"Updated")
    }
    func testTwinsHistoryTTLAndPrivatePersistence() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let path=folder.appendingPathComponent("private.json"),now=Date()
        let store=PrototypeStore(storageURL:path)
        try store.recordTwinsSearch(species:.dog,state:"results",mode:"local",candidates:[2,4],now:now)
        XCTAssertEqual(PrototypeStore(storageURL:path).twinsHistory.first?.candidateIDs,[2,4])
        XCTAssertFalse(String(decoding:try Data(contentsOf:path),as:UTF8.self).contains("inputImage"))
        XCTAssertTrue(PrototypeStore.recentTwinsHistory(store.twinsHistory,now:now.addingTimeInterval(86400)).isEmpty)
        XCTAssertThrowsError(try store.recordTwinsSearch(species:.dog,state:"results",mode:"local",candidates:[1]))
        try store.clearTwinsHistory();XCTAssertTrue(PrototypeStore(storageURL:path).twinsHistory.isEmpty)
    }
    func testPrivateCropKeepsInputAndBounds() throws {
        let original=UIGraphicsImageRenderer(size:CGSize(width:600,height:400)).image {_ in UIColor.orange.setFill();UIRectFill(CGRect(x:0,y:0,width:600,height:400))}
        let cropped=try PrivateImageCrop.crop(original,zoom:2,x:1,y:0)
        XCTAssertEqual(cropped.cgImage?.width,200);XCTAssertEqual(cropped.cgImage?.height,200)
        XCTAssertEqual(original.size,CGSize(width:600,height:400))
        XCTAssertThrowsError(try PrivateImageCrop.crop(original,zoom:0.5,x:0.5,y:0.5))
        XCTAssertThrowsError(try PrivateImageCrop.crop(original,zoom:2,x:1.1,y:0.5))
    }
    func testCloudSessionRefreshBoundary() {
        XCTAssertTrue(CloudFamilyClient.needsSessionRefresh(expiresAt:nil,now:100))
        XCTAssertTrue(CloudFamilyClient.needsSessionRefresh(expiresAt:99,now:100))
        XCTAssertTrue(CloudFamilyClient.needsSessionRefresh(expiresAt:160,now:100))
        XCTAssertFalse(CloudFamilyClient.needsSessionRefresh(expiresAt:161,now:100))
    }
    func testCloudDuplicateResponseDoesNotHidePermissionErrors() {
        let duplicate=Data(#"{"statusCode":"409","error":"Duplicate","message":"Already exists"}"#.utf8)
        XCTAssertTrue(CloudFamilyClient.isExistingUpload(status:400,data:duplicate))
        XCTAssertTrue(CloudFamilyClient.isExistingUpload(status:409,data:duplicate))
        XCTAssertFalse(CloudFamilyClient.isExistingUpload(status:403,data:duplicate))
        XCTAssertFalse(CloudFamilyClient.isExistingUpload(status:400,data:Data(#"{"error":"Unauthorized"}"#.utf8)))
        XCTAssertFalse(CloudFamilyClient.isExistingUpload(status:400,data:Data()))
    }
    func testCloudUploadQueueDurablePartialRetryAndAccountIsolation() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let actor=UUID().uuidString,other=UUID().uuidString
        let first=CloudUploadDraft(pet:"pet",jpeg:Data([1]),captured:"2020")
        let second=CloudUploadDraft(pet:"pet",jpeg:Data([2]),captured:nil)
        let queue=CloudUploadQueue(folder:folder);try queue.activate(actor:actor);try queue.append([first,second])
        await queue.send(pet:"pet") {if $0.id==second.id {throw CocoaError(.fileReadUnknown)}}
        let different=CloudUploadQueue(folder:folder);try different.activate(actor:other);XCTAssertTrue(different.drafts.isEmpty)
        let restored=CloudUploadQueue(folder:folder);try restored.activate(actor:actor)
        XCTAssertEqual(restored.drafts.map(\.id),[second.id]);XCTAssertEqual(restored.drafts.first?.jpeg,second.jpeg)
        var sent:[UUID]=[];await restored.send(pet:"pet") {sent.append($0.id)};XCTAssertEqual(sent,[second.id])
        let again=CloudUploadQueue(folder:folder);try again.activate(actor:actor);XCTAssertTrue(again.drafts.isEmpty)
        try again.append([second]);again.clear()
        let afterLogout=CloudUploadQueue(folder:folder);try afterLogout.activate(actor:actor);XCTAssertTrue(afterLogout.drafts.isEmpty)
    }
    func testCloudQueueStorageFailureRollsBackAndCorruptionIsProtected() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        try Data([1]).write(to:folder)
        let queue=CloudUploadQueue(folder:folder);try queue.activate(actor:UUID().uuidString)
        XCTAssertThrowsError(try queue.append([CloudUploadDraft(pet:"pet",jpeg:Data([1]),captured:nil)]));XCTAssertTrue(queue.drafts.isEmpty)
        try FileManager.default.removeItem(at:folder);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let actor=UUID().uuidString,file=folder.appendingPathComponent(actor+".json");try Data("broken".utf8).write(to:file)
        let damaged=CloudUploadQueue(folder:folder);XCTAssertThrowsError(try damaged.activate(actor:actor))
        XCTAssertThrowsError(try damaged.append([CloudUploadDraft(pet:"pet",jpeg:Data([1]),captured:nil)]))
        XCTAssertEqual(try Data(contentsOf:file),Data("broken".utf8))
    }
    func testCloudQueueDetectsDuplicatePendingBytesWithoutLosingOriginal() throws {
        let queue=CloudUploadQueue(),draft=CloudUploadDraft(pet:"a",jpeg:Data([1]),captured:nil)
        try queue.append([draft]);XCTAssertThrowsError(try queue.append([CloudUploadDraft(pet:"a",jpeg:Data([1]),captured:nil)]));XCTAssertEqual(queue.drafts.map(\.id),[draft.id])
        try queue.append([CloudUploadDraft(pet:"b",jpeg:Data([1]),captured:nil)]);XCTAssertEqual(queue.drafts.count,2)
    }
    func testPublicationRetryReusesFailedPhotoAfterItIsSelectedAgain() async throws {
        let queue=CloudUploadQueue()
        let original=CloudUploadDraft(pet:"pet",jpeg:Data([1,2,3]),captured:nil)
        try queue.append([original])
        await queue.send(pet:"pet") {_ in throw CocoaError(.fileReadUnknown)}
        let selectedAgain=CloudUploadDraft(pet:"pet",jpeg:original.jpeg,captured:nil)
        XCTAssertEqual(queue.pendingMatch(for:selectedAgain)?.id,original.id)
        try queue.allowPublicationRetry(ids:[original.id])
        XCTAssertTrue(queue.drafts[0].duplicateApproved)
        var retried:[UUID]=[]
        await queue.send(pet:"pet") {retried.append($0.id)}
        XCTAssertEqual(retried,[original.id])
        XCTAssertEqual(queue.drafts[0].state,.complete)
    }
    func testCloudBatchPartialRetryKeepsIdentityAndSkipsCompleted() async throws {
        let queue=CloudUploadQueue()
        let first=CloudUploadDraft(pet:"family",jpeg:Data([1]),captured:"2020")
        let second=CloudUploadDraft(pet:"family",jpeg:Data([2]),captured:nil)
        try queue.append([first,second])
        var attempts:[UUID]=[]
        await queue.send(pet:"family") {draft in attempts.append(draft.id);if draft.id==second.id {throw CocoaError(.fileReadUnknown)}}
        XCTAssertEqual(queue.drafts.map(\.state),[.complete,.failed])
        XCTAssertTrue(queue.drafts[0].jpeg.isEmpty)
        XCTAssertEqual(queue.drafts[1].jpeg,Data([2]))
        await queue.send(pet:"family") {draft in attempts.append(draft.id)}
        XCTAssertEqual(attempts,[first.id,second.id,second.id])
        XCTAssertEqual(queue.drafts.map(\.state),[.complete,.complete])
    }
    func testCloudBatchLimitsAndLogoutDuringUpload() async throws {
        let queue=CloudUploadQueue()
        XCTAssertThrowsError(try queue.append((0..<31).map {_ in CloudUploadDraft(pet:"a",jpeg:Data([1]),captured:nil)}))
        XCTAssertThrowsError(try queue.append([CloudUploadDraft(pet:"a",jpeg:Data([1]),captured:"2021-02-29")]))
        XCTAssertTrue(queue.drafts.isEmpty)
        try queue.append([CloudUploadDraft(pet:"a",jpeg:Data([1]),captured:nil)])
        await queue.send(pet:"b") {_ in XCTFail("Different Pet must not send")}
        await queue.send(pet:"a") {_ in queue.clear()}
        XCTAssertTrue(queue.drafts.isEmpty,"An in-flight completion must not restore a logged-out user's drafts")
    }
    func testPrivatePersistenceReloadAndDeleteCascade() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let path=directory.appendingPathComponent("private.json")
        let store=PrototypeStore(storageURL:path)
        try store.createPet(name:"こむぎ",species:.dog)
        store.addDemoDrafts();try store.saveDrafts(allowDuplicates:false)
        let pet=try XCTUnwrap(store.selectedPet)
        try store.saveCard(petID:pet,ids:store.photos.map(\.id),text:"思い出")
        let restored=PrototypeStore(storageURL:path)
        XCTAssertNil(restored.storageError)
        XCTAssertEqual(restored.pets.first?.name,"こむぎ")
        XCTAssertEqual(restored.photos.count,2)
        XCTAssertEqual(restored.cards.first?.text,"思い出")
        XCTAssertTrue(restored.deletePhoto(try XCTUnwrap(restored.photos.first?.id)))
        let again=PrototypeStore(storageURL:path)
        XCTAssertEqual(again.photos.count,1);XCTAssertTrue(again.cards.isEmpty)
    }

    func testPrivatePersistenceFailureRollsBackMemory() throws {
        let blocker=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("existing".utf8).write(to:blocker)
        defer { try? FileManager.default.removeItem(at:blocker) }
        let store=PrototypeStore(storageURL:blocker.appendingPathComponent("private.json"))
        XCTAssertThrowsError(try store.createPet(name:"こむぎ",species:.dog))
        XCTAssertTrue(store.pets.isEmpty);XCTAssertNil(store.selectedPet)
        XCTAssertEqual(try Data(contentsOf:blocker),Data("existing".utf8))
    }

    func testCorruptSnapshotNeverOverwritten() throws {
        let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original=Data("corrupt snapshot".utf8);try original.write(to:path)
        defer { try? FileManager.default.removeItem(at:path) }
        let store=PrototypeStore(storageURL:path)
        XCTAssertNotNil(store.storageError)
        XCTAssertThrowsError(try store.createPet(name:"こむぎ",species:.dog))
        XCTAssertEqual(try Data(contentsOf:path),original)
    }
    func testPrivatePetWithZeroPhotos() throws {
        let store = PrototypeStore()
        try store.createPet(name: "こむぎ", species: .dog)
        XCTAssertFalse(store.pets[0].isPublic)
        XCTAssertTrue(store.photos.isEmpty)
    }
    func testDatePrecisionAndInvalidDates() {
        for date in ["", "2020", "2020-02", "2020-02-29"] { XCTAssertTrue(PrototypeStore.dateIsValid(date)) }
        for date in ["0000", "2021-02-29", "2020-13", "2020-1", "abc", "+020", "２０２０"] { XCTAssertFalse(PrototypeStore.dateIsValid(date)) }
    }
    func testPrivateSaveRetryAndCardDeletion() throws {
        let store = PrototypeStore()
        try store.createPet(name: "こむぎ", species: .dog)
        store.addDemoDrafts()
        XCTAssertEqual(store.drafts.count, 2)
        try store.saveDrafts(allowDuplicates: false)
        try store.saveDrafts(allowDuplicates: false)
        XCTAssertEqual(store.photos.count, 2)
        let petID = try XCTUnwrap(store.selectedPet)
        let ids = store.photos.map(\.id)
        try store.saveCard(petID: petID, ids: ids, text: "思い出")
        XCTAssertEqual(store.cards.count, 1)
        store.deletePhoto(ids[0])
        XCTAssertTrue(store.cards.isEmpty)
    }
    func testOldPhotoAndUnknownDate() throws {
        let store = PrototypeStore()
        try store.createPet(name: "こむぎ", species: .dog)
        store.addDemoDrafts()
        store.drafts[0].captured = ""
        try store.saveDrafts(allowDuplicates: false)
        let petID = try XCTUnwrap(store.selectedPet)
        XCTAssertEqual(store.album(petID).last?.captured, nil)
        XCTAssertEqual(store.album(petID).first?.captured, "2026-10")
    }
    func testVisualOwnedDemoSearchHasNoSelfAndAtMostThree() async throws {
        let image = try XCTUnwrap(UIImage(named: "pet-0")?.cgImage)
        let results = try await DemoTwinsEngine().search(image: image, species: .dog)
        XCTAssertFalse(results.isEmpty, "Owned demo fixture must exercise the result path")
        XCTAssertLessThanOrEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy { $0.id % 2 == 0 && $0.id != 0 })
        XCTAssertTrue(results.allSatisfy { $0.distance > DemoTwinsPolicy.duplicateDistance })
    }

    func testLargeBlankTwinsPhotoRejected() async throws {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let image=UIGraphicsImageRenderer(size:CGSize(width:256,height:256),format:format).image {_ in UIColor.orange.setFill();UIRectFill(CGRect(x:0,y:0,width:256,height:256))}
        do {_=try await DemoTwinsEngine().rank(image:try XCTUnwrap(image.cgImage),candidates:[]);XCTFail("A featureless input cannot produce a resemblance result")} catch {XCTAssertTrue(error is DemoTwinsError)}
    }
    func testSmallTwinsInputRejected() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { _ in UIColor.black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 32, height: 32)) }
        do {
            _ = try await DemoTwinsEngine().search(image: try XCTUnwrap(image.cgImage), species: .dog)
            XCTFail("Small input must fail quality validation")
        } catch is DemoTwinsError { }
    }

    func testCardCropRetainedAndOutOfRangeDenied() throws {
        let store = PrototypeStore()
        try store.createPet(name: "こむぎ", species: .dog)
        store.addDemoDrafts(); try store.saveDrafts(allowDuplicates: false)
        let petID = try XCTUnwrap(store.selectedPet), ids = store.photos.map(\.id)
        try store.saveCard(petID: petID, ids: ids, text: "", zooms: [1.5, 2], offsets: [0.1, 0])
        XCTAssertEqual(store.cards[0].zooms, [1.5, 2])
        XCTAssertThrowsError(try store.saveCard(petID: petID, ids: ids, text: "", zooms: [4, 1]))
    }

}
