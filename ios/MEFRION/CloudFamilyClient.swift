import SwiftUI
import Security
import CryptoKit
import ImageIO
import os

struct CloudPet:Codable,Identifiable { let id:String;let name:String;let species:String;let breed:String;let introduction:String;let role:String?;var details:[String:String]?=nil;var public_fields:[String]?=nil }
private struct PendingFirstPet:Codable {let email:String;let name:String;let species:String;let breed:String}
struct CloudPhoto:Decodable,Identifiable { let id:String;let path:String;let captured:String?;let title:String;let mine:Bool;var event_kind:String?=nil;var note:String?=nil;var provider_name:String?=nil;var created_at:String?=nil;var media_kind:String?=nil;var duration_seconds:Double?=nil }
struct CloudInvitation:Decodable { let id:String;let token:String;let expires_at:String }
struct CloudMember:Decodable,Identifiable {let id:String;let role:String;let me:Bool;var display_name:String?=nil}
struct ProvidedPhoto:Decodable,Identifiable {let id:String;let captured:String?;let title:String;let sns:Bool;let twins:Bool;let external_share:Bool}
struct CloudPublicPost:Decodable,Identifiable {let id:String;let pet_id:String;let name:String;let species:String;let breed:String;let body:String;let kind:String;let media:[String];var likes:Int;var comments:Int;var liked:Bool;var saved:Bool;var following:Bool;var tags:[CloudPublicTag]?=nil;var published_at:String?=nil;var video_media:[String]?=nil}
struct CloudPublicTag:Decodable,Identifiable {let id:String;let name:String}
struct CloudModerationNotice:Decodable,Identifiable {let id:String;let decision:String;let note:String;let created_at:String}
struct CloudBlockedPet:Decodable,Identifiable {let id:String;let name:String}
struct CloudPublication:Decodable {let id:String;let state:String}
private struct CloudPublicationUploadError:LocalizedError {
    let detail:String
    var errorDescription:String? {"写真を送れませんでした。"+detail+" もう一度お試しください。"}
}
struct CloudMyPublication:Decodable,Identifiable {
    let id:String;let pet_id:String;let pet_name:String;let body:String;let state:String;let created_at:String;let media:[String];let preview_photo:String?;var video_media:[String]?=nil
}
struct CloudComment:Decodable,Identifiable {let id:String;let body:String;let parent:String?;let display_name:String;let mine:Bool;let deleted:Bool;let created_at:String}
struct CloudNotificationPreferences:Codable {var like:Bool;var comment:Bool;var follow:Bool;var twins:Bool}
struct CloudSocialIdentity:Decodable {let name:String;let last_pet:String?}
struct CloudSocialConnection:Decodable,Identifiable {
    let id:String
    let name:String
    let species:String?
    let breed:String?
    let profile_pet_id:String?
    let followed_pet_name:String?
}
struct CloudSocialNotification:Decodable,Identifiable {let id:String;let kind:String;let name:String;let pet_name:String;let pet_id:String;let post_id:String?;let created_at:String;var count:Int?=nil}
struct CloudCard:Decodable,Identifiable {let id:String;let first:String;let second:String;let layout:CloudCardLayout;let mine:Bool}
struct CloudCardLayout:Decodable {let text:String?;let first_zoom:Double?;let first_x:Double?;let first_y:Double?;let second_zoom:Double?;let second_x:Double?;let second_y:Double?}
struct CloudAlbumGesture:Decodable {let photo_id:String;let gesture:String}
struct CloudFamilyActivity:Decodable,Identifiable {let id:String;let action:String;let mine:Bool;let created_at:String;var actor_name:String?=nil}
private struct CloudSession:Codable { let access_token:String;let refresh_token:String;let expires_at:Double? }
struct CloudEvent:Decodable,Identifiable {let id:String;let captured:String?;let title:String;let kind:String;let note:String;let mine:Bool}
struct CloudPetNotifications:Decodable {let frequency:String;let milestones:Bool;let paused_until:String?}
private struct PhotoReservation:Decodable { let id:String;let path:String;let state:String;var preview_path:String?=nil }

@MainActor
final class CloudFamilyClient:ObservableObject {
    static let shared=CloudFamilyClient()
    #if DEBUG
    private static let feedLogger=Logger(subsystem:"MEFRION",category:"public-feed")
    #endif
    #if DEBUG
    private let referenceProbeGuestID=UUID()
    #endif
    @Published var pets:[CloudPet]=[]
    @Published var photos:[CloudPhoto]=[]
    @Published var images:[String:UIImage]=[:]
    @Published var authenticated=false
    @Published private(set) var currentUserID:String?
    #if DEBUG
    private var uiReviewOnly=false
    private var albumFixtureGestures:[CloudAlbumGesture]=[]
    private var albumFixtureCards:[CloudCard]=[]
    private var feedFixtureRevision=0
    static func uiReviewFixture()->CloudFamilyClient {
        let client=CloudFamilyClient()
        guard ProcessInfo.processInfo.arguments.contains("--ui-test-isolated"),ProcessInfo.processInfo.arguments.contains("--ui-reference-gallery") else{return client}
        client.uiReviewOnly=true
        client.members=[CloudMember(id:"ui-owner",role:"owner",me:true),CloudMember(id:"ui-family",role:"member",me:false)]
        client.photos=[CloudPhoto(id:"ui-photo",path:"",captured:"2026-10",title:"所有デモイラスト",mine:true)]
        if let image=UIImage(named:"pet-0") {client.images=["ui-photo":image]}
        client.invitation=CloudInvitation(id:"ui-invite",token:"UI-PREVIEW-NOT-A-REAL-INVITATION",expires_at:"プレビュー")
        return client
    }
    #endif
    @Published var busy=false
    @Published var error:String?
    @Published var invitation:CloudInvitation?
    @Published var members:[CloudMember]=[]
    @Published var providedPhotos:[ProvidedPhoto]=[]
    @Published var publicPosts:[CloudPublicPost]=[]
    @Published var moderationNotices:[CloudModerationNotice]=[]
    @Published var blockedPets:[CloudBlockedPet]=[]
    @Published var publicImages:[String:UIImage]=[:]
    @Published private(set) var failedPublicImages:Set<String>=[]
    private var publicCompressedImages:[String:Data]=[:]
    private var publicCompressedOrder:[String]=[]
    let uploads=CloudUploadQueue(folder:ProcessInfo.processInfo.arguments.contains("--ui-test-isolated") ? nil : CloudUploadQueue.deviceFolder)
    private var session:CloudSession?
    private var twinsGuest:CloudSession?
    private var authenticationGeneration=UUID()
    private var refreshTask:Task<CloudSession,Error>?
    private var restoration:Task<Void,Never>?
    private(set) var sessionRefreshCount=0
    private var privacyGeneration=UUID()
    private var publicGeneration=UUID()
    private var publicFeedRevalidating=false
    var publicFeedIsRevalidating:Bool {publicFeedRevalidating}
    private var publicImageTask:Task<Void,Never>?
    private var initialQueuedPublicMedia:Set<String>=[]
    private var publicPrefetchQueue:[String]=[]
    private var publicPrefetchWorkers=0
    private var publicPrefetchAnchor = -1
    private var publicVideoFiles:[String:URL]=[:]
    private var publicVideoGeneration=UUID()
    private var publicVideoOrder:[String]=[]
    private var publicVideoLoads:[String:Task<URL,Error>]=[:]
    private var publicVideoPrefetchQueue:[String]=[]
    private var publicVideoPrefetchWorkers=0
    private var publicVideoPrefetchAnchor = -1
    private var visiblePublicVideos:[String:Int]=[:]
    private var publicImageOrder:[String]=[]
    private var visiblePublicMedia:Set<String>=[]
    private var inFlightPublicMedia:Set<String>=[]
    private var feedMode="all"
    private var feedQuery=""
    private var feedSpecies="all"
    private var recommendationImpressions:[String:Int]=[:]
    @Published private(set) var hasMorePublicPosts=false
    private var nextFeedDate:String?
    private var nextFeedID:String?
    private static let developmentBase="https://pmrvzpuznwzuejbuhaqm.supabase.co"
    private static let productionConfiguration:(url:String,key:String)? = {
        guard let file=Bundle.main.url(forResource:"ProductionPublicConfiguration",withExtension:"json"),
              let bytes=try? Data(contentsOf:file),
              let config=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:String],
              let address=config["url"],let url=URLComponents(string:address),
              url.scheme=="https",url.host?.hasSuffix(".supabase.co")==true,
              url.host != URLComponents(string:developmentBase)?.host,
              url.path.isEmpty || url.path=="/",
              url.query==nil,url.fragment==nil,
              let key=config["anon_key"],key.hasPrefix("sb_publishable_"),key.count>=32,
              !key.contains(where:\.isWhitespace) else {return nil}
        return (address,key)
    }()
    private var key:String {
        #if DEBUG
        return ProcessInfo.processInfo.environment["MEFRION_CLOUD_PUBLIC_KEY"] ?? UserDefaults.standard.string(forKey:"MEFRIONCloudPublicKey") ?? Self.developmentPublicKey
        #else
        return Self.productionConfiguration?.key ?? ""
        #endif
    }
    private static var developmentPublicKey:String {
        guard let file=Bundle.main.url(forResource:"DevelopmentPublicConfiguration",withExtension:"json"),let bytes=try? Data(contentsOf:file),let config=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:String],config["url"]==developmentBase,let key=config["anon_key"],key.hasPrefix("sb_publishable_") else {return ""}
        return key
    }
    private var base:String {
        #if DEBUG
        return Self.developmentBase
        #else
        return Self.productionConfiguration?.url ?? ""
        #endif
    }
    private let http:URLSession={ let c=URLSessionConfiguration.ephemeral;c.urlCache=nil;c.timeoutIntervalForRequest=20;return URLSession(configuration:c) }()
    private var isolated:Bool { ProcessInfo.processInfo.arguments.contains("--ui-test-isolated") }
    private var sessionStorageEnabled:Bool {
        #if DEBUG && targetEnvironment(simulator)
        return !isolated || ProcessInfo.processInfo.environment["MEFRION_TEST_PERSIST_SESSION"]=="1"
        #else
        return !isolated
        #endif
    }
    private var sessionService:String {
        #if DEBUG && targetEnvironment(simulator)
        if isolated && sessionStorageEnabled {return "MEFRION.development.family.test-persistence"}
        #endif
        #if DEBUG
        return "MEFRION.development.family"
        #else
        return "MEFRION.production.family"
        #endif
    }
    var configured:Bool { !key.isEmpty }
    private enum Failure:LocalizedError {
        case unavailable,providerUnavailable,notAuthenticated,denied,invalid,network,dailyLimit,referenceLimit,emailNotAuthorized,emailRateLimited,emailAlreadyRegistered
        var errorDescription:String? { switch self { case .referenceLimit:return "参考写真の検索はゲスト10回・会員50回/日（日本時間）までです。明日またお試しください。";case .unavailable:return "サービスに接続できません。時間をおいて再試行してください。";case .providerUnavailable:return "このログイン方法は現在利用できません。メールでログインしてください。";case .notAuthenticated:return "ログインが必要です。メールとパスワードを確認してください。";case .denied:return "操作できません。権限・招待・写真の状態を確認してください。";case .invalid:return "入力内容を確認してください。";case .network:return "接続できません。再試行してください。";case .dailyLimit:return "本日の検索回数を使い切りました。ゲスト初回1回・会員5回/日（日本時間）です。";case .emailNotAuthorized:return "このメールアドレスには現在確認メールを送れません。メール配信の設定が必要です。";case .emailRateLimited:return "メール送信の回数制限に達しました。時間をおいて再試行してください。";case .emailAlreadyRegistered:return "このメールアドレスは登録済みです。ログインまたはパスワードの復旧をお試しください。" } }
    }
    private func request(_ path:String,body:[String:Any]?=nil,token:String?=nil,raw:Data?=nil,contentType:String="image/jpeg") async throws -> Data {
        #if DEBUG
        if uiReviewOnly {throw Failure.unavailable}
        #endif
        guard configured,let url=URL(string:base+path) else {throw Failure.unavailable}
        var req=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalAndRemoteCacheData)
        req.setValue(key,forHTTPHeaderField:"apikey")
        if let token { req.setValue("Bearer "+token,forHTTPHeaderField:"Authorization") }
        if let body { req.httpMethod="POST";req.setValue("application/json",forHTTPHeaderField:"Content-Type");req.httpBody=try JSONSerialization.data(withJSONObject:body) }
        if let raw { req.httpMethod="POST";req.setValue(contentType,forHTTPHeaderField:"Content-Type");req.httpBody=raw }
        let (data,response)=try await http.data(for:req)
        guard let response=response as? HTTPURLResponse else {throw Failure.network}
        // A lost upload response may leave the object stored. finish_photo below
        // checks the registered path and provider before treating it as complete.
        if raw != nil && Self.isExistingUpload(status:response.statusCode,data:data) {return data}
        if response.statusCode==401 {throw Failure.notAuthenticated}
        if let error=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],error["message"] as? String == "daily_search_limit" {throw Failure.dailyLimit}
        if let error=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],error["message"] as? String == "reference_search_limit" {throw Failure.referenceLimit}
        if path.hasPrefix("/auth/v1/"),!(200..<300).contains(response.statusCode),
           let payload=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] {
            let details=[payload["code"],payload["error_code"],payload["msg"],payload["message"],payload["error_description"]]
                .compactMap {$0 as? String}.joined(separator:" ").lowercased()
            if details.contains("email_address_not_authorized") || details.contains("email address not authorized") {throw Failure.emailNotAuthorized}
            if response.statusCode==429 || details.contains("rate limit") || details.contains("rate_limit") {throw Failure.emailRateLimited}
            if details.contains("email_exists") || details.contains("already registered") {throw Failure.emailAlreadyRegistered}
        }
        guard (200..<300).contains(response.statusCode) else {throw Failure.denied}
        return data
    }
    static func isExistingUpload(status:Int,data:Data)->Bool {
        guard status==400 || status==409,
              let response=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {return false}
        return response["error"] as? String == "Duplicate"
    }
    func clearPrivateViews() {privacyGeneration=UUID();photos=[];images=[:];members=[];invitation=nil}
    func clearPublicViews() {publicGeneration=UUID();publicVideoGeneration=UUID();publicFeedRevalidating=false;publicImageTask?.cancel();publicImageTask=nil;initialQueuedPublicMedia=[];publicPrefetchQueue=[];publicPrefetchWorkers=0;publicPrefetchAnchor = -1;publicVideoPrefetchQueue=[];publicVideoPrefetchAnchor = -1;for task in publicVideoLoads.values {task.cancel()};publicVideoLoads=[:];for file in publicVideoFiles.values {try? FileManager.default.removeItem(at:file)};publicVideoFiles=[:];publicVideoOrder=[];visiblePublicVideos=[:];publicPosts=[];publicImages=[:];publicImageOrder=[];publicCompressedImages=[:];publicCompressedOrder=[];visiblePublicMedia=[];inFlightPublicMedia=[];failedPublicImages=[];recommendationImpressions=[:]}
    private func rpc<T:Decodable>(_ name:String,_ body:[String:Any]=[:]) async throws -> T {
        guard authenticated else {throw Failure.notAuthenticated}
        let data=try await authenticatedRequest("/rest/v1/rpc/mefrion_"+name,body:body)
        return try JSONDecoder().decode(T.self,from:data)
    }
    static func needsSessionRefresh(expiresAt:Double?,now:Double)->Bool {
        guard let expiresAt else {return true}
        return expiresAt <= now + 60
    }
    private func usableSession(force:Bool=false) async throws->CloudSession {
        guard let old=session,authenticated else {throw Failure.notAuthenticated}
        guard force || Self.needsSessionRefresh(expiresAt:old.expires_at,now:Date().timeIntervalSince1970) else {return old}
        let stamp=authenticationGeneration
        let task:Task<CloudSession,Error>
        if let existing=refreshTask {task=existing} else {
            task=Task {
                let bytes=try await self.request("/auth/v1/token?grant_type=refresh_token",body:["refresh_token":old.refresh_token])
                let renewed=try JSONDecoder().decode(CloudSession.self,from:bytes)
                _=try await self.request("/auth/v1/user",token:renewed.access_token)
                guard stamp==self.authenticationGeneration,self.authenticated else {throw CancellationError()}
                if self.sessionStorageEnabled {try self.saveSession(renewed)}
                self.session=renewed;self.sessionRefreshCount+=1
                return renewed
            }
            refreshTask=task
        }
        do {
            let renewed=try await task.value
            guard stamp==authenticationGeneration,authenticated else {throw CancellationError()}
            refreshTask=nil;return renewed
        } catch {
            guard stamp==authenticationGeneration else {throw CancellationError()}
            refreshTask=nil
            if case Failure.notAuthenticated=error {invalidateSession()}
            throw error
        }
    }
    private func authenticatedRequest(_ path:String,body:[String:Any]?=nil,raw:Data?=nil,contentType:String="image/jpeg") async throws->Data {
        let stamp=authenticationGeneration
        let active=try await usableSession()
        do {
            let data=try await request(path,body:body,token:active.access_token,raw:raw,contentType:contentType)
            guard stamp==authenticationGeneration,authenticated else {throw CancellationError()};return data
        } catch Failure.notAuthenticated {
            guard stamp==authenticationGeneration,authenticated else {throw CancellationError()}
            // Only retry a rejected token. Ambiguous network failures keep their
            // upload/publication UUID and are retried explicitly by the user.
            let renewed=try await usableSession(force:true)
            let data=try await request(path,body:body,token:renewed.access_token,raw:raw,contentType:contentType)
            guard stamp==authenticationGeneration,authenticated else {throw CancellationError()};return data
        }
    }
    private func invalidateSession() {
        authenticationGeneration=UUID();refreshTask=nil;session=nil;authenticated=false;currentUserID=nil
        pets=[];providedPhotos=[];blockedPets=[];moderationNotices=[];clearPrivateViews();clearPublicViews();uploads.clear()
        if sessionStorageEnabled {SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:sessionService,kSecAttrAccount as String:base] as CFDictionary)}
    }
    func perform(_ operation:() async throws->Void) async {
        #if DEBUG
        if uiReviewOnly {return}
        #endif
        guard !busy else {return};busy=true;error=nil
        do {try await operation()} catch is CancellationError {} catch let failure as URLError where failure.code == .cancelled {} catch {self.error=error.localizedDescription}
        busy=false
    }
    // A navigation refresh must wait for the disappearing view's cancelled
    // read to release busy. User submissions still use perform's double-tap guard.
    func performRefresh(_ operation:() async throws->Void) async {
        let actor=authenticationGeneration;let deadline=Date().addingTimeInterval(20)
        while busy {
            guard !Task.isCancelled,actor==authenticationGeneration,Date()<deadline else{return}
            do {try await Task.sleep(for:.milliseconds(25))} catch{return}
        }
        guard !Task.isCancelled,actor==authenticationGeneration else{return}
        await perform(operation)
    }
    func signIn(email:String,password:String) async throws {
        invalidateSession();sessionRefreshCount=0;let stamp=authenticationGeneration
        let data=try await request("/auth/v1/token?grant_type=password",body:["email":email,"password":password])
        var candidate=try JSONDecoder().decode(CloudSession.self,from:data)
        #if DEBUG && targetEnvironment(simulator)
        if isolated,ProcessInfo.processInfo.environment["MEFRION_TEST_EXPIRE_SESSION"]=="1" {candidate=CloudSession(access_token:candidate.access_token,refresh_token:candidate.refresh_token,expires_at:0)}
        #endif
        let userData=try await request("/auth/v1/user",token:candidate.access_token)
        let userObject=try JSONSerialization.jsonObject(with:userData) as? [String:Any]
        guard let userID=userObject?["id"] as? String else {throw Failure.invalid}
        guard stamp==authenticationGeneration else {throw CancellationError()}
        if sessionStorageEnabled {try saveSession(candidate)}
        try uploads.activate(actor:userID)
        session=candidate;currentUserID=userID;authenticated=true
        do {try await loadPets()} catch {invalidateSession();throw error}
        if let email=userObject?["email"] as? String {try? await completePendingFirstPet(email:email)}
    }
    private func adoptAuth(_ data:Data,validatedUserData:Data?=nil) async throws {
        let stamp=authenticationGeneration
        let candidate=try JSONDecoder().decode(CloudSession.self,from:data)
        let userData:Data
        if let validatedUserData {userData=validatedUserData}
        else {userData=try await request("/auth/v1/user",token:candidate.access_token)}
        let userObject=try JSONSerialization.jsonObject(with:userData) as? [String:Any]
        guard let userID=userObject?["id"] as? String else {throw Failure.invalid}
        guard stamp==authenticationGeneration else {throw CancellationError()}
        if sessionStorageEnabled {try saveSession(candidate)}
        try uploads.activate(actor:userID)
        session=candidate;currentUserID=userID;authenticated=true
        do {try await loadPets()} catch {invalidateSession();throw error}
        if let email=userObject?["email"] as? String {try? await completePendingFirstPet(email:email)}
    }
    func signUp(email:String,password:String,confirmed:Bool) async throws->Bool {
        guard confirmed,password.count>=12 else {throw Failure.invalid}
        let data=try await request("/auth/v1/signup",body:["email":email,"password":password,"data":["adult_confirmation":true,"data_handling_confirmation":true]])
        // A previous registration attempt may have left a local Pet draft. This
        // registration flow never creates a Pet without the user's later choice.
        clearPendingFirstPet()
        if (try? JSONDecoder().decode(CloudSession.self,from:data)) != nil {try await adoptAuth(data);return true}
        return false
    }
    func sendRecovery(email:String) async throws { _=try await request("/auth/v1/recover",body:["email":email]) }
    func resendSignup(email:String) async throws { _=try await request("/auth/v1/resend",body:["email":email,"type":"signup"]) }
    func changePassword(_ password:String) async throws {
        guard password.count>=12 else {throw Failure.invalid}
        let active=try await usableSession()
        guard let url=URL(string:base+"/auth/v1/user") else {throw Failure.invalid}
        var req=URLRequest(url:url);req.httpMethod="PUT"
        req.setValue(key,forHTTPHeaderField:"apikey");req.setValue("Bearer "+active.access_token,forHTTPHeaderField:"Authorization");req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.httpBody=try JSONSerialization.data(withJSONObject:["password":password])
        let (_,response)=try await http.data(for:req)
        guard (response as? HTTPURLResponse)?.statusCode==200 else {throw Failure.denied}
        await signOut()
    }
    func retireAccount(key:UUID,expectedUser:String) async throws {
        guard currentUserID==expectedUser else {throw Failure.denied}
        struct Receipt:Decodable {let accepted:Bool;let state:String}
        let receipt:Receipt=try await rpc("request_retirement",["p_request_key":key.uuidString,"p_explicit":true,"p_expected_user":expectedUser])
        guard receipt.accepted else {throw Failure.denied}
        await signOut()
    }
    func verifyEmail(email:String,code:String,recovery:Bool) async throws {
        guard code.count>=6,code.count<=12,code.allSatisfy(\.isNumber) else {throw Failure.invalid}
        let data=try await request("/auth/v1/verify",body:["email":email,"token":code,"type":recovery ? "recovery" : "signup"])
        invalidateSession();try await adoptAuth(data)
        if !recovery {try? await completePendingFirstPet(email:email)}
    }
    static func pkceChallenge(_ verifier:String)->String {
        Data(SHA256.hash(data:Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
    }
    static func authCode(_ url:URL)->String? {
        guard url.scheme=="mefrion",url.host=="auth",url.fragment==nil,let items=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems,items.filter({$0.name=="code"}).count==1,let code=items.first(where:{$0.name=="code"})?.value,!code.isEmpty,code.count<=2048 else{return nil}
        return code
    }
    func oauthSignIn(provider:String) async throws {
        guard ["apple","google"].contains(provider) else {throw Failure.invalid}
        let data=try await request("/auth/v1/settings")
        let settings=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        guard (settings?["external"] as? [String:Any])?[provider] as? Bool == true else {throw Failure.providerUnavailable}
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else {throw Failure.network}
        let verifier=Data(bytes).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        var url=URLComponents(string:base+"/auth/v1/authorize")!
        url.queryItems=[URLQueryItem(name:"provider",value:provider),URLQueryItem(name:"redirect_to",value:"mefrion://auth"),URLQueryItem(name:"code_challenge",value:Self.pkceChallenge(verifier)),URLQueryItem(name:"code_challenge_method",value:"s256")]
        let callback=try await OAuthBrowserFlow.authenticate(url.url!)
        guard let code=Self.authCode(callback) else {throw Failure.invalid}
        let response=try await request("/auth/v1/token?grant_type=pkce",body:["auth_code":code,"code_verifier":verifier])
        invalidateSession();try await adoptAuth(response)
    }
    func restore() async {
        if let restoration {await restoration.value;return}
        let task=Task {await self.restoreSession()}
        restoration=task;await task.value;restoration=nil
    }
    private func restoreSession() async {
        #if DEBUG
        if uiReviewOnly {return}
        if isolated,ProcessInfo.processInfo.arguments.contains("--appstore-screenshots") {
            currentUserID="appstore-sample";authenticated=true
            pets=[CloudPet(id:"appstore-pet",name:"こむぎ",species:"dog",breed:"柴犬",introduction:"",role:"owner")]
            return
        }
        if isolated,ProcessInfo.processInfo.arguments.contains("--ui-album-fixture") {
            currentUserID="ui-album-fixture";authenticated=true
            pets=[CloudPet(id:"fixture-album-pet",name:"クッキー",species:"dog",breed:"トイ・プードル",introduction:"",role:"owner")]
            return
        }
        #endif
        guard !authenticated else {return}
        #if DEBUG && targetEnvironment(simulator)
        if isolated,let email=ProcessInfo.processInfo.environment["MEFRION_TEST_CLOUD_EMAIL"],let password=ProcessInfo.processInfo.environment["MEFRION_TEST_CLOUD_PASSWORD"] {
            await perform {try await self.signIn(email:email,password:password)};return
        }
        #endif
        guard sessionStorageEnabled,configured else {return}
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:sessionService,kSecAttrAccount as String:base,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var found:CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&found)==errSecSuccess,let data=found as? Data,let old=try? JSONDecoder().decode(CloudSession.self,from:data) else {return}
        let stamp=authenticationGeneration
        await perform {
            if !Self.needsSessionRefresh(expiresAt:old.expires_at,now:Date().timeIntervalSince1970) {
                let verifiedUser:Data?
                do {
                    verifiedUser=try await self.request("/auth/v1/user",token:old.access_token)
                } catch Failure.notAuthenticated {
                    // The server rejected the cached token; refresh it below.
                    verifiedUser=nil
                }
                if let verifiedUser {
                    guard stamp==self.authenticationGeneration else {throw CancellationError()}
                    try await self.adoptAuth(try JSONEncoder().encode(old),validatedUserData:verifiedUser)
                    return
                }
            }
            let data=try await self.request("/auth/v1/token?grant_type=refresh_token",body:["refresh_token":old.refresh_token])
            guard stamp==self.authenticationGeneration else {throw CancellationError()}
            do {try await self.adoptAuth(data)} catch {self.invalidateSession();throw error}
        }
    }
    private func saveSession(_ session:CloudSession) throws {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:sessionService,kSecAttrAccount as String:base]
        let attrs:[String:Any]=[kSecValueData as String:try JSONEncoder().encode(session),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update=SecItemUpdate(query as CFDictionary,attrs as CFDictionary)
        if update==errSecItemNotFound {let result=SecItemAdd(query.merging(attrs){_,b in b} as CFDictionary,nil);guard result==errSecSuccess else {throw Failure.network}}
        else if update != errSecSuccess {throw Failure.network}
    }
    func signOut() async {
        let previous=session
        invalidateSession();error=nil
        if sessionStorageEnabled {SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:sessionService,kSecAttrAccount as String:base] as CFDictionary)}
        if let previous {_=try? await request("/auth/v1/logout",body:[:],token:previous.access_token)}
    }
    func loadPets() async throws {
        #if DEBUG
        if isolated,ProcessInfo.processInfo.arguments.contains("--appstore-screenshots") {return}
        if isolated,ProcessInfo.processInfo.arguments.contains("--ui-album-fixture") {return}
        #endif
        pets=try await rpc("list_pets")
    }
    func loadMembers(pet:String) async throws {members=[];members=try await rpc("members",["p_pet":pet])}
    func setFamilyName(pet:String,name:String) async throws {let _:Bool=try await rpc("set_family_name",["p_pet":pet,"p_name":name]);try await loadMembers(pet:pet)}
    func removeMember(pet:String,user:String) async throws {let _:Bool=try await rpc("remove_member",["p_pet":pet,"p_user":user]);try await loadPets();if pets.contains(where:{$0.id==pet}) {try await loadMembers(pet:pet)} else {members=[];photos=[];images=[:]}}
    func createPet(name:String,species:String,breed:String) async throws { let _:CloudPet=try await rpc("create_pet",["p_name":name,"p_species":species,"p_breed":breed]);try await loadPets() }
    private var pendingFirstPetQuery:[String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:sessionService+".pending-first-pet",kSecAttrAccount as String:base]
    }
    func rememberPendingFirstPet(email:String,name:String,species:String,breed:String) throws {
        guard sessionStorageEnabled else{return}
        let draft=PendingFirstPet(email:email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased(),name:name,species:species,breed:breed)
        let attrs:[String:Any]=[kSecValueData as String:try JSONEncoder().encode(draft),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status=SecItemUpdate(pendingFirstPetQuery as CFDictionary,attrs as CFDictionary)
        if status==errSecItemNotFound {
            guard SecItemAdd(pendingFirstPetQuery.merging(attrs){_,value in value} as CFDictionary,nil)==errSecSuccess else {throw Failure.network}
        } else if status != errSecSuccess {throw Failure.network}
    }
    func clearPendingFirstPet() {SecItemDelete(pendingFirstPetQuery as CFDictionary)}
    private func completePendingFirstPet(email:String) async throws {
        guard sessionStorageEnabled,authenticated else{return}
        var found:CFTypeRef?
        let query=pendingFirstPetQuery.merging([kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]){_,value in value}
        guard SecItemCopyMatching(query as CFDictionary,&found)==errSecSuccess,
              let data=found as? Data,let draft=try? JSONDecoder().decode(PendingFirstPet.self,from:data),
              draft.email==email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() else{return}
        if !pets.isEmpty {clearPendingFirstPet();return}
        try await setSocialName(draft.name)
        try await createPet(name:draft.name,species:draft.species,breed:draft.breed)
        clearPendingFirstPet()
    }
    func updatePet(_ pet:CloudPet,name:String,breed:String,introduction:String,details:[String:String],publicFields:[String]) async throws {
        let _:Bool=try await rpc("update_pet",["p_pet":pet.id,"p_name":name,"p_breed":breed,"p_introduction":introduction,"p_details":details,"p_public_fields":publicFields]);clearPublicViews();try await loadPets()
    }
    func editPhoto(_ photo:CloudPhoto,pet:String,captured:String?,title:String,kind:String?,note:String) async throws {
        let _:Bool=try await rpc("edit_photo",["p_photo":photo.id,"p_captured":captured as Any? ?? NSNull(),"p_title":title,"p_event_kind":kind as Any? ?? NSNull(),"p_note":note]);try await loadAlbum(pet:pet)
    }
    func events(pet:String) async throws->[CloudEvent] {try await rpc("events",["p_pet":pet])}
    func saveEvent(pet:String,key:UUID,captured:String?,title:String,kind:String,note:String) async throws {
        let _:String=try await rpc("save_event",["p_pet":pet,"p_key":key.uuidString,"p_captured":captured as Any? ?? NSNull(),"p_title":title,"p_kind":kind,"p_note":note])
    }
    func editEvent(_ event:String,captured:String?,title:String,kind:String,note:String) async throws {let _:Bool=try await rpc("edit_event",["p_event":event,"p_captured":captured as Any? ?? NSNull(),"p_title":title,"p_kind":kind,"p_note":note])}
    func shareCard(id:String,key:UUID) async throws->CloudPublication {try await rpc("share_card",["p_card":id,"p_key":key.uuidString,"p_explicit":true])}
    func deleteEvent(_ event:String) async throws {let _:Bool=try await rpc("delete_event",["p_event":event])}
    func petNotifications(pet:String) async throws->CloudPetNotifications {try await rpc("get_pet_notifications",["p_pet":pet])}
    func savePetNotifications(pet:String,frequency:String,milestones:Bool,paused:String?) async throws {
        let _:Bool=try await rpc("pet_notifications",["p_pet":pet,"p_frequency":frequency,"p_milestones":milestones,"p_paused_until":paused as Any? ?? NSNull()])
    }
    func cards(pet:String) async throws->[CloudCard] {
        #if DEBUG
        if isolated,ProcessInfo.processInfo.arguments.contains("--ui-album-fixture") {return albumFixtureCards}
        #endif
        return try await rpc("cards",["p_pet":pet])
    }
    func albumGestures(pet:String) async throws->[CloudAlbumGesture] {
        #if DEBUG
        if isolated,ProcessInfo.processInfo.arguments.contains("--ui-album-fixture") {return albumFixtureGestures}
        #endif
        return try await rpc("album_gestures",["p_pet":pet])
    }
    func setAlbumGesture(pet:String,photo:String,gesture:String,enabled:Bool) async throws {
        #if DEBUG
        if isolated,ProcessInfo.processInfo.arguments.contains("--ui-album-fixture") {
            albumFixtureGestures.removeAll {$0.photo_id==photo && $0.gesture==gesture}
            if enabled {albumFixtureGestures.insert(CloudAlbumGesture(photo_id:photo,gesture:gesture),at:0)}
            return
        }
        #endif
        let _:Bool=try await rpc("set_album_gesture",["p_pet":pet,"p_photo":photo,"p_gesture":gesture,"p_enabled":enabled])
    }
    func saveCard(pet:String,first:String,second:String,text:String,zooms:[Double],xs:[Double],ys:[Double],key:UUID) async throws->String {
        #if DEBUG
        if isolated,ProcessInfo.processInfo.arguments.contains("--ui-album-fixture") {
            let id=UUID().uuidString
            albumFixtureCards.insert(CloudCard(id:id,first:first,second:second,layout:CloudCardLayout(text:text,first_zoom:zooms[0],first_x:xs[0],first_y:ys[0],second_zoom:zooms[1],second_x:xs[1],second_y:ys[1]),mine:true),at:0)
            return id
        }
        #endif
        return try await rpc("save_card",["p_pet":pet,"p_first":first,"p_second":second,"p_key":key.uuidString,"p_layout":["text":text,"first_zoom":zooms[0],"first_x":xs[0],"first_y":ys[0],"second_zoom":zooms[1],"second_x":xs[1],"second_y":ys[1]]])
    }
    func authorizeCardExport(id:String) async throws {let _:Bool=try await rpc("authorize_card_export",["p_card":id,"p_explicit":true])}
    func deleteCard(id:String) async throws {let _:Bool=try await rpc("delete_card",["p_card":id])}
    func familyActivity(pet:String) async throws->[CloudFamilyActivity] {try await rpc("family_activity",["p_pet":pet])}
    func familyNew(pet:String) async throws->Int {try await rpc("family_new",["p_pet":pet])}
    func markFamilyRead(pet:String) async throws {let _:Bool=try await rpc("mark_family_read",["p_pet":pet])}
    func invite(pet:String) async throws { invitation=try await rpc("invite",["p_pet":pet]) }
    func cancelInvite() async throws { if let invitation {let _:Bool=try await rpc("revoke_invite",["p_invite":invitation.id]);self.invitation=nil} }
    func accept(token:String,confirmed:Bool) async throws { let _:AcceptResult=try await rpc("accept_invite",["p_token":token,"p_confirm_scope":confirmed]);try await loadPets() }
    private struct AcceptResult:Decodable {let pet_id:String}
    func albumPhotos(pet:String) async throws->[CloudPhoto] {
        #if DEBUG
        if isolated,ProcessInfo.processInfo.arguments.contains("--appstore-screenshots") {
            return [CloudPhoto(id:"appstore-album-one",path:"",captured:"2026-10-20",title:"ひなたぼっこ",mine:true,created_at:"2026-10-20T00:00:00Z"),
                    CloudPhoto(id:"appstore-album-two",path:"",captured:"2025-10-20",title:"あの頃のこむぎ",mine:true,created_at:"2025-10-20T00:00:00Z")]
        }
        if isolated,ProcessInfo.processInfo.arguments.contains("--ui-album-fixture") {
            try await Task.sleep(for:.milliseconds(550))
            return [CloudPhoto(id:"fixture-album-photo",path:"",captured:"2026-10-20",title:"おひるね",mine:true,created_at:"2026-10-20T00:00:00Z"),
                    CloudPhoto(id:"fixture-album-old",path:"",captured:"2023-10-20",title:"はじめてのおすわり",mine:true,created_at:"2023-10-20T00:00:00Z")]
        }
        #endif
        let records:[CloudPhoto]=try await rpc("album",["p_pet":pet])
        // A read-receipt failure must not hide photos that the server already returned.
        try? await markFamilyRead(pet:pet)
        return records
    }
    func loadAlbum(pet:String) async throws {
        photos=[];images=[:]
        let stamp=privacyGeneration
        let records:[CloudPhoto]=try await rpc("album",["p_pet":pet])
        var loaded:[String:UIImage]=[:]
        for photo in records {
            let data=try await authenticatedRequest("/functions/v1/private-image?photo="+photo.id)
            guard let image=UIImage(data:data) else {throw Failure.invalid};loaded[photo.id]=image
        }
        guard stamp==privacyGeneration,authenticated else {throw CancellationError()}
        photos=records;images=loaded
        try await markFamilyRead(pet:pet)
    }
    func privatePhotoForDeviceSave(_ id:String) async throws->UIImage {
        #if DEBUG
        if isolated,ProcessInfo.processInfo.arguments.contains("--appstore-screenshots") {
            let asset=id=="appstore-album-two" ? "appstore-dog-two" : "appstore-dog-one"
            if let image=UIImage(named:asset) {return image}
        }
        if isolated,ProcessInfo.processInfo.arguments.contains("--ui-album-fixture"),["fixture-album-photo","fixture-album-old"].contains(id),let image=UIImage(named:id=="fixture-album-old" ? "pet-1" : "pet-0") {return image}
        #endif
        let stamp=privacyGeneration;let actor=currentUserID
        let data=try await authenticatedRequest("/functions/v1/private-image?photo="+id)
        guard stamp==privacyGeneration,authenticated,actor==currentUserID,let image=UIImage(data:data) else {throw CancellationError()}
        return image
    }
    func videoFile(_ id:String,privateMedia:Bool) async throws->URL {
        guard UUID(uuidString:id) != nil else {throw Failure.invalid}
        if !privateMedia {
            if let file=publicVideoFiles[id],FileManager.default.fileExists(atPath:file.path) {
                publicVideoOrder.removeAll(where:{$0==id});publicVideoOrder.append(id)
                return file
            }
            if let task=publicVideoLoads[id] {
                let generation=publicVideoGeneration
                let file=try await task.value
                guard generation==publicVideoGeneration else {throw CancellationError()}
                return file
            }
            let generation=publicVideoGeneration
            let task=Task {try await self.downloadVideo(id,privateMedia:false)}
            publicVideoLoads[id]=task
            do {
                let file=try await task.value
                guard generation==publicVideoGeneration else {try? FileManager.default.removeItem(at:file);throw CancellationError()}
                publicVideoLoads[id]=nil
                guard !Task.isCancelled else {try? FileManager.default.removeItem(at:file);throw CancellationError()}
                publicVideoFiles[id]=file;publicVideoOrder.removeAll(where:{$0==id});publicVideoOrder.append(id)
                trimPublicVideoCache()
                return file
            } catch {if generation==publicVideoGeneration {publicVideoLoads[id]=nil};throw error}
        }
        return try await downloadVideo(id,privateMedia:true)
    }
    private func downloadVideo(_ id:String,privateMedia:Bool) async throws->URL {
        let path=privateMedia ? "/functions/v1/private-video?photo="+id : "/functions/v1/public-image?media="+id+"&format=video"
        let data:Data
        if privateMedia || authenticated {data=try await authenticatedRequest(path)}
        else {data=try await request(path)}
        guard !data.isEmpty,data.count<=50*1024*1024,data.count>8,data[4..<8].elementsEqual("ftyp".utf8) else {throw Failure.invalid}
        let output=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
        try data.write(to:output,options:[.atomic,.completeFileProtection])
        return output
    }
    private func trimPublicVideoCache() {
        var bytes=publicVideoOrder.reduce(0) {total,id in
            total+(publicVideoFiles[id].flatMap {try? FileManager.default.attributesOfItem(atPath:$0.path)[.size] as? Int} ?? 0)
        }
        while publicVideoOrder.count>12 || bytes>250*1024*1024 {
            guard let id=publicVideoOrder.first(where:{visiblePublicVideos[$0,default:0]==0}) else {break}
            publicVideoOrder.removeAll(where:{$0==id})
            guard let file=publicVideoFiles.removeValue(forKey:id) else {continue}
            bytes-=((try? FileManager.default.attributesOfItem(atPath:file.path)[.size] as? Int) ?? 0)
            try? FileManager.default.removeItem(at:file)
        }
    }
    func setPublicVideoVisible(_ id:String,_ visible:Bool) {
        if visible {visiblePublicVideos[id,default:0]+=1}
        else {let count=visiblePublicVideos[id,default:0];if count<=1 {visiblePublicVideos[id]=nil} else {visiblePublicVideos[id]=count-1};purgeRetiredPublicVideos();trimPublicVideoCache()}
    }
    private func purgeRetiredPublicVideos() {
        let retained=Set(publicPosts.flatMap{$0.video_media ?? []})
        for id in publicVideoOrder where !retained.contains(id) && visiblePublicVideos[id,default:0]==0 {
            if let file=publicVideoFiles.removeValue(forKey:id) {try? FileManager.default.removeItem(at:file)}
        }
        publicVideoOrder.removeAll(where:{publicVideoFiles[$0]==nil})
    }
    func prefetchPublicVideos(after postID:String) {
        guard let index=publicPosts.firstIndex(where:{$0.id==postID}),index>publicVideoPrefetchAnchor else{return}
        publicVideoPrefetchAnchor=index
        let ids=publicPosts.dropFirst(index).prefix(11).flatMap{$0.video_media ?? []}.prefix(10)
        let pending=ids.filter {publicVideoFiles[$0]==nil && publicVideoLoads[$0]==nil && !publicVideoPrefetchQueue.contains($0)}
        publicVideoPrefetchQueue=Array(pending)
        startPublicVideoPrefetch()
    }
    private func startPublicVideoPrefetch() {
        while publicVideoPrefetchWorkers<2 && !publicVideoPrefetchQueue.isEmpty {
            publicVideoPrefetchWorkers+=1
            Task {
                defer {publicVideoPrefetchWorkers-=1;startPublicVideoPrefetch()}
                while !publicVideoPrefetchQueue.isEmpty {
                    let id=publicVideoPrefetchQueue.removeFirst()
                    if publicVideoFiles[id]==nil { _=try? await videoFile(id,privateMedia:false) }
                }
            }
        }
    }
    func upload(pet:String,image:UIImage,captured:String?) async throws {
        guard let jpeg=image.jpegData(compressionQuality:0.9) else {throw Failure.invalid}
        try uploads.append([CloudUploadDraft(pet:pet,jpeg:jpeg,captured:captured)])
        try await sendUploads(pet:pet)
    }
    func sendUploads(pet:String,reloadAlbum:Bool=true) async throws {
        await uploads.send(pet:pet) {try await self.uploadDraft($0)}
        if reloadAlbum {try await loadAlbum(pet:pet)}
    }
    func uploadForPublication(_ drafts:[CloudUploadDraft],pet:String) async throws->[String] {
        guard !drafts.isEmpty,drafts.count<=10,drafts.allSatisfy({$0.pet==pet}) else {throw Failure.invalid}
        var resolved:[CloudUploadDraft]=[],additions:[CloudUploadDraft]=[]
        for draft in drafts {
            if let pending=uploads.pendingMatch(for:draft) ?? additions.first(where:{$0.pet==draft.pet && $0.fingerprint==draft.fingerprint}) {
                resolved.append(pending)
            } else {
                var newDraft=draft
                newDraft.duplicateApproved=true
                additions.append(newDraft);resolved.append(newDraft)
            }
        }
        if !additions.isEmpty {try uploads.append(additions)}
        try uploads.allowPublicationRetry(ids:Set(resolved.map(\.id)))
        try await sendUploads(pet:pet,reloadAlbum:false)
        if let failed=uploads.drafts.first(where:{resolved.map(\.id).contains($0.id) && $0.state == .failed}) {
            throw CloudPublicationUploadError(detail:failed.message ?? "通信を確認してください。")
        }
        var ids:[String]=[]
        for draft in resolved {
            let reservation:PhotoReservation=try await rpc("begin_photo",["p_pet":pet,"p_request_key":draft.id.uuidString,"p_captured":NSNull(),"p_title":""])
            guard reservation.state=="ready" else {throw Failure.network}
            ids.append(reservation.id)
        }
        return ids
    }
    func uploadVideo(pet:String,url:URL,poster:UIImage,duration:Double,id:UUID) async throws->String {
        guard duration>0,duration<=300,let posterBytes=poster.jpegData(compressionQuality:0.78) else {throw Failure.invalid}
        try await PetPostValidator.shared.validateVideo(url,duration:duration)
        let reservation:PhotoReservation=try await rpc("begin_video",["p_pet":pet,"p_request_key":id.uuidString,"p_duration":duration])
        guard let preview=reservation.preview_path else {throw Failure.invalid}
        if reservation.state != "ready" {
            let bytes=try Data(contentsOf:url,options:.mappedIfSafe)
            guard bytes.count<=49*1024*1024 else {throw Failure.invalid}
            _=try await authenticatedRequest("/storage/v1/object/family-originals/"+reservation.path,raw:bytes,contentType:"video/mp4")
            _=try await authenticatedRequest("/storage/v1/object/family-originals/"+preview,raw:try CloudPhotoCodec.encode(posterBytes))
            let _:Bool=try await rpc("finish_video",["p_photo":reservation.id])
        }
        return reservation.id
    }
    func setAlbumVisibility(photo:String,visible:Bool) async throws {
        let _:Bool=try await rpc("set_album_visibility",["p_photo":photo,"p_visible":visible])
    }
    func ownPostVideoSource(_ post:String) async throws->String? {
        try await rpc("own_post_video_source",["p_post":post])
    }
    private func uploadDraft(_ draft:CloudUploadDraft) async throws {
        try await PetPostValidator.shared.validatePhoto(draft.jpeg)
        let reservation:PhotoReservation=try await rpc("begin_photo",["p_pet":draft.pet,"p_request_key":draft.id.uuidString,"p_captured":draft.captured as Any? ?? NSNull(),"p_title":""])
        if reservation.state=="ready" {return}
        let duplicates:[String]=try await rpc("record_fingerprint",["p_photo":reservation.id,"p_fingerprint":draft.fingerprint])
        if !duplicates.isEmpty && !draft.duplicateApproved {throw CloudUploadQueue.Validation.duplicate}
        _=try await authenticatedRequest("/storage/v1/object/family-originals/"+reservation.path,raw:draft.jpeg)
        let _:Bool=try await rpc("finish_photo",["p_photo":reservation.id])
    }
    func consent(photo:String,purpose:String,allowed:Bool) async throws {let _:Int=try await rpc("consent",["p_photo":photo,"p_purpose":purpose,"p_allowed":allowed]);if !allowed {clearPublicViews()}}
    func loadProvidedPhotos() async throws {providedPhotos=[];providedPhotos=try await rpc("provided_photos")}
    func setPublicProfile(pet:String,enabled:Bool,explicit:Bool=false) async throws {let _:Bool=try await rpc("set_public_profile",["p_pet":pet,"p_enabled":enabled,"p_explicit":explicit]);if !enabled {clearPublicViews()}}
    func requestPublication(pet:String,photos:[String],body:String,key:UUID,tags:[String]=[]) async throws->CloudPublication {
        try await rpc("request_tagged_publication",["p_pet":pet,"p_photos":photos,"p_tags":Array(Set(tags+[pet])).sorted(),"p_body":body,"p_request_key":key.uuidString,"p_explicit":true])
    }
    func stopPublication(id:String) async throws {let _:Bool=try await rpc("stop_publication",["p_post":id]);clearPublicViews()}
    private struct FeedPage:Decodable {let items:[CloudPublicPost];let next_date:String?;let next_id:String?;let valid_known_ids:[String]}
    static func recommendedOrder(_ posts:[CloudPublicPost],impressions:[String:Int],seed:UInt64)->[CloudPublicPost] {
        func tieBreak(_ id:String)->UInt64 {
            var value:UInt64=14_695_981_039_346_656_037 ^ seed
            for byte in id.utf8 {value=(value ^ UInt64(byte)) &* 1_099_511_628_211}
            return value
        }
        let ranked=posts.enumerated().sorted {left,right in
            let leftSeen=impressions[left.element.id,default:0],rightSeen=impressions[right.element.id,default:0]
            if leftSeen != rightSeen {return leftSeen<rightSeen}
            let leftRecency=left.offset/12,rightRecency=right.offset/12
            if leftRecency != rightRecency {return leftRecency<rightRecency}
            return tieBreak(left.element.id)<tieBreak(right.element.id)
        }.map(\.element)
        var remaining=ranked,ordered:[CloudPublicPost]=[]
        while !remaining.isEmpty {
            let alternate=ordered.last.flatMap {last in remaining.prefix(8).firstIndex(where:{$0.species != last.species})}
            ordered.append(remaining.remove(at:alternate ?? 0))
        }
        return ordered
    }
    func loadPublicFeed(mode:String?=nil,query:String?=nil,species:String?=nil,append:Bool=false,rotateRecommendations:Bool=false) async throws {
        // An append based on an old cursor must not race a fresh feed validation.
        // Whichever request finished last could otherwise replace the visible rows.
        if append && publicFeedRevalidating {return}
        let oldSelection=(feedMode,feedQuery,feedSpecies)
        if let mode {feedMode=mode};if let query {feedQuery=query};if let species {feedSpecies=species}
        let recommended=feedMode=="all" && feedQuery.isEmpty && feedSpecies=="all"
        #if DEBUG
        if isolated,ProcessInfo.processInfo.arguments.contains("--appstore-screenshots") {
            if append {return}
            let samples:[(String,String,String,String,String)]=[
                ("こむぎ","dog","柴犬","appstore-dog-one","窓辺でのんびり。今日もいい日 🐾  Photo: Valeria Boltneva / Pexels"),
                ("つむぎ","cat","","appstore-cat-one","ふわっとお昼寝の時間 ♡  Photo: Pexels"),
                ("すず","dog","チワワ","appstore-dog-two","おさんぽ日和 🌷  Photo: Pexels")]
            publicPosts=samples.enumerated().map {index,item in
                CloudPublicPost(id:"appstore-post-\(index)",pet_id:"appstore-pet-\(index)",name:item.0,species:item.1,breed:item.2,body:item.4,kind:"post",media:["appstore-media-\(index)"],likes:[38,24,17][index],comments:[4,2,1][index],liked:false,saved:false,following:false,published_at:"2026-10-21T12:00:00Z")
            }
            publicImages=Dictionary(uniqueKeysWithValues:samples.enumerated().compactMap {index,item in
                UIImage(named:item.3).map {("appstore-media-\(index)",$0)}
            })
            hasMorePublicPosts=false
            return
        }
        if isolated,ProcessInfo.processInfo.arguments.contains("--ui-feed-fixture") {
            if append {return}
            feedFixtureRevision+=1
            hasMorePublicPosts=false
            let revision=feedFixtureRevision
            let fixtures=(0..<20).map {index in
                CloudPublicPost(id:"fixture-post-\(index)",pet_id:"fixture-pet-\(index)",name:"テスト犬 \(index+1)・\(revision)",species:"dog",breed:"犬",body:"公開フィードのスクロール確認",kind:"post",media:["fixture-media-\(index)","fixture-media-\(index)-2"],likes:0,comments:0,liked:false,saved:false,following:false)
            }
            publicPosts=Self.recommendedOrder(fixtures,impressions:recommendationImpressions,seed:UInt64(revision))
            for post in publicPosts.prefix(12) {recommendationImpressions[post.id,default:0]+=1}
            var fixtureImages:[String:UIImage]=[:]
            var fixtureCompressed:[String:Data]=[:]
            for index in 0..<20 {
                if let image=UIImage(named:"pet-\(index % 4)"),let bytes=image.jpegData(compressionQuality:0.75) {
                    for media in ["fixture-media-\(index)","fixture-media-\(index)-2"] {
                        fixtureCompressed[media]=bytes
                        if index<2 {fixtureImages[media]=image}
                    }
                }
            }
            publicImages=fixtureImages
            publicCompressedImages=fixtureCompressed
            publicCompressedOrder=(0..<20).flatMap{["fixture-media-\($0)","fixture-media-\($0)-2"]}
            return
        }
        #endif
        // Keep the current screen intact while the RPC is in flight. A cancelled
        // pull-to-refresh must not erase the verified feed or its photos.
        let previous=publicPosts
        let oldImages=publicImages
        let oldCompressed=publicCompressedImages
        if !append {
            publicGeneration=UUID();publicFeedRevalidating=true
            publicImageTask?.cancel();publicImageTask=nil
            initialQueuedPublicMedia=[];publicPrefetchQueue=[];publicPrefetchWorkers=0;publicPrefetchAnchor = -1
            publicVideoPrefetchQueue=[];publicVideoPrefetchAnchor = -1
            inFlightPublicMedia=[]
        }
        guard !append || hasMorePublicPosts else{return}
        let stamp=publicGeneration,signedIn=authenticated
        // A fresh page only needs validation for cached covers on that page.
        // Appends still validate all retained rows so withdrawn posts disappear.
        let knownIDs=append ? previous.map(\.id) : Array(previous.prefix(recommended ? 50 : 30)).map(\.id)
        var body:[String:Any]=["p_limit":recommended ? 50 : 30,"p_mode":feedMode,"p_query":feedQuery,"p_species":feedSpecies,"p_known_ids":knownIDs]
        if append,let date=nextFeedDate,let id=nextFeedID {body["p_before"]=date;body["p_before_id"]=id}
        let page:FeedPage
        do {
            #if DEBUG
            let requestStarted=Date()
            #endif
            let data = signedIn ? try await authenticatedRequest("/rest/v1/rpc/mefrion_feed_page",body:body) : try await request("/rest/v1/rpc/mefrion_feed_page",body:body)
            page=try JSONDecoder().decode(FeedPage.self,from:data)
            #if DEBUG
            Self.feedLogger.info("metadata_ms=\(Int(Date().timeIntervalSince(requestStarted)*1000)) items=\(page.items.count) append=\(append)")
            #endif
        } catch {
            if !append && stamp==publicGeneration {
                publicFeedRevalidating=false
                for media in visiblePublicMedia where publicImages[media]==nil {ensurePublicImage(media)}
            }
            throw error
        }
        let valid=Set(page.valid_known_ids),retained=append ? previous.filter{valid.contains($0.id)} : []
        guard stamp==publicGeneration else {throw CancellationError()}
        if append && page.items.isEmpty && retained.count==previous.count {
            // Reaching the end must not replace all 50 visible cells with an
            // equivalent array; LazyVStack can readjust its content offset.
            nextFeedDate=nil;nextFeedID=nil;hasMorePublicPosts=false
            return
        }
        let ids=Set(retained.map(\.id));var posts=retained+page.items.filter{!ids.contains($0.id)}
        if recommended && !append {
            if rotateRecommendations || previous.isEmpty || oldSelection.0 != feedMode || oldSelection.1 != feedQuery || oldSelection.2 != feedSpecies {
                posts=Self.recommendedOrder(posts,impressions:recommendationImpressions,seed:UInt64.random(in:UInt64.min...UInt64.max))
                for post in posts.prefix(12) {recommendationImpressions[post.id,default:0]+=1}
            } else {
                let previousRanks=Dictionary(uniqueKeysWithValues:previous.enumerated().map{($0.element.id,$0.offset)})
                let serverRanks=Dictionary(uniqueKeysWithValues:posts.enumerated().map{($0.element.id,$0.offset)})
                posts.sort {left,right in
                    let oldLeft=previousRanks[left.id],oldRight=previousRanks[right.id]
                    if oldLeft==nil && oldRight != nil {return true}
                    if oldLeft != nil && oldRight==nil {return false}
                    if let oldLeft,let oldRight {return oldLeft<oldRight}
                    return serverRanks[left.id,default:0]<serverRanks[right.id,default:0]
                }
            }
            let currentIDs=Set(posts.map(\.id))
            recommendationImpressions=recommendationImpressions.filter {currentIDs.contains($0.key)}
        }
        if !append {publicImageTask?.cancel()}
        var retainedImages:[String:UIImage]=[:]
        var retainedCompressed:[String:Data]=[:]
        for post in posts where valid.contains(post.id) {
            for media in post.media {
                if let image=oldImages[media] {retainedImages[media]=image}
                if let bytes=oldCompressed[media] {retainedCompressed[media]=bytes}
            }
        }
        publicFeedRevalidating=false
        publicPosts=posts;publicImages=retainedImages;publicImageOrder=posts.flatMap(\.media).filter{retainedImages[$0] != nil};publicCompressedImages=retainedCompressed;publicCompressedOrder=posts.flatMap(\.media).filter{retainedCompressed[$0] != nil};failedPublicImages=[];nextFeedDate=page.next_date;nextFeedID=page.next_id;hasMorePublicPosts=page.next_id != nil && posts.count<500
        purgeRetiredPublicVideos()
        var seen=Set<String>()
        // Only prefetch the next dozen covers. The rest load as they enter view;
        // fetching every carousel photo on a 30-post page wastes bandwidth.
        let visibleMedia=posts.flatMap(\.media).filter{visiblePublicMedia.contains($0)}
        let orderedMedia=posts.prefix(12).compactMap(\.media.first)+visibleMedia
        for media in visibleMedia where retainedImages[media]==nil && retainedCompressed[media] != nil {ensurePublicImage(media)}
        let missing=orderedMedia.filter {seen.insert($0).inserted && retainedImages[$0]==nil && retainedCompressed[$0]==nil}
        initialQueuedPublicMedia=Set(missing)
        if !missing.isEmpty {publicImageTask=Task {await loadPublicFeedImages(missing,signedIn:signedIn,generation:stamp)}}
        if let first=posts.first {prefetchPublicVideos(after:first.id)}
    }
    /// LazyVStack reports a row shortly before it is drawn. Keep a small,
    /// bounded window farther ahead so the next photos are usually ready.
    func prefetchPublicImages(after postID:String) {
        guard !publicFeedRevalidating,let index=publicPosts.firstIndex(where:{$0.id==postID}),index>publicPrefetchAnchor else{return}
        publicPrefetchAnchor=index
        let start=index+1,end=min(publicPosts.count,start+8)
        guard start<end else{return}
        let candidates=publicPosts[start..<end].compactMap(\.media.first)
        publicPrefetchQueue=candidates.filter {media in
            publicImages[media]==nil && !failedPublicImages.contains(media) && !inFlightPublicMedia.contains(media) && !initialQueuedPublicMedia.contains(media)
        }
        startPublicPrefetchWorkers()
    }
    private func startPublicPrefetchWorkers() {
        let stamp=publicGeneration
        while publicPrefetchWorkers<2 && !publicPrefetchQueue.isEmpty {
            publicPrefetchWorkers+=1
            Task {await drainPublicPrefetch(generation:stamp)}
        }
    }
    private func drainPublicPrefetch(generation:UUID) async {
        defer {
            if generation==publicGeneration {
                publicPrefetchWorkers-=1
                startPublicPrefetchWorkers()
            }
        }
        while generation==publicGeneration && !Task.isCancelled && !publicFeedRevalidating && !publicPrefetchQueue.isEmpty {
            let media=publicPrefetchQueue.removeFirst()
            guard publicImages[media]==nil,!failedPublicImages.contains(media),!inFlightPublicMedia.contains(media),
                  !initialQueuedPublicMedia.contains(media),publicPosts.contains(where:{$0.media.contains(media)}) else {continue}
            inFlightPublicMedia.insert(media)
            let payload:FeedImagePayload?
            if let bytes=publicCompressedImages[media] {
                let image=await Task.detached(priority:.utility) {Self.decodedFeedImage(bytes)}.value
                payload=image.map {FeedImagePayload(image:$0,compressed:bytes)}
            } else {payload=await fetchPublicImage(media,signedIn:authenticated)}
            guard generation==publicGeneration else{return}
            inFlightPublicMedia.remove(media)
            guard publicPosts.contains(where:{$0.media.contains(media)}) else{continue}
            if let payload {rememberPublicImage(payload.image,media:media,compressed:payload.compressed)}
            else {failedPublicImages.insert(media)}
        }
    }
    func setPublicImageVisible(_ media:String,_ visible:Bool) {
        if visible {visiblePublicMedia.insert(media);ensurePublicImage(media)}
        else {visiblePublicMedia.remove(media);prunePublicImages()}
    }
    private func ensurePublicImage(_ media:String) {
        guard !publicFeedRevalidating,publicImages[media]==nil,!failedPublicImages.contains(media),!inFlightPublicMedia.contains(media),
              publicPosts.contains(where:{$0.media.contains(media)}) else{return}
        publicPrefetchQueue.removeAll(where:{$0==media})
        let stamp=publicGeneration,signedIn=authenticated
        inFlightPublicMedia.insert(media)
        if let bytes=publicCompressedImages[media] {
            Task {
                let image=await Task.detached(priority:.userInitiated) {Self.decodedFeedImage(bytes)}.value
                guard stamp==publicGeneration else {return}
                inFlightPublicMedia.remove(media)
                guard publicPosts.contains(where:{$0.media.contains(media)}) else {return}
                if let image {rememberPublicImage(image,media:media)}
                else {
                    publicCompressedImages.removeValue(forKey:media)
                    publicCompressedOrder.removeAll(where:{$0==media})
                    ensurePublicImage(media)
                }
            }
            return
        }
        Task {
            let payload=await fetchPublicImage(media,signedIn:signedIn)
            guard stamp==publicGeneration else{return}
            inFlightPublicMedia.remove(media)
            guard publicPosts.contains(where:{$0.media.contains(media)}) else{return}
            if let payload {rememberPublicImage(payload.image,media:media,compressed:payload.compressed)}
            else {failedPublicImages.insert(media)}
        }
    }
    private func rememberPublicImage(_ image:UIImage,media:String,compressed:Data?=nil) {
        publicImages[media]=image
        publicImageOrder.removeAll(where:{$0==media});publicImageOrder.append(media)
        if let compressed,compressed.count<=2_000_000 {
            publicCompressedImages[media]=compressed
            publicCompressedOrder.removeAll(where:{$0==media});publicCompressedOrder.append(media)
        } else if publicCompressedImages[media] != nil {
            publicCompressedOrder.removeAll(where:{$0==media});publicCompressedOrder.append(media)
        }
        while publicCompressedImages.count>96 || publicCompressedImages.values.reduce(0,{$0+$1.count})>24_000_000 {
            guard let oldest=publicCompressedOrder.first(where:{!visiblePublicMedia.contains($0)}) ?? publicCompressedOrder.first else {break}
            publicCompressedOrder.removeAll(where:{$0==oldest});publicCompressedImages.removeValue(forKey:oldest)
        }
        prunePublicImages()
    }
    private func prunePublicImages() {
        while publicImages.count>24,let oldest=publicImageOrder.first(where:{!visiblePublicMedia.contains($0)}) {
            publicImageOrder.removeAll(where:{$0==oldest});publicImages.removeValue(forKey:oldest)
        }
    }
    private nonisolated static func decodedFeedImage(_ bytes:Data)->UIImage? {
        guard let source=CGImageSourceCreateWithData(bytes as CFData,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceThumbnailMaxPixelSize:1600,
                kCGImageSourceShouldCacheImmediately:true
              ] as CFDictionary) else {return nil}
        return UIImage(cgImage:image)
    }
    private struct FeedImagePayload {let image:UIImage;let compressed:Data}
    private func fetchPublicImage(_ media:String,signedIn:Bool) async->FeedImagePayload? {
        #if DEBUG
        let requestStarted=Date()
        #endif
        let path="/functions/v1/public-image?media="+media
        let bytes=try? await (signedIn ? authenticatedRequest(path) : request(path))
        #if DEBUG
        let transferMS=Int(Date().timeIntervalSince(requestStarted)*1000)
        #endif
        let image=await Task.detached(priority:.userInitiated) {bytes.flatMap(Self.decodedFeedImage)}.value
        #if DEBUG
        Self.feedLogger.info("photo_network_ms=\(transferMS) photo_total_ms=\(Int(Date().timeIntervalSince(requestStarted)*1000)) ok=\(image != nil)")
        #endif
        guard let image,let bytes else {return nil}
        return FeedImagePayload(image:image,compressed:bytes)
    }
    private func loadPublicFeedImages(_ mediaIDs:[String],signedIn:Bool,generation:UUID) async {
        defer {if generation==publicGeneration {initialQueuedPublicMedia=[]}}
        // Fill the six-request window immediately. The old 60 ms stagger
        // delayed every image after the first, even on a fast connection.
        let queue=mediaIDs.filter{!inFlightPublicMedia.contains($0) && publicImages[$0]==nil && publicCompressedImages[$0]==nil}
        guard !queue.isEmpty else{return}
        await withTaskGroup(of:(String,FeedImagePayload?).self) {group in
            inFlightPublicMedia.insert(queue[0])
            group.addTask { [self] in
                let media=queue[0]
                return (media,await fetchPublicImage(media,signedIn:signedIn))
            }
            var next=1
            while next<min(queue.count,6) {
                let media=queue[next];next+=1
                inFlightPublicMedia.insert(media)
                group.addTask { [self] in
                    return (media,await fetchPublicImage(media,signedIn:signedIn))
                }
            }
            while let (media,payload)=await group.next() {
                guard !Task.isCancelled,generation==publicGeneration else {group.cancelAll();return}
                inFlightPublicMedia.remove(media)
                if publicPosts.contains(where:{$0.media.contains(media)}) {
                    if let payload {rememberPublicImage(payload.image,media:media,compressed:payload.compressed)}
                    else {failedPublicImages.insert(media)}
                }
                while next<queue.count {
                    let nextMedia=queue[next];next+=1
                    if inFlightPublicMedia.contains(nextMedia) || publicImages[nextMedia] != nil || publicCompressedImages[nextMedia] != nil {continue}
                    inFlightPublicMedia.insert(nextMedia)
                    group.addTask { [self] in
                        return (nextMedia,await fetchPublicImage(nextMedia,signedIn:signedIn))
                    }
                    break
                }
            }
        }
    }
    func react(post:String,kind:String,enabled:Bool) async throws {
        let generation=publicGeneration
        let _:Bool=try await rpc("react",["p_post":post,"p_kind":kind,"p_enabled":enabled])
        guard generation==publicGeneration,let index=publicPosts.firstIndex(where:{$0.id==post}) else{return}
        if kind=="like" {
            if publicPosts[index].liked != enabled {
                publicPosts[index].likes=max(0,publicPosts[index].likes+(enabled ? 1 : -1))
                publicPosts[index].liked=enabled
                if feedMode=="liked" && !enabled {publicPosts.remove(at:index)}
            }
        } else if kind=="save" {
            publicPosts[index].saved=enabled
            if feedMode=="saved" && !enabled {publicPosts.remove(at:index)}
        }
    }
    func follow(pet:String,enabled:Bool) async throws {
        let generation=publicGeneration
        let _:Bool=try await rpc("follow",["p_pet":pet,"p_enabled":enabled])
        guard generation==publicGeneration else{return}
        if feedMode=="following" && !enabled {publicPosts.removeAll(where:{$0.pet_id==pet})}
        else {for index in publicPosts.indices where publicPosts[index].pet_id==pet {publicPosts[index].following=enabled}}
    }
    func syncCommentCount(post:String,count:Int) {
        guard let index=publicPosts.firstIndex(where:{$0.id==post}) else{return}
        publicPosts[index].comments=max(0,count)
    }
    func comments(post:String) async throws->[CloudComment] {try await rpc("comments",["p_post":post])}
    func publicSpeakers() async throws->[CloudBlockedPet] {try await rpc("public_speakers")}
    func socialIdentity() async throws->CloudSocialIdentity? {try await rpc("social_identity")}
    func setSocialName(_ name:String) async throws {let _:Bool=try await rpc("set_social_name",["p_name":name])}
    func comment(post:String,body:String,parent:String?,aliasPet:String?,key:UUID) async throws {let _:String=try await rpc("comment",["p_post":post,"p_body":body,"p_parent":parent as Any? ?? NSNull(),"p_alias_pet":aliasPet as Any? ?? NSNull(),"p_request_key":key.uuidString])}
    func deleteComment(_ id:String) async throws {let _:Bool=try await rpc("delete_comment",["p_comment":id])}
    func reportComment(_ id:String,reason:String,note:String,key:UUID) async throws {let _:String=try await rpc("report_comment",["p_comment":id,"p_reason":reason,"p_note":note,"p_request_key":key.uuidString])}
    func notificationPreferences() async throws->CloudNotificationPreferences {try await rpc("notification_preferences")}
    func setNotificationPreferences(_ value:CloudNotificationPreferences) async throws {let _:Bool=try await rpc("set_notification_preferences",["p_settings":["like":value.like,"comment":value.comment,"follow":value.follow,"twins":value.twins]])}
    func socialNotifications() async throws->[CloudSocialNotification] {try await rpc("social_notification_groups")}
    func socialConnections(kind:String,offset:Int,limit:Int=40) async throws->[CloudSocialConnection] {
        try await rpc("social_connections",["p_kind":kind,"p_offset":offset,"p_limit":limit])
    }
    func loadModerationNotices() async throws {moderationNotices=try await rpc("my_moderation")}
    func appeal(report:String,note:String) async throws {let _:String=try await rpc("appeal",["p_report":report,"p_note":note])}
    func deleteProvidedPhoto(id:String) async throws {let _:Bool=try await rpc("delete_photo",["p_photo":id]);clearPrivateViews();clearPublicViews();try await loadProvidedPhotos()}
    func block(pet:String,enabled:Bool) async throws {
        let _:Bool=try await rpc("block_pet",["p_pet":pet,"p_enabled":enabled])
        clearPublicViews();try await loadBlockedPets();try await loadPublicFeed()
    }
    func loadBlockedPets() async throws {blockedPets=try await rpc("blocked_pets")}
    func report(post:CloudPublicPost,reason:String,note:String,key:UUID) async throws {
        let _:String=try await rpc("report",["p_post":post.id,"p_pet":post.pet_id,"p_reason":reason,"p_note":note,"p_request_key":key.uuidString])
    }
    func delete(photo:String,pet:String) async throws {let _:Bool=try await rpc("delete_photo",["p_photo":photo]);clearPublicViews();try await loadAlbum(pet:pet)}
    private func twinsRequest<T:Decodable>(_ name:String,_ body:[String:Any]=[:]) async throws->T {
        if authenticated {return try await rpc(name,body)}
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:sessionService+".twins-guest",kSecAttrAccount as String:base]
        if twinsGuest==nil {var item:CFTypeRef?;if SecItemCopyMatching(query.merging([kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]){_,v in v} as CFDictionary,&item)==errSecSuccess,let data=item as? Data {twinsGuest=try? JSONDecoder().decode(CloudSession.self,from:data)}}
        if let old=twinsGuest,Self.needsSessionRefresh(expiresAt:old.expires_at,now:Date().timeIntervalSince1970) {twinsGuest=try JSONDecoder().decode(CloudSession.self,from:await request("/auth/v1/token?grant_type=refresh_token",body:["refresh_token":old.refresh_token]))}
        if twinsGuest==nil {twinsGuest=try JSONDecoder().decode(CloudSession.self,from:await request("/auth/v1/signup",body:[:]))}
        guard let guest=twinsGuest else {throw Failure.notAuthenticated}
        let attrs:[String:Any]=[kSecValueData as String:try JSONEncoder().encode(guest),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result=SecItemUpdate(query as CFDictionary,attrs as CFDictionary)
        if result==errSecItemNotFound {guard SecItemAdd(query.merging(attrs){_,v in v} as CFDictionary,nil)==errSecSuccess else {throw Failure.network}} else if result != errSecSuccess {throw Failure.network}
        return try JSONDecoder().decode(T.self,from:await request("/rest/v1/rpc/mefrion_"+name,body:body,token:guest.access_token))
    }
    private func referenceRequest(_ name:String,_ body:[String:Any]) async throws->Data {
        let path="/rest/v1/rpc/mefrion_reference_"+name
        return authenticated ? try await authenticatedRequest(path,body:body) : try await request(path,body:body)
    }
    func referenceSummary(species:String) async throws->ReferenceServerSummary {
        try JSONDecoder().decode(ReferenceServerSummary.self,from:await referenceRequest("stats_v2",["p_species":species]))
    }
    func referenceLookup(ids:[String]) async throws->[ReferencePetAsset] {
        guard ids.count<=60 else {throw Failure.invalid}
        let assets=try JSONDecoder().decode([ReferencePetAsset].self,from:await referenceRequest("lookup",["p_ids":ids]))
        guard assets.allSatisfy({$0.demoOnly && ["dog","cat"].contains($0.species) && $0.file==$0.id+".jpg" && $0.id.range(of:"^pexels-[0-9]+$",options:.regularExpression) != nil && URL(string:$0.source)?.host=="www.pexels.com"}) else {throw Failure.invalid}
        return assets
    }
    func referenceSearch(query:ReferenceQuery,species:String,consent:Bool,requestID:UUID) async throws->[ReferencePetAsset] {
        guard consent,["dog","cat"].contains(species),query.values.count==768,query.values.allSatisfy(\.isFinite),query.fingerprint.count==144,query.resemblance.count==384,query.resemblance.allSatisfy(\.isFinite),query.color.count==64,query.color.allSatisfy({$0.isFinite && $0>=0}) else {throw Failure.invalid}
        let defaults=UserDefaults.standard
        let saved=defaults.string(forKey:"MEFRIONReferenceGuestID").flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(saved.uuidString,forKey:"MEFRIONReferenceGuestID")
        var guest=saved
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--twins-vision-self-check") {guest=referenceProbeGuestID}
        #endif
        let vector=String(decoding:try JSONEncoder().encode(query.values),as:UTF8.self)
        let descriptor=String(decoding:try JSONEncoder().encode(query.resemblance),as:UTF8.self)
        let color=String(decoding:try JSONEncoder().encode(query.color),as:UTF8.self)
        let data=try await referenceRequest("search_v2",["p_species":species,"p_query":descriptor,"p_color":color,"p_legacy":vector,"p_fingerprint":query.fingerprint,"p_mean":query.mean,"p_algorithm":PetResemblance.algorithm,"p_consent":consent,"p_guest":guest.uuidString,"p_request":requestID.uuidString])
        let assets=try JSONDecoder().decode([ReferencePetAsset].self,from:data)
        guard assets.count<=3,assets.allSatisfy({$0.species==species && $0.demoOnly}) else {throw Failure.invalid}
        return assets
    }
    func referenceImage(id:String) async throws->UIImage {
        guard id.range(of:"^pexels-[0-9]+$",options:.regularExpression) != nil else {throw Failure.invalid}
        let bytes=try await request("/functions/v1/public-image?reference="+id)
        guard bytes.count<=200000,bytes.starts(with:[0xff,0xd8]),let image=UIImage(data:bytes) else {throw Failure.invalid}
        return image
    }
    func twinsCandidates(species:String) async throws->[CloudTwinCandidate] {
        let data = authenticated ? try await authenticatedRequest("/rest/v1/rpc/mefrion_twins_candidates",body:["p_species":species]) : try await request("/rest/v1/rpc/mefrion_twins_candidates",body:["p_species":species],token:twinsGuest?.access_token)
        return try JSONDecoder().decode([CloudTwinCandidate].self,from:data)
    }
    func twinsImage(_ id:String) async throws->UIImage {
        let data=authenticated ? try await authenticatedRequest("/functions/v1/public-image?media="+id) : try await request("/functions/v1/public-image?media="+id,token:twinsGuest?.access_token)
        guard let image=UIImage(data:data) else {throw Failure.invalid};return image
    }
    func beginTwins(key:UUID,hash:String,species:String) async throws->CloudTwinsSearch {try await twinsRequest("twins_begin",["p_key":key.uuidString,"p_hash":hash,"p_species":species])}
    func finishTwins(id:String,state:String,candidates:[String]) async throws {let _:Bool=try await twinsRequest("twins_finish",["p_search":id,"p_state":state,"p_candidates":candidates])}
    func twinsHistory() async throws->[CloudTwinsHistory] {try await twinsRequest("twins_history")}
    func enrollTwins(pet:String,photo:String,key:UUID) async throws->CloudPublication {try await rpc("twins_enroll",["p_pet":pet,"p_photo":photo,"p_key":key.uuidString,"p_explicit":true])}
    func twinsFeedback(search:String,candidate:String,similar:Bool) async throws {let _:Bool=try await rpc("twins_feedback",["p_search":search,"p_candidate":candidate,"p_similar":similar])}
    func publicPet(_ pet:String) async throws->CloudPublicPet {let data=authenticated ? try await authenticatedRequest("/rest/v1/rpc/mefrion_public_pet",body:["p_pet":pet]) : try await request("/rest/v1/rpc/mefrion_public_pet",body:["p_pet":pet]);return try JSONDecoder().decode(CloudPublicPet.self,from:data)}
    func petRecentPosts(_ pet:String) async throws->[CloudPetRecentPost] {let data=authenticated ? try await authenticatedRequest("/rest/v1/rpc/mefrion_pet_recent_posts",body:["p_pet":pet]) : try await request("/rest/v1/rpc/mefrion_pet_recent_posts",body:["p_pet":pet]);return try JSONDecoder().decode([CloudPetRecentPost].self,from:data)}
    func publicPost(_ id:String,petName:String) async throws->(post:CloudPublicPost?,visible:Bool) {
        // The profile already checked visibility. Fetch detail without replacing the home feed.
        let body:[String:Any]=["p_limit":50,"p_mode":"all","p_query":petName,"p_species":"all","p_known_ids":[id]]
        let data=authenticated ? try await authenticatedRequest("/rest/v1/rpc/mefrion_feed_page",body:body) : try await request("/rest/v1/rpc/mefrion_feed_page",body:body)
        let page=try JSONDecoder().decode(FeedPage.self,from:data)
        guard page.valid_known_ids.contains(id) else {return (nil,false)}
        return (page.items.first(where:{$0.id==id}),true)
    }
    func myPublications() async throws->[CloudMyPublication] {try await rpc("my_publications",["p_limit":50])}
    func shareTwins(search:String,query:String,candidate:String,key:UUID) async throws->CloudPublication {try await rpc("share_twins",["p_search":search,"p_query":query,"p_candidate":candidate,"p_key":key.uuidString,"p_explicit":true])}
    func stopTwinsShare(_ id:String) async throws {let _:Bool=try await rpc("stop_twins_share",["p_share":id])}
    func sharedProjection(_ id:String) async throws->CloudSharedProjection? {let data=try await request("/rest/v1/rpc/mefrion_shared_projection",body:["p_post":id]);return try JSONDecoder().decode(CloudSharedProjection?.self,from:data)}
    func sharedURL(_ id:String)->URL? {
        guard UUID(uuidString:id) != nil else {return nil}
        let route: String
        switch base {
        case "https://pbnimpqrthvznbwewtcf.supabase.co": route="cloud-shared"
        case "https://pmrvzpuznwzuejbuhaqm.supabase.co": route="cloud-development-shared"
        default: return nil
        }
        return URL(string:"https://mefrion-support.toshiki1108.chatgpt.site/"+route+"/"+id)
    }
    func withdrawTwins(pet:String) async throws {let _:Bool=try await rpc("twins_withdraw",["p_pet":pet])}

    func familyNotifications() async throws->[CloudFamilyNotification] {try await rpc("family_notifications")}

}

struct CloudTwinCandidate:Decodable,Identifiable {let id:String;let pet_id:String;let name:String;let species:String;var breed:String?=nil;var demo_only:Bool?=nil}
struct CloudTwinsSearch:Decodable {let id:String;let state:String;var remaining:Int?=nil}
struct CloudTwinsHistory:Decodable,Identifiable {let id:String;let state:String;let species:String;let created_at:String;let candidates:[CloudTwinCandidate]}

struct CloudFamilyNotification:Decodable,Identifiable {let id:String;let kind:String;let pet_id:String;let pet_name:String;let title:String;let count:Int;let created_at:String}

struct CloudPublicPet:Decodable {let id:String;let name:String;let species:String;var breed:String?;var introduction:String?;var sex:String?;var birthday:String?;var life_status:String?}
struct CloudPetRecentPost:Decodable,Identifiable {let id:String;let body:String;let media:[String]}
struct CloudSharedProjection:Decodable {let id:String;let kind:String;let name:String}
