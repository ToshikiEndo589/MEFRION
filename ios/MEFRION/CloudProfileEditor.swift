import SwiftUI
import PhotosUI
import ImageIO

/// A bounded, metadata-free thumbnail. Never place full photos in Auth/JWT data.
enum ProfileIconCodec {
    static let maximumBytes=16384
    static func encode(data:Data)->String? {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1024] as CFDictionary) else{return nil}
        return encode(image:UIImage(cgImage:image))
    }
    static func encode(image:UIImage)->String? {
        guard image.size.width>0,image.size.height>0 else{return nil}
        for side in [256.0,192.0,128.0] {
            let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
            let scale=max(side/image.size.width,side/image.size.height)
            let size=CGSize(width:image.size.width*scale,height:image.size.height*scale)
            let thumbnail=UIGraphicsImageRenderer(size:CGSize(width:side,height:side),format:format).image {context in
                UIColor.white.setFill();context.fill(CGRect(x:0,y:0,width:side,height:side))
                image.draw(in:CGRect(x:(side-size.width)/2,y:(side-size.height)/2,width:size.width,height:size.height))
            }
            for quality in [0.8,0.6,0.4] {
                if let jpeg=thumbnail.jpegData(compressionQuality:quality),jpeg.count<=maximumBytes {return jpeg.base64EncodedString()}
            }
        }
        return nil
    }
    static func image(_ value:String?)->UIImage? {
        guard let value,value.count<=22500,let bytes=Data(base64Encoded:value,options:.ignoreUnknownCharacters),bytes.count<=maximumBytes else{return nil}
        return UIImage(data:bytes)
    }
}

struct ProfileIconImage:View {
    let encoded:String?
    var size:CGFloat=48
    var fallback="pawprint.fill"
    @State private var image:UIImage?
    @State private var decodedValue:String?
    var body:some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.1))
            if let image,decodedValue==encoded {
                Image(uiImage:image).resizable().scaledToFill()
            } else {Image(systemName:fallback).font(.system(size:size*0.4)).foregroundStyle(Theme.actionText)}
        }.frame(width:size,height:size).clipShape(Circle())
            .task(id:encoded) {image=ProfileIconCodec.image(encoded);decodedValue=encoded}
    }
}

struct EditableProfileIcon:View {
    @Binding var encoded:String?
    @Binding var changed:Bool
    @State private var selection:PhotosPickerItem?
    @Binding var importing:Bool
    @State private var requestID=UUID()
    @State private var error:String?
    var body:some View {
        VStack(spacing:9) {
            PhotosPicker(selection:$selection,matching:.images) {
                HStack(spacing:16) {
                    ProfileIconImage(encoded:encoded,size:72)
                        .overlay(alignment:.bottomTrailing) {
                            Image(systemName:"camera.fill").font(.caption).foregroundStyle(.white)
                                .frame(width:28,height:28).background(Theme.accent,in:Circle())
                        }
                    VStack(alignment:.leading,spacing:6) {
                        Text("写真を変更").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.actionText)
                        Text("プロフィールやコメントにも表示されます。")
                            .font(.caption).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength:0)
                }
            }.buttonStyle(.borderless).disabled(importing)
                .accessibilityIdentifier("profile-icon-picker")
            if importing {ProgressView("写真を準備中")}
            if encoded != nil {
                Button("写真を外す") {requestID=UUID();encoded=nil;changed=true;selection=nil;importing=false}
                    .font(.caption).foregroundStyle(Theme.secondaryText).buttonStyle(.borderless)
                    .accessibilityIdentifier("profile-icon-remove")
            }
            if let error {Text(error).font(.caption).foregroundStyle(.red)}
        }.frame(maxWidth:.infinity).padding(.vertical,10)
        .onChange(of:selection) {_,item in
            guard let item else{return}
            importing=true;error=nil;let request=UUID();requestID=request
            Task {
                defer {if requestID==request {importing=false}}
                do {
                    guard let data=try await item.loadTransferable(type:Data.self) else {throw CocoaError(.fileReadCorruptFile)}
                    let value=await Task.detached(priority:.userInitiated) {ProfileIconCodec.encode(data:data)}.value
                    guard let value else {throw CocoaError(.fileReadCorruptFile)}
                    guard requestID==request else{return}
                    encoded=value;changed=true
                } catch {if requestID==request {self.error="写真を選び直してね"}}
            }
        }
    }
}

struct CloudProfileEditor:View {
    @Environment(\.dismiss) private var dismiss
    let pet:CloudPet
    @ObservedObject var client:CloudFamilyClient
    @State private var name=""
    @State private var breed=""
    @State private var intro=""
    @State private var sex="unknown"
    @State private var birthday=""
    @State private var arrival=""
    @State private var age=""
    @State private var temperament=""
    @State private var life="living"
    @State private var familyIcon=""
    @State private var cover=""
    @State private var icon:String?
    @State private var iconChanged=false
    @State private var importingIcon=false
    @State private var fields:Set<String>=[]
    @State private var saved=false
    @State private var initialized=false
    @State private var albumPhotos:[CloudPhoto]=[]
    @State private var photoPurpose:String?
    @State private var showAlbumPicker=false
    @State private var twinPhoto=""
    @State private var twinConfirmed=false
    @State private var twinKey=UUID()
    @State private var twinMessage:String?
    @State private var photoError:String?
    private let labels=[("breed","品種"),("introduction","自己紹介"),("sex","性別"),("birthday","誕生日"),("arrival","お迎え日"),("age_basis","年齢"),("temperament","性格"),("life_status","状態")]
    private var valid:Bool {
        (1...40).contains(name.trimmingCharacters(in:.whitespacesAndNewlines).count) && breed.count<=100 && intro.count<=500 && age.count<=100 && temperament.count<=200
    }
    var body:some View {
        Form {
            Section {EditableProfileIcon(encoded:$icon,changed:$iconChanged,importing:$importingIcon)}
            Section("うちの子") {
                LabeledContent("名前") {TextField("名前を入力",text:$name).multilineTextAlignment(.trailing).accessibilityIdentifier("cloud-profile-name")}
                VStack(alignment:.leading,spacing:5) {
                    Text(pet.species=="cat" ? "猫種" : "犬種").font(.caption).foregroundStyle(Theme.secondaryText)
                    BreedAutocompleteField(species:pet.species,text:$breed,identifier:"cloud-profile-breed")
                }
                VStack(alignment:.leading,spacing:5) {
                    Text("自己紹介").font(.caption).foregroundStyle(Theme.secondaryText)
                    TextField("好きなことなど ♡",text:$intro,axis:.vertical).lineLimit(2...4)
                        .accessibilityIdentifier("cloud-profile-introduction")
                }
            }
            Section {
                DisclosureGroup("誕生日・性別など") {
                    Picker("性別",selection:$sex) {Text("未設定").tag("unknown");Text("男の子").tag("male");Text("女の子").tag("female")}
                    TextField("誕生日（例：2021-04-05）",text:$birthday).keyboardType(.numbersAndPunctuation)
                    TextField("お迎え日（例：2021-06-01）",text:$arrival).keyboardType(.numbersAndPunctuation)
                    TextField("年齢のメモ",text:$age)
                    TextField("性格",text:$temperament)
                    Picker("この子について",selection:$life) {Text("通常").tag("living");Text("シニア").tag("senior");Text("亡くなった子").tag("deceased")}
                }
                DisclosureGroup("公開する項目") {
                    Text("公開プロフィールに表示する情報を選べます。").font(.caption).foregroundStyle(Theme.secondaryText)
                    ForEach(labels,id:\.0) {field,label in Toggle(label,isOn:Binding(get:{fields.contains(field)},set:{if $0 {fields.insert(field)} else {fields.remove(field)}}))}
                }
                DisclosureGroup("アルバムの写真から選ぶ") {
                    Button("アイコン写真を選ぶ") {photoPurpose="icon";showAlbumPicker=true}
                    Button("カバー写真を選ぶ") {photoPurpose="cover";showAlbumPicker=true}
                    if !cover.isEmpty {Button("カバー写真を外す") {cover=""}}
                    Text("カバー写真は家族アルバム内だけに表示します。").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                DisclosureGroup("そっくりへの掲載") {
                    Picker("掲載する写真",selection:$twinPhoto) {Text("写真を選ぶ").tag("");ForEach(albumPhotos.filter{$0.media_kind != "video"}) {Text($0.title.isEmpty ? ($0.captured ?? "写真") : $0.title).tag($0.id)}}
                    Toggle("公開プロフィールへの掲載を確認しました",isOn:$twinConfirmed)
                    Text("他の提供者の写真は、その方のそっくり用途同意が必要です。").font(.caption)
                    Button("この写真でそっくりに参加") {Task {await client.perform {
                        if albumPhotos.first(where:{$0.id==twinPhoto})?.mine==true {try await client.consent(photo:twinPhoto,purpose:"twins",allowed:true)}
                        try await client.setPublicProfile(pet:pet.id,enabled:true,explicit:true)
                        let result=try await client.enrollTwins(pet:pet.id,photo:twinPhoto,key:twinKey)
                        twinMessage=result.state=="pending" ? "参加を受け付けました" : "参加状態を確認しました"
                    }}}.disabled(!twinConfirmed || twinPhoto.isEmpty || client.busy)
                    if let twinMessage {Text(twinMessage).font(.caption)}
                    Button("そっくりへの掲載をやめる",role:.destructive) {twinConfirmed=false;Task {await client.perform {try await client.withdrawTwins(pet:pet.id)}}}
                }
            }
            Section {
                if let error=client.error {Text(error).font(.footnote).foregroundStyle(.red)}
                if let photoError {Text(photoError).font(.caption).foregroundStyle(Theme.secondaryText)}
            }
        }.disabled(client.busy).scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("プロフィールを編集").navigationBarTitleDisplayMode(.inline).protectWhenInactive()
            .safeAreaInset(edge:.top,spacing:0) {
                if saved {
                    Label("保存したよ ♡",systemImage:"checkmark.circle.fill").font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.actionText).frame(maxWidth:.infinity).padding(.vertical,9)
                        .background(Theme.accent.opacity(0.08)).accessibilityIdentifier("cloud-profile-saved")
                }
            }
            .toolbar {ToolbarItem(placement:.topBarTrailing) {
                Button(importingIcon ? "写真を準備中…" : client.busy ? "保存中…" : "保存") {save()}
                    .fontWeight(.semibold).disabled(client.busy || importingIcon || !valid)
                    .accessibilityIdentifier("cloud-profile-save")
            }}
            .onChange(of:client.currentUserID) {_,_ in dismiss()}
            .onChange(of:twinPhoto) {_,_ in twinKey=UUID();twinConfirmed=false}
            .onChange(of:[name,breed,intro,sex,birthday,arrival,age,temperament,life,cover]) {_,_ in saved=false}
            .onChange(of:icon) {_,_ in if iconChanged {saved=false}}
            .onChange(of:fields) {_,_ in saved=false}
            .sheet(isPresented:$showAlbumPicker) {
                NavigationStack {CloudProfileAlbumPhotoPicker(photos:photoPurpose=="icon" ? albumPhotos.filter(\.mine) : albumPhotos,client:client) {photo,image in
                    if photoPurpose=="cover" {cover=photo.id}
                    else if let encoded=ProfileIconCodec.encode(image:image) {icon=encoded;iconChanged=true;familyIcon=""}
                    showAlbumPicker=false
                }}
            }
            .task {
                guard !initialized else{return};initialized=true
                name=pet.name;breed=pet.breed;intro=pet.introduction;icon=pet.icon
                let d=pet.details ?? [:]
                sex=d["sex"] ?? "unknown";birthday=d["birthday"] ?? "";arrival=d["arrival"] ?? "";age=d["age_basis"] ?? "";temperament=d["temperament"] ?? "";life=d["life_status"] ?? "living"
                familyIcon=d["icon_photo"] ?? "";cover=d["cover_photo"] ?? "";fields=Set(pet.public_fields ?? ["breed","introduction"])
                do {albumPhotos=try await client.albumPhotos(pet:pet.id)} catch {photoError="アルバムの写真を読み込めませんでした"}
                if icon==nil,!familyIcon.isEmpty,let image=try? await client.privatePhotoForDeviceSave(familyIcon),!iconChanged {icon=ProfileIconCodec.encode(image:image)}
            }
    }
    private func save() {
        Task {await client.perform {
            var details=["sex":sex,"age_basis":age,"temperament":temperament,"life_status":life]
            if !birthday.isEmpty {details["birthday"]=birthday};if !arrival.isEmpty {details["arrival"]=arrival}
            if !familyIcon.isEmpty,!iconChanged {details["icon_photo"]=familyIcon};if !cover.isEmpty {details["cover_photo"]=cover}
            let selectedBreed=PetBreedCatalog.canonical(breed,species:pet.species) ?? breed.trimmingCharacters(in:.whitespacesAndNewlines)
            try await client.updatePetProfile(pet,name:name,breed:selectedBreed,introduction:intro,details:details,publicFields:fields.sorted(),icon:icon,iconChanged:iconChanged)
            if iconChanged {familyIcon=""}
            iconChanged=false;saved=true
        }}
    }
}

private struct CloudProfileAlbumPhotoPicker:View {
    let photos:[CloudPhoto]
    @ObservedObject var client:CloudFamilyClient
    let onPick:(CloudPhoto,UIImage)->Void
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        ScrollView {
            if photos.filter({$0.media_kind != "video"}).isEmpty {ContentUnavailableView("写真はまだありません",systemImage:"photo",description:Text("アイコンは「写真を変更」からも選べます"))}
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
                ForEach(photos.filter{$0.media_kind != "video"}) {photo in
                    CloudProfileAlbumPhoto(photo:photo,client:client,onPick:onPick)
                }
            }.padding(12)
        }.background(Theme.background).navigationTitle("写真を選ぶ").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("閉じる") {dismiss()}}}
    }
}
private struct CloudProfileAlbumPhoto:View {
    let photo:CloudPhoto
    @ObservedObject var client:CloudFamilyClient
    let onPick:(CloudPhoto,UIImage)->Void
    @State private var image:UIImage?
    var body:some View {
        Button {if let image {onPick(photo,image)}} label: {
            GeometryReader {geometry in
                ZStack {
                    RoundedRectangle(cornerRadius:12).fill(Theme.accent.opacity(0.08))
                    if let image {Image(uiImage:image).resizable().scaledToFill().frame(width:geometry.size.width,height:geometry.size.height).clipped()}
                    else {Image(systemName:"pawprint.fill").foregroundStyle(Theme.accent)}
                }.clipShape(RoundedRectangle(cornerRadius:12))
            }.aspectRatio(1,contentMode:.fit)
        }.buttonStyle(.plain).disabled(image==nil).accessibilityLabel("この写真を選ぶ")
            .task {image=try? await client.privatePhotoForDeviceSave(photo.id)}
    }
}

enum PetBreedCatalog {
    private static let dogs="柴犬|秋田犬|北海道犬|甲斐犬|紀州犬|四国犬|日本スピッツ|トイ・プードル|ミニチュア・プードル|スタンダード・プードル|チワワ|ポメラニアン|ミニチュア・ダックスフンド|カニーンヘン・ダックスフンド|ダックスフンド|ミニチュア・シュナウザー|マルチーズ|フレンチ・ブルドッグ|ブルドッグ|ヨークシャー・テリア|ビション・フリーゼ|シー・ズー|ゴールデン・レトリーバー|ラブラドール・レトリーバー|パグ|ウェルシュ・コーギー・ペンブローク|ボーダー・コリー|ペキニーズ|ジャック・ラッセル・テリア|パピヨン|キャバリア・キング・チャールズ・スパニエル|ビーグル|シベリアン・ハスキー|サモエド|シェットランド・シープドッグ|コーイケルホンディエ|イタリアン・グレーハウンド|ボストン・テリア|ミニチュア・ピンシャー|ドーベルマン|ジャーマン・シェパード・ドッグ|バーニーズ・マウンテン・ドッグ|ボクサー|ロットワイラー|ダルメシアン|グレート・ピレニーズ|セント・バーナード|アメリカン・コッカー・スパニエル|イングリッシュ・コッカー・スパニエル|ミックス犬".components(separatedBy:"|")
    private static let cats="アビシニアン|アメリカン・カール|アメリカン・ショートヘア|アメリカン・ボブテイル|エキゾチック・ショートヘア|エジプシャン・マウ|オシキャット|オリエンタル・ショートヘア|コーニッシュ・レックス|サイベリアン|シャム|シャルトリュー|シンガプーラ|スコティッシュ・フォールド|スノーシュー|スフィンクス|セルカーク・レックス|ソマリ|ターキッシュ・アンゴラ|デボン・レックス|トンキニーズ|ノルウェージャン・フォレスト・キャット|バーマン|バーミーズ|バリニーズ|ヒマラヤン|ブリティッシュ・ショートヘア|ブリティッシュ・ロングヘア|ベンガル|ペルシャ|ボンベイ|マンチカン|ミヌエット|メイン・クーン|ラグドール|ラガマフィン|ロシアン・ブルー|日本猫|ミックス猫".components(separatedBy:"|")
    private static let aliases:[String:String]=[
        "しば":"柴犬","柴":"柴犬","といぷー":"トイ・プードル","トイプー":"トイ・プードル",
        "ミニチュアダックス":"ミニチュア・ダックスフンド","コーギー":"ウェルシュ・コーギー・ペンブローク",
        "ゴールデン":"ゴールデン・レトリーバー","ラブラドール":"ラブラドール・レトリーバー",
        "スコティッシュ":"スコティッシュ・フォールド","アメショ":"アメリカン・ショートヘア",
        "ノルウェージャン":"ノルウェージャン・フォレスト・キャット","ブリショ":"ブリティッシュ・ショートヘア",
        "メイクーン":"メイン・クーン","雑種":"ミックス犬","キジトラ":"日本猫"
    ]
    static func names(for species:String)->[String] {species=="cat" ? cats : dogs}
    private static func key(_ value:String)->String {
        let katakana=value.applyingTransform(.hiraganaToKatakana,reverse:false) ?? value
        return katakana.lowercased().filter{!$0.isWhitespace && !"・ー-・･".contains($0)}
    }
    static func canonical(_ value:String,species:String)->String? {
        let query=key(value)
        guard !query.isEmpty else {return nil}
        if query==key("ミックス") || query==key("雑種") {return species=="cat" ? "ミックス猫" : "ミックス犬"}
        let mapped=aliases.first{$0.key == value || key($0.key)==query}?.value
        return names(for:species).first{key($0)==key(mapped ?? value)}
    }
    static func suggestions(for value:String,species:String)->[String] {
        let names=names(for:species),query=key(value)
        guard !query.isEmpty else {return Array(names.prefix(6))}
        if query==key("ミックス") || query==key("雑種") {return [species=="cat" ? "ミックス猫" : "ミックス犬"]}
        let aliasTargets=aliases.filter{key($0.key).contains(query)}.map(\.value)
        let prefixMatches=names.filter{key($0).hasPrefix(query) || aliasTargets.contains($0)}
        let otherMatches=names.filter{key($0).contains(query) && !prefixMatches.contains($0)}
        return Array((prefixMatches+otherMatches).prefix(6))
    }
}

struct PetSpeciesSelectionField:View {
    @Binding var species:String
    @Binding var selected:Bool
    var body:some View {
        if selected {
            HStack {
                Text(species=="cat" ? "🐱 猫" : "🐶 犬").font(.headline)
                    .accessibilityIdentifier("pet-species-selected")
                Spacer()
                Button("変更") {selected=false}
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.actionText)
                    .frame(minHeight:44).buttonStyle(.borderless)
                    .accessibilityLabel("犬・猫を選び直す")
                    .accessibilityIdentifier("pet-species-change")
            }
        } else {
            VStack(alignment:.leading,spacing:10) {
                Text("犬・猫を選んでね").font(.subheadline.weight(.semibold))
                HStack(spacing:12) {
                    choice("dog",emoji:"🐶",name:"犬")
                    choice("cat",emoji:"🐱",name:"猫")
                }
            }.padding(.vertical,6)
        }
    }
    private func choice(_ value:String,emoji:String,name:String)->some View {
        Button {species=value;selected=true} label: {
            HStack(spacing:8) {
                Text(emoji).font(.system(size:30))
                Text(name).font(.headline)
            }.foregroundStyle(Theme.actionText).frame(maxWidth:.infinity,minHeight:66)
                .background(Theme.accent.opacity(0.09),in:RoundedRectangle(cornerRadius:16))
                .overlay {RoundedRectangle(cornerRadius:16).strokeBorder(Theme.accent.opacity(0.25),lineWidth:1)}
        }.buttonStyle(.borderless).accessibilityLabel(name+"を選ぶ")
            .accessibilityIdentifier("pet-species-"+value)
    }
}

struct BreedAutocompleteField:View {
    let species:String
    @Binding var text:String
    let identifier:String
    @FocusState private var focused:Bool
    @State private var showingSuggestions=false
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            TextField(species=="cat" ? "猫種" : "犬種",text:$text)
                .focused($focused).accessibilityIdentifier(identifier)
                .onSubmit {normalize();showingSuggestions=false;focused=false}
                .onChange(of:focused) {_,isFocused in
                    if isFocused {showingSuggestions=true}
                    else {
                        Task { @MainActor in
                            try? await Task.sleep(for:.seconds(1))
                            if !focused {normalize();showingSuggestions=false}
                        }
                    }
                }
            if showingSuggestions {
                let matches=PetBreedCatalog.suggestions(for:text,species:species)
                if !matches.isEmpty {
                    ForEach(matches,id:\.self) {name in
                        Button {text=name;showingSuggestions=false;focused=false} label: {
                            HStack {Image(systemName:"pawprint.fill").font(.caption);Text(name);Spacer();Image(systemName:"checkmark.circle").font(.caption)}
                                .foregroundStyle(Theme.actionText).frame(minHeight:38)
                        }.buttonStyle(.borderless).accessibilityIdentifier("breed-suggestion-"+name)
                    }
                } else {
                    Text("候補にない場合は、そのまま入力できます ♡")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
    private func normalize() {if let canonical=PetBreedCatalog.canonical(text,species:species) {text=canonical}}
}

struct CloudPhotoEditor:View {
    let photo:CloudPhoto;let pet:String
    @ObservedObject var client:CloudFamilyClient
    @State private var captured=""
    @State private var title=""
    @State private var kind=""
    @State private var note=""
    @State private var saved=false
    var body:some View {
        Form {
            if let image=client.images[photo.id] {PhotoHero(image:image,height:220)}
            TextField("撮影日・空欄は不明",text:$captured)
            TextField("タイトル",text:$title)
            Picker("節目",selection:$kind) {Text("なし").tag("");ForEach(CloudEventsView.kinds,id:\.0) {Text($0.1).tag($0.0)}}
            TextField("メモ（200字まで）",text:$note,axis:.vertical)
            Button("写真の情報を保存") {Task {await client.perform {try await client.editPhoto(photo,pet:pet,captured:captured.isEmpty ? nil : captured,title:title,kind:kind.isEmpty ? nil : kind,note:note);saved=true}}}
            if saved {Text("保存しました")};if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("写真・節目を編集").protectWhenInactive().task {captured=photo.captured ?? "";title=photo.title;kind=photo.event_kind ?? "";note=photo.note ?? ""}
    }
}

struct CloudEventsView:View {
    static let kinds=[("birthday","誕生日"),("anniversary","うちの子記念日"),("arrival","お迎えした日"),("hospital","通院"),("other","その他")]
    let pet:CloudPet
    @ObservedObject var client:CloudFamilyClient
    @State private var events:[CloudEvent]=[]
    @State private var captured=""
    @State private var title=""
    @State private var kind="birthday"
    @State private var note=""
    @State private var key=UUID()
    @State private var deleting:String?
    @State private var editing:CloudEvent?
    var body:some View {
        Form {
            Section("節目を残す") {
                Picker("種類",selection:$kind) {ForEach(Self.kinds,id:\.0) {Text($0.1).tag($0.0)}}
                TextField("日付・空欄は不明",text:$captured)
                TextField("タイトル（30字まで）",text:$title).accessibilityIdentifier("cloud-event-title")
                TextField("メモ（200字まで）",text:$note,axis:.vertical)
                Button("節目を保存") {let requestKey=key;Task {await client.perform {try await client.saveEvent(pet:pet.id,key:requestKey,captured:captured.isEmpty ? nil : captured,title:title,kind:kind,note:note);events=try await client.events(pet:pet.id);title="";note="";key=UUID()}}}.disabled(client.busy || title.isEmpty).accessibilityIdentifier("cloud-event-save")
            }
            Section("家族だけの節目") {ForEach(events) {event in VStack(alignment:.leading) {Text(event.title).font(.headline);Text(event.captured ?? "日付不明");Text(event.note);if event.mine {Button("この節目を編集") {editing=event};Button("この節目を削除",role:.destructive) {deleting=event.id}}}}}
            Section {NavigationLink("通知設定") {CloudNotificationSettingsView(client:client)}}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("記念日").protectWhenInactive()
        .task {await client.performRefresh {events=try await client.events(pet:pet.id)}}
        .onChange(of:captured) {_,_ in key=UUID()}.onChange(of:title) {_,_ in key=UUID()}.onChange(of:kind) {_,_ in key=UUID()}.onChange(of:note) {_,_ in key=UUID()}
        .sheet(item:$editing,onDismiss:{Task {await client.perform {events=try await client.events(pet:pet.id)}}}) {event in NavigationStack {CloudMilestoneEditor(event:event,client:client)}}
        .confirmationDialog("この節目を削除しますか？",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}})) {Button("削除",role:.destructive) {if let id=deleting {Task {await client.perform {try await client.deleteEvent(id);events=try await client.events(pet:pet.id)}}};deleting=nil}}
    }
}

struct CloudMilestoneEditor:View {
    let event:CloudEvent
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var note=""
    @State private var captured=""
    @State private var kind="other"
    var body:some View {Form {TextField("タイトル",text:$title);TextField("日付・空欄は不明",text:$captured);Picker("種類",selection:$kind) {ForEach(CloudEventsView.kinds,id:\.0) {Text($0.1).tag($0.0)}};TextField("メモ",text:$note,axis:.vertical);Button("変更を保存") {Task {await client.perform {try await client.editEvent(event.id,captured:captured.isEmpty ? nil : captured,title:title,kind:kind,note:note);dismiss()}}}.disabled(client.busy || title.isEmpty || title.count>30 || note.count>200);if let error=client.error {Text(error).foregroundStyle(.red)}}.navigationTitle("節目を編集").toolbar {ToolbarItem(placement:.cancellationAction) {Button("キャンセル") {dismiss()}}}.protectWhenInactive().task {title=event.title;note=event.note;captured=event.captured ?? "";kind=event.kind}}
}
