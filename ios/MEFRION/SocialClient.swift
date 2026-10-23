import Foundation
import SwiftUI

struct FeedImage: Decodable { let asset: String; let captured: String? }
struct FeedPost: Decodable, Identifiable {
    let id: String
    let pet_id: String
    let name: String
    let species: String
    let body: String
    let asset: String
    let images: [FeedImage]
    let likes: Int
    let comments: Int
    let liked: Bool
    let saved: Bool
    let following: Bool
}
struct FeedComment: Decodable, Identifiable {
    let id: String
    let body: String
    let parent: String?
    let display_name: String
}

@MainActor
final class SocialClient: ObservableObject {
    @Published var posts: [FeedPost] = []
    @Published var comments: [FeedComment] = []
    @Published var loading = false
    @Published var error: String?
    @Published var liked: Set<String> = []
    @Published var saved: Set<String> = []
    @Published var followed: Set<String> = []
    @Published var message: String?
    private var currentFollowing = false
    private var currentSaved = false

    // Fixed development identity only. Release builds cannot use this adapter.
    func request<T: Decodable>(_ path: String, body: [String: Any]? = nil, as type: T.Type) async throws -> T {
        #if DEBUG && targetEnvironment(simulator)
        let base = ProcessInfo.processInfo.environment["MEFRION_TEST_API_BASE"] ?? "http://127.0.0.1:8765"
        guard let components=URLComponents(string:base), components.scheme == "http",
              components.host == "127.0.0.1", [8765,8766].contains(components.port ?? 0),
              components.path.isEmpty, components.query == nil, components.user == nil,
              let url=URL(string:base+path) else { throw PrototypeError(message:"開発APIの接続先が不正です。") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Bearer local-owner", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw PrototypeError(message: "この操作は許可されないか、対象の公開が終了しています。")
        }
        return try JSONDecoder().decode(type, from: data)
        #else
        throw PrototypeError(message: "本認証・サーバーの接続設定が必要です。")
        #endif
    }

    func load(following: Bool = false) async {
        currentFollowing = following
        currentSaved = false
        loading = true; error = nil
        struct Response: Decodable { let posts: [FeedPost] }
        do {
            let response = try await request(following ? "/v1/demo/social/following" : "/v1/demo/feed", as: Response.self)
            posts = response.posts
            liked = Set(posts.filter(\.liked).map(\.id))
            saved = Set(posts.filter(\.saved).map(\.id))
            followed = Set(posts.filter(\.following).map(\.pet_id))
        } catch { self.error = "開発APIに接続できません。Macのローカルサーバーを確認してください。"; posts = [] }
        loading = false
    }

    func loadSaved() async {
        currentSaved=true
        loading=true;error=nil
        struct Response:Decodable { let posts:[FeedPost] }
        do { posts=try await request("/v1/demo/social/saved",as:Response.self).posts
            liked=Set(posts.filter(\.liked).map(\.id));saved=Set(posts.filter(\.saved).map(\.id));followed=Set(posts.filter(\.following).map(\.pet_id))
        }
        catch { posts=[];self.error=error.localizedDescription }
        loading=false
    }

    private struct Action: Decodable { }
    func action(_ path: String, _ body: [String: Any]) async -> Bool {
        error = nil; message = nil
        do { _ = try await request(path, body: body, as: Action.self); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func react(_ post: FeedPost, kind: String) async {
        let selected = kind == "like" ? liked.contains(post.id) : saved.contains(post.id)
        if await action("/v1/demo/social/react", ["post_id":post.id,"kind":kind,"enabled":!selected]) {
            if kind == "like" { if selected { liked.remove(post.id) } else { liked.insert(post.id) } }
            else { if selected { saved.remove(post.id) } else { saved.insert(post.id) } }
            if currentSaved { await loadSaved() } else { await load(following:currentFollowing) }
        }
    }
    func follow(_ post: FeedPost) async {
        let enabled = !followed.contains(post.pet_id)
        if await action("/v1/demo/social/follow", ["pet_id":post.pet_id,"enabled":enabled]) {
            if enabled { followed.insert(post.pet_id) } else { followed.remove(post.pet_id) }
        }
    }
    func block(_ post: FeedPost) async {
        if await action("/v1/demo/social/block", ["pet_id":post.pet_id]) { if currentSaved { await loadSaved() } else { await load(following:currentFollowing) }; message = "この管理者のすべてのPetをブロックしました。" }
    }
    func report(_ post: FeedPost, reason: String) async {
        if await action("/v1/demo/social/report", ["post_id":post.id,"reason":reason]) { message = "開発環境の通報受付に記録しました。" }
    }
    func loadComments(_ id: String) async {
        struct Response: Decodable { let comments: [FeedComment] }
        do { comments = try await request("/v1/demo/social/comments/"+id, as: Response.self).comments }
        catch { comments = []; self.error = error.localizedDescription }
    }
    func comment(_ id: String, body: String, parent: String? = nil) async -> Bool {
        var payload: [String:Any] = ["post_id":id,"body":body]
        if let parent { payload["parent"] = parent }
        let success = await action("/v1/demo/social/comment", payload)
        if success { await loadComments(id) }
        return success
    }
}
