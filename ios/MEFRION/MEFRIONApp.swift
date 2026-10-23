import SwiftUI

@main
struct MEFRIONApp: App {
    @StateObject private var store = PrototypeStore(storageURL: ProcessInfo.processInfo.arguments.contains("--ui-test-isolated") || ProcessInfo.processInfo.arguments.contains("--twins-vision-self-check") ? nil : PrototypeStore.deviceStorageURL)
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store).tint(Theme.actionText) }
    }
}

struct RootView: View {
    @AppStorage("MEFRIONHasStarted") private var hasStarted=false
    private struct PendingInvite:Identifiable {let id=UUID();let token:String}
    @State private var pendingInvite:PendingInvite?

    @State private var selected=0
    @State private var homeRefreshID=0
    @State private var albumRefreshID=0
    @State private var startedThisRun=false
    @State private var keyboardVisible=false
    private let tabs=[("ホーム","house"),("アルバム","photo.on.rectangle"),("投稿","plus"),("そっくり","pawprint"),("マイページ","person")]
    var body:some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--twins-vision-self-check") {TwinsVisionSelfCheckView()}
            else if ProcessInfo.processInfo.arguments.contains("--ui-test-isolated"),ProcessInfo.processInfo.arguments.contains("--ui-reference-gallery") {NavigationStack {UIReferenceGallery()}}
            else {standardContent}
            #else
            standardContent
            #endif
        }.task {if useCloud && !ProcessInfo.processInfo.arguments.contains("--twins-vision-self-check") {await CloudFamilyClient.shared.restore()}}.protectWhenInactive(selected != 0).onOpenURL {url in
            guard url.scheme=="mefrion",url.host=="family",let token=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="token"})?.value,!token.isEmpty,token.count<=512 else{return}
            pendingInvite=PendingInvite(token:token)
        }.sheet(item:$pendingInvite) {invitation in NavigationStack {FamilyInvitationAcceptView(token:invitation.token).toolbar {ToolbarItem(placement:.cancellationAction) {Button("今回はスキップ") {pendingInvite=nil}}}}}
    }
    private var standardContent:some View {
        Group {
            if (ProcessInfo.processInfo.arguments.contains("--ui-test-onboarding") && !startedThisRun) || (!hasStarted && !ProcessInfo.processInfo.arguments.contains("--ui-test-isolated")) {
                WelcomeFlowView {hasStarted=true;startedThisRun=true}
            } else {mainTabs}
        }
    }
    private var useCloud:Bool { !ProcessInfo.processInfo.arguments.contains("--ui-test-isolated") || ProcessInfo.processInfo.arguments.contains("--appstore-screenshots") || ProcessInfo.processInfo.environment["MEFRION_TEST_USE_CLOUD"]=="1" }
    private func moveTab(_ towardRight:Bool) {
        selected=min(tabs.count-1,max(0,selected+(towardRight ? 1 : -1)))
    }
    private var mainTabs:some View {
        TabView(selection:$selected) {
            NavigationStack { Group {if useCloud {CloudDiscoveryView(client:CloudFamilyClient.shared,integrated:true,homeRefreshID:homeRefreshID)} else {HomeView()}} }.tabItem {Label("ホーム",systemImage:"house")} .tag(0)
            NavigationStack { Group {if useCloud {CloudAlbumLibraryView(refreshID:albumRefreshID)} else {PrivateAlbumLibraryView()}} }.modifier(HorizontalTabSwipe {towardRight in moveTab(towardRight)}).tabItem {Label("アルバム",systemImage:"photo.on.rectangle")} .tag(1)
            NavigationStack { Group {if useCloud {CloudUnifiedComposer()} else {AlbumComposer()}} }.tabItem {Label("投稿",systemImage:"plus.circle")} .tag(2)
            NavigationStack { Group {if !ProcessInfo.processInfo.arguments.contains("--ui-test-isolated") || ProcessInfo.processInfo.arguments.contains("--ui-stock-twins") || ProcessInfo.processInfo.arguments.contains("--appstore-screenshots") {ReferenceTwinsView()} else if useCloud {CloudTwinsView()} else {TwinsView()}} }.modifier(HorizontalTabSwipe {towardRight in moveTab(towardRight)}).tabItem {Label("そっくり",systemImage:"pawprint")} .tag(3)
            NavigationStack { Group {if useCloud {CloudAccountPage()} else {MyPage()}} }.modifier(HorizontalTabSwipe {towardRight in moveTab(towardRight)}).tabItem {Label("マイページ",systemImage:"person")} .tag(4)
        }.toolbar(.hidden,for:.tabBar).safeAreaInset(edge:.bottom,spacing:0) {
            if !keyboardVisible {HStack(spacing:0) {
                ForEach(0..<tabs.count,id:\.self) {index in
                    Button {
                        if index==0 && selected==0 {homeRefreshID &+= 1}
                        else {selected=index}
                    } label: {
                        VStack(spacing:2) {
                            if index==2 {
                                Image(systemName:"plus").font(.system(size:22,weight:.medium)).foregroundStyle(.white)
                                    .frame(width:36,height:36).background(Theme.accent.gradient).clipShape(Circle())
                            } else {
                                Image(systemName:tabs[index].1+(selected==index ? ".fill" : ""))
                                    .font(.system(size:21)).frame(height:34)
                            }
                            Text(tabs[index].0).font(.caption2.weight(selected==index ? .semibold : .regular)).dynamicTypeSize(...DynamicTypeSize.xxxLarge).fixedSize(horizontal:false,vertical:true)
                        }.foregroundStyle(selected==index ? Theme.actionText : Theme.text).frame(maxWidth:.infinity).frame(minHeight:52)
                    }.accessibilityLabel(tabs[index].0).accessibilityIdentifier("root-tab-"+tabs[index].0)
                        .accessibilityAddTraits(selected==index ? .isSelected : [])
                }
            }.modifier(HorizontalTabSwipe {towardRight in moveTab(towardRight)}).padding(.horizontal,8).background(.white).overlay(alignment:.top) {Rectangle().fill(Color(.systemGray5)).frame(height:0.5)}}
        }.environment(\.rootTabSwipe) {towardRight in moveTab(towardRight)}
            .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillShowNotification)) {_ in keyboardVisible=true}
            .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillHideNotification)) {_ in keyboardVisible=false}
            .onChange(of:selected) {_,next in
                if useCloud && [0,3].contains(next) {CloudFamilyClient.shared.clearPrivateViews()}
                if next==1 {albumRefreshID &+= 1}
            }
    }
}
