import SwiftUI
import PhotosUI
import Photos
import ImageIO

struct CloudFamilyView:View {
    var registrationOnly=false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var client=CloudFamilyClient.shared
    @State private var publicKey=""
    @State private var petName=""
    @State private var species="dog"
    @State private var speciesSelected=false
    @State private var petBreed=""
    @State private var showingPetForm=false
    @State private var inviteToken=""
    @State private var confirmScope=false
    var body:some View {
        List {
            if registrationOnly && client.authenticated {
                Section {petCreationFields}
            } else {
                Section {Text("家族アルバム").font(.headline);Text("写真は、参加している家族だけで共有します。アルバムへの追加だけでは公開投稿に配信しません。").font(.footnote)}
                if !client.authenticated {
                    if !client.configured {
                        #if DEBUG
                        Section("接続設定") {SecureField("接続用キー",text:$publicKey);Button("接続設定を保存") { if publicKey.hasPrefix("sb_publishable_") || publicKey.hasPrefix("eyJ") {UserDefaults.standard.set(publicKey,forKey:"MEFRIONCloudPublicKey");publicKey=""} } }
                        #else
                        Section {Text("現在アカウントサービスに接続できません。時間をおいて再試行してください。")}
                        #endif
                    }
                    Section {
                        NavigationLink("メールで新規登録") {EmailAccountView(client:client,initialMode:"signup")}
                        NavigationLink("メールでログイン") {EmailAccountView(client:client)}
                        Text("犬猫を飼っていなくても登録できます。うちの子はあとから追加できます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("家族のPet") {
                        Text("サーバー認証済み").accessibilityIdentifier("cloud-authenticated")
                        if client.pets.isEmpty {
                            Text("まだ犬猫を登録していません。投稿を見る・フォロー・そっくりはこのまま使えます。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(client.pets) {pet in NavigationLink {CloudAlbumLibraryView()} label:{HStack {Image(systemName:"pawprint.fill").foregroundStyle(Theme.accent);VStack(alignment:.leading){Text(pet.name);Text(pet.role=="owner" ? "オーナー" : "家族メンバー").font(.caption).foregroundStyle(.secondary)}}}.accessibilityIdentifier("cloud-pet-"+pet.id)}
                        Button("一覧を更新") {Task {await client.perform {try await client.loadPets()} } }
                    }
                    Section("運営からの通知") {NavigationLink("対応の確認・異議申し立て") {CloudModerationNoticesView(client:client)}}
                    Section("提供した写真") {NavigationLink("公開用途の同意を管理") {ProviderConsentView(client:client)}.accessibilityIdentifier("cloud-provider-management")}
                    Section {
                        if client.pets.isEmpty {
                            DisclosureGroup("うちの子を登録する（任意）",isExpanded:$showingPetForm) {
                                petCreationFields
                            }
                        } else {
                            petCreationFields
                        }
                    } header: {
                        if !client.pets.isEmpty {Text("Petを非公開で作成")}
                    }
                    Section("招待を受け取ったら") {
                        TextField("招待トークン",text:$inviteToken).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("家族内の写真を閲覧・追加する範囲に同意する",isOn:$confirmScope)
                        Text("SNS・そっくり・外部共有の公開権限は付与されません。").font(.caption)
                        Button("家族に参加") {Task {await client.perform {try await client.accept(token:inviteToken,confirmed:confirmScope);inviteToken="";confirmScope=false} } }.disabled(!confirmScope)
                    }
                    Button("ログアウト",role:.destructive) {Task {await client.signOut()} }
                }
            }
            if client.busy {ProgressView("確認中")}
            if let error=client.error {Text(error).foregroundStyle(.red).accessibilityIdentifier("cloud-error")}
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle(registrationOnly ? "うちの子を登録" : "家族で共有").navigationBarTitleDisplayMode(.inline).task {await client.restore()}.protectWhenInactive()
            .onChange(of:species) {_,_ in petBreed=""}
    }

    @ViewBuilder private var petCreationFields:some View {
        TextField("犬・猫の名前",text:$petName).accessibilityIdentifier("cloud-pet-name")
        PetSpeciesSelectionField(species:$species,selected:$speciesSelected)
        if speciesSelected {
            BreedAutocompleteField(species:species,text:$petBreed,identifier:"cloud-pet-breed")
        }
        Button("この子を登録") {Task {await client.perform {
            if client.pets.isEmpty {try await client.setSocialName(petName.trimmingCharacters(in:.whitespacesAndNewlines))}
            let breed=PetBreedCatalog.canonical(petBreed,species:species) ?? petBreed.trimmingCharacters(in:.whitespacesAndNewlines)
            try await client.createPet(name:petName,species:species,breed:breed)
            petName="";petBreed="";speciesSelected=false;showingPetForm=false
            if registrationOnly {dismiss()}
        } } }
        .disabled(!speciesSelected || !(1...40).contains(petName.trimmingCharacters(in:.whitespacesAndNewlines).count) || !(1...100).contains(petBreed.trimmingCharacters(in:.whitespacesAndNewlines).count))
        .accessibilityIdentifier("cloud-create-pet")
    }
}

struct ProviderConsentView:View {
    @ObservedObject var client:CloudFamilyClient
    @State private var withdrawing:(String,String)?
    @State private var deleting:String?
    var body:some View {
        List {
            Text("家族から退出しても、自分が提供した写真の公開同意を取り消せます。ここでは元写真や他の家族の記録を取得しません。").font(.footnote)
            ForEach(client.providedPhotos) {photo in
                Section(photo.title.isEmpty ? "提供写真 "+String(photo.id.prefix(8)) : photo.title) {
                    Text(photo.captured ?? "日付不明")
                    ForEach([("sns","SNS",photo.sns),("twins","そっくり",photo.twins),("external_share","外部共有",photo.external_share)],id:\.0) {purpose,title,allowed in
                        HStack {Text(title+"："+(allowed ? "同意中" : "同意なし"));Spacer();if allowed {Button("取り消す",role:.destructive) {withdrawing=(photo.id,purpose)}.disabled(client.busy).accessibilityIdentifier("provider-withdraw-"+purpose)}}
                    }
                    Button("提供した写真を削除",role:.destructive) {deleting=photo.id}.disabled(client.busy).accessibilityIdentifier("provider-delete-"+photo.id)
                }
            }
            if client.providedPhotos.isEmpty && !client.busy {Text("提供した写真はありません。")}
            if client.busy {ProgressView()}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("写真の公開同意").task {await client.performRefresh {try await client.loadProvidedPhotos()}}
        .onDisappear {client.providedPhotos=[]}
        .confirmationDialog("この提供写真を削除しますか？",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) {
            Button("元写真と関連する公開表示を削除",role:.destructive) {if let id=deleting {Task {await client.perform {try await client.deleteProvidedPhoto(id:id)}}};deleting=nil}
        } message: {Text("退出後も自分の提供写真を削除できます。家族アルバムから写真が消え、利用した公開投稿や共有表示を停止します。取り消せません。")}
        .confirmationDialog("この用途への公開同意を取り消しますか？",isPresented:Binding(get:{withdrawing != nil},set:{if !$0 {withdrawing=nil}})) {Button("同意を取り消す",role:.destructive) {if let (id,purpose)=withdrawing {Task {await client.perform {try await client.consent(photo:id,purpose:purpose,allowed:false);try await client.loadProvidedPhotos()}}};withdrawing=nil}}
    }
}

struct CloudAlbumView:View {
    private struct Composition:Identifiable {let id=UUID();let photos:[CloudPhoto];let images:[String:UIImage]}
    let pet:CloudPet
    @ObservedObject var client:CloudFamilyClient
    @State private var selection:[PhotosPickerItem]=[]
    @Environment(\.scenePhase) private var scenePhase
    @State private var captured=""
    @State private var confirmDelete:String?
    @State private var confirmingConsent:(String,String,Bool)?
    @State private var composition:Composition?
    @State private var stoppingProfile=false
    private struct ImportReview:Identifiable {let id=UUID();let drafts:[CloudUploadDraft]}
    @State private var review:ImportReview?
    @State private var importGeneration=UUID()
    @State private var savingPhoto:String?
    @State private var saveMessage:String?
    @State private var showingPhotoPermissions=false
    @State private var expandedPhotoActions:Set<String>=[]
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:16) {
            HStack {Text(pet.name+"のアルバム").font(.title3.bold());Spacer();Label("家族だけ",systemImage:"lock.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.actionText)}
            PhotosPicker(selection:$selection,maxSelectionCount:30,matching:.images) {
                Label("写真を追加",systemImage:"plus.circle.fill")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth:.infinity,minHeight:52)
                    .background(Theme.accent.gradient,in:Capsule())
            }.buttonStyle(.plain).disabled(client.busy).accessibilityIdentifier("cloud-album-add-photos")
            Text("選んだ写真は家族だけのアルバムに保存されます。").font(.caption).foregroundStyle(Theme.secondaryText)
            CloudUploadStatus(pet:pet.id,queue:client.uploads,busy:client.busy) {Task {await client.perform {try await client.sendUploads(pet:pet.id)}}}
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-isolated") {
                Button("合成イラスト1枚を追加（検証用）") { if let image=UIImage(named:"pet-0") {Task {await client.perform {try await client.upload(pet:pet.id,image:image,captured:nil)} } } }.accessibilityIdentifier("cloud-upload-demo")
            }
            #endif
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-isolated") {
                Button("追加前の確認を検証") {if let image=UIImage(named:"pet-0"),let data=image.jpegData(compressionQuality:0.9) {review=ImportReview(drafts:[CloudUploadDraft(pet:pet.id,jpeg:data,captured:nil),CloudUploadDraft(pet:pet.id,jpeg:data,captured:nil)])}}.accessibilityIdentifier("cloud-import-review-fixture")
            }
            #endif
            if client.busy {PawLoadingView(title:"写真を準備中",compact:true)}
            if let error=client.error {Text(error).foregroundStyle(.red).accessibilityIdentifier("cloud-error")}
            if let saveMessage {Text(saveMessage).font(.caption)}
            if client.photos.isEmpty && !client.busy {ContentUnavailableView("写真はまだありません",systemImage:"photo.on.rectangle.angled",description:Text("かわいい瞬間を、ここに残そう"))}
            ForEach(client.photos) {photo in
                VStack(alignment:.leading,spacing:10) {
                    if let image=client.images[photo.id] {Image(uiImage:image).resizable().scaledToFill().frame(maxWidth:.infinity).frame(height:260).clipped().clipShape(RoundedRectangle(cornerRadius:16)).accessibilityIdentifier("cloud-photo")}
                    HStack {Text(photo.title.isEmpty ? (photo.captured ?? "思い出") : photo.title).font(.headline);Spacer();Text(photo.captured ?? "").font(.caption).foregroundStyle(.secondary)}
                    DisclosureGroup("写真の操作",isExpanded:Binding(get:{expandedPhotoActions.contains(photo.id)},set:{opened in if opened {expandedPhotoActions.insert(photo.id)} else {expandedPhotoActions.remove(photo.id)}})) {
                        Text("追加した人："+(photo.provider_name ?? (photo.mine ? "あなた" : "家族メンバー"))).font(.caption).foregroundStyle(.secondary)
                        Button("端末に保存") {savingPhoto=photo.id}.disabled(client.busy).accessibilityIdentifier("cloud-save-photo-"+photo.id)
                        if photo.mine {
                            NavigationLink("写真・節目を編集") {CloudPhotoEditor(photo:photo,pet:pet.id,client:client)}
                            DisclosureGroup("写真の公開許可") {ForEach([("sns","SNS"),("twins","そっくり"),("external_share","外部共有")],id:\.0) {purpose,title in
                                HStack {Button(title+"への写真提供に同意") {confirmingConsent=(photo.id,purpose,true)};Button("同意を取り消す",role:.destructive) {confirmingConsent=(photo.id,purpose,false)}}.font(.caption)
                            }}.font(.caption)
                        }
                        if photo.mine || pet.role=="owner" {Button("写真を削除",role:.destructive) {confirmDelete=photo.id}.accessibilityIdentifier("cloud-delete-photo")}
                    }
                }.padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius:20))
            }
            DisclosureGroup("アルバムの設定",isExpanded:$showingPhotoPermissions) {
                VStack(alignment:.leading,spacing:16) {
                    if pet.role=="owner" {
                        Button("アルバムの写真から投稿") {composition=Composition(photos:client.photos,images:client.images)}
                            .disabled(client.photos.isEmpty || client.busy).accessibilityIdentifier("cloud-compose-post")
                    }
                    NavigationLink("家族メンバー") {CloudMembersView(pet:pet,client:client)}
                    if pet.role=="owner" {
                        NavigationLink("家族を招待") {FamilyInviteView(pet:pet,client:client)}
                        NavigationLink("プロフィールを編集") {CloudProfileEditor(pet:client.pets.first(where:{$0.id==pet.id}) ?? pet,client:client)}
                        NavigationLink("Petの公開設定") {CloudPetPublicSettingsView(pet:pet,client:client)}
                    }
                    DisclosureGroup("その他の管理") {
                        VStack(alignment:.leading,spacing:16) {
                            NavigationLink("家族の記録") {CloudFamilyActivityView(pet:pet,client:client)}
                            NavigationLink("記念日") {CloudEventsView(pet:pet,client:client)}
                            if pet.role=="owner" {
                                Button("Petの公開プロフィールを停止",role:.destructive) {stoppingProfile=true}.disabled(client.busy).accessibilityIdentifier("cloud-stop-public-profile")
                                if let invite=client.invitation {
                                    Text("有効期限："+invite.expires_at).font(.caption)
                                    ShareLink(item:invite.token) {Label("招待トークンを共有",systemImage:"square.and.arrow.up")}
                                    Button("招待を取り消す",role:.destructive) {Task {await client.perform {try await client.cancelInvite()} } }
                                }
                            }
                        }
                    }
                }.padding(.top,8)
            }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:18))
            Button("アルバムを更新") {Task {await client.perform {try await client.loadAlbum(pet:pet.id)} } }.accessibilityIdentifier("cloud-refresh-album")
        }.padding(16) }.background(Theme.background).navigationTitle(pet.name).navigationBarTitleDisplayMode(.inline)
        .sheet(item:$composition) {snapshot in NavigationStack {CloudPublicationComposer(pet:pet,photos:snapshot.photos,images:snapshot.images,client:client)}}
        .task {await client.performRefresh {try await client.loadAlbum(pet:pet.id)} }
        .onChange(of:client.currentUserID) {_,_ in importGeneration=UUID();review=nil;savingPhoto=nil;composition=nil;selection=[];captured="";confirmingConsent=nil;confirmDelete=nil}
        .onDisappear {selection=[]}
        .sheet(item:$review) {snapshot in
            CloudImportReview(drafts:snapshot.drafts,petName:pet.name,captured:$captured,busy:client.busy,error:client.error,onCancel:{review=nil;selection=[]}) {drafts in
                let confirmed=drafts.map {CloudUploadDraft(pet:pet.id,jpeg:$0.jpeg,captured:captured.isEmpty ? nil : captured,id:$0.id)}
                Task {await client.perform {try client.uploads.append(confirmed);review=nil;selection=[];try await client.sendUploads(pet:pet.id)}}
            }
        }
        .onChange(of:selection) {_,items in
            guard !items.isEmpty else{return};let actor=client.currentUserID;let stamp=UUID();importGeneration=stamp
            Task {await client.perform {
                var drafts:[CloudUploadDraft]=[];var bytes=0
                for item in items {
                    guard stamp==importGeneration,scenePhase == .active else {throw CancellationError()}
                    guard let data=try await item.loadTransferable(type:Data.self) else {throw CloudPhotoCodec.Failure.decode}
                    let jpeg=try CloudPhotoCodec.encode(data);bytes+=jpeg.count
                    guard bytes<=100*1024*1024 else {throw CloudUploadQueue.Validation.size}
                    drafts.append(CloudUploadDraft(pet:pet.id,jpeg:jpeg,captured:nil))
                }
                guard stamp==importGeneration,client.authenticated,client.currentUserID==actor,scenePhase == .active else {throw CancellationError()}
                try client.uploads.append(drafts)
                selection=[]
                try await client.sendUploads(pet:pet.id)
            }}
        }
        .onChange(of:scenePhase) {_,phase in if phase != .active {importGeneration=UUID();review=nil;selection=[];savingPhoto=nil} else {Task {await client.performRefresh {try await client.loadAlbum(pet:pet.id)}}} }
        .confirmationDialog("家族内の保存済みJPEGを端末の写真ライブラリへ保存しますか？",isPresented:Binding(get:{savingPhoto != nil},set:{if !$0 {savingPhoto=nil}}),titleVisibility:.visible) {
            Button("この端末に保存") {guard let id=savingPhoto else{return};savingPhoto=nil;Task {await client.perform {
                let actor=client.currentUserID
                let status=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
                guard status == .authorized || status == .limited else {saveMessage="写真への追加を許可してください。";return}
                let image=try await client.privatePhotoForDeviceSave(id)
                guard actor==client.currentUserID,scenePhase == .active else {throw CancellationError()}
                try await PHPhotoLibrary.shared().performChanges {PHAssetChangeRequest.creationRequestForAsset(from:image)}
                saveMessage="保存済みJPEGを端末に保存しました。端末側のコピーはアプリの削除と連動しません。"
            }}}
        } message: {Text("家族の非公開写真です。端末からSNSなどへ公開する場合は、写真の提供者への確認が別途必要です。取り込み前のHEIC等ではなく、MEFRIONに保存したJPEGを書き出します。")}
        .confirmationDialog("家族アルバムの写真を削除しますか？関連する表示も停止します。",isPresented:Binding(get:{confirmDelete != nil},set:{if !$0 {confirmDelete=nil}})) {Button("削除する",role:.destructive) {if let id=confirmDelete {Task {await client.perform {try await client.delete(photo:id,pet:pet.id)} }};confirmDelete=nil}}
        .confirmationDialog(confirmingConsent?.2==true ? "この用途で公開するための写真提供に同意しますか？家族内保存とは別の同意です。公開はオーナーが別途操作します。" : "この用途への公開同意を取り消しますか？",isPresented:Binding(get:{confirmingConsent != nil},set:{if !$0 {confirmingConsent=nil}})) {Button(confirmingConsent?.2==true ? "この用途に同意する" : "同意を取り消す") {if let (photo,purpose,allowed)=confirmingConsent {Task {await client.perform {try await client.consent(photo:photo,purpose:purpose,allowed:allowed)}}};confirmingConsent=nil}}
        .confirmationDialog("Petの公開プロフィールと公開投稿を停止しますか？家族アルバムは非公開のまま保持します。",isPresented:$stoppingProfile) {Button("公開プロフィールを停止",role:.destructive) {Task {await client.perform {try await client.setPublicProfile(pet:pet.id,enabled:false)}}}}
    }
}

private struct CloudImportReview:View {
    @State var drafts:[CloudUploadDraft]
    let petName:String
    @Binding var captured:String
    let busy:Bool
    let error:String?
    let onCancel:()->Void
    let onConfirm:([CloudUploadDraft])->Void
    var body:some View {
        NavigationStack {List {
            Section("追加先："+petName) {TextField("撮影日（空欄は不明）",text:$captured);Text("確認して追加するまで送信しません。不要な写真は取り消せます。").font(.caption)}
            ForEach(drafts) {draft in HStack {
                if let source=CGImageSourceCreateWithData(draft.jpeg as CFData,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:240] as CFDictionary) {Image(uiImage:UIImage(cgImage:cg)).resizable().scaledToFit().frame(width:100,height:100)}
                Spacer();Button("取り消す",role:.destructive) {drafts.removeAll{$0.id==draft.id}}.buttonStyle(.borderless).accessibilityIdentifier("cloud-import-remove")
            }}
            Button("確認した\(drafts.count)枚を追加") {onConfirm(drafts)}.disabled(drafts.isEmpty || busy || !PrototypeStore.dateIsValid(captured)).accessibilityIdentifier("cloud-import-confirm")
            if let error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("写真を確認").toolbar {Button("キャンセル",action:onCancel)}}.protectWhenInactive()
        .onDisappear {drafts=[]}
    }
}

private struct CloudUploadStatus:View {
    let pet:String
    @ObservedObject var queue:CloudUploadQueue
    let busy:Bool
    let retry:()->Void
    var body:some View {
        let drafts=queue.drafts.filter{$0.pet==pet && $0.state != .complete}
        if !drafts.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                Text("写真を保存中").accessibilityIdentifier("cloud-upload-count")
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                    ForEach(Array(drafts.enumerated()),id:\.element.id) {index,draft in
                        VStack(spacing:4) {
                            if let image=thumbnail(draft.jpeg) {
                                Image(uiImage:image).resizable().scaledToFill().frame(height:100).clipped().clipShape(RoundedRectangle(cornerRadius:10)).overlay {
                                    if draft.state == .uploading {ProgressView().padding(8).background(.white.opacity(0.85)).clipShape(Circle())}
                                }.overlay(alignment:.topTrailing) {
                                    if draft.state == .complete {Image(systemName:"checkmark.circle.fill").foregroundStyle(Theme.accent).padding(5)}
                                    else if draft.state == .failed {Image(systemName:"exclamationmark.circle.fill").foregroundStyle(.red).padding(5)}
                                }
                            }
                            Text(draft.state == .complete ? "保存済み" : draft.state == .uploading ? "送信中" : draft.state == .failed ? "再試行が必要" : "待機中").font(.caption2)
                            if draft.state == .failed {Text(draft.message ?? "再試行してください").font(.caption2).foregroundStyle(.red)}
                        }
                    }
                }
                if queue.isSending {Button("ここまでで追加を中断") {queue.pause()}.disabled(queue.paused).accessibilityIdentifier("cloud-pause-upload");Text("送信中の1枚は保存結果を確認してから中断します。残りは同じ写真で再開できます。").font(.caption)}
                if queue.paused {Text("追加を中断しました。保存済みの写真は保持します。").font(.caption)}
                if drafts.contains(where:{$0.state == .pending}) && !queue.isSending {Button("残りの写真を再開",action:retry).disabled(busy).accessibilityIdentifier("cloud-resume-upload")}
                if drafts.contains(where:{$0.state == .failed}) {
                    Button("失敗した写真を再試行",action:retry).disabled(busy).accessibilityIdentifier("cloud-retry-upload")
                    Button("重複候補も保存して再試行") {do {try queue.approveDuplicates(pet:pet);retry()} catch {}}.disabled(busy)
                    Text("同じ写真の候補がある場合だけ、追加保存を明示して再試行できます。").font(.caption)
                }
            }
        }
    }
    private func thumbnail(_ data:Data)->UIImage? {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:240,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else{return nil};return UIImage(cgImage:cg)
    }

}

struct CloudMembersView:View {
    let pet:CloudPet
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    @State private var removing:CloudMember?
    @State private var familyName=""
    var body:some View {
        List {
            Section {HStack {Image(systemName:"pawprint.fill").font(.system(size:36)).foregroundStyle(Theme.accent).frame(width:64,height:64).background(Theme.accent.opacity(0.07)).clipShape(Circle());VStack(alignment:.leading,spacing:6) {Text(pet.name+"の家族").font(.headline);Text("みんなで大切な毎日を見守ります").font(.caption).foregroundStyle(.secondary)}}.padding(.vertical,12)}
            Section("この家族内だけの呼び名") {TextField("呼び名（40字まで・空欄で解除）",text:$familyName);Button("家族内の呼び名を保存") {Task {await client.perform {try await client.setFamilyName(pet:pet.id,name:familyName)}}}.disabled(client.busy || familyName.count>40);Text("SNSの名前とは別です。このPetの家族の写真・活動だけに表示します。").font(.caption)}
            Section("メンバー（\(client.members.count)人）") {
                ForEach(client.members) {member in
                    HStack {
                        Image(systemName:"person.crop.circle").font(.system(size:36)).foregroundStyle(Theme.accent)
                        VStack(alignment:.leading) {Text((member.display_name ?? "家族メンバー")+(member.me ? "（あなた）" : ""));Text("ID "+String(member.id.prefix(8))).font(.caption).foregroundStyle(.secondary)}
                        Spacer()
                        if member.role != "owner" && (pet.role=="owner" || member.me) {Button(member.me ? "退出" : "解除",role:.destructive) {removing=member}}
                    }
                }
            }
            Text("オーナーと家族メンバーで権限を分けています。解除・退出後は、新しい写真取得と共同編集ができなくなります。提供した写真は家族内に保持され、公開同意は取り消せます。").font(.footnote)
            if client.busy {ProgressView()}
            if let error=client.error {Text(error).foregroundStyle(.red)}
            if pet.role=="owner" {NavigationLink {FamilyInviteView(pet:pet,client:client)} label: {Label("メンバーを招待する",systemImage:"plus.circle")}}
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("家族メンバー").task {await client.performRefresh {try await client.loadMembers(pet:pet.id);familyName=client.members.first(where:{$0.me})?.display_name ?? ""}}
        .confirmationDialog("家族へのアクセスを解除しますか？",isPresented:Binding(get:{removing != nil},set:{if !$0 {removing=nil}})) {Button("解除する",role:.destructive) {if let member=removing {Task {await client.perform {try await client.removeMember(pet:pet.id,user:member.id);if member.me {dismiss()} } }};removing=nil}}
    }
}
