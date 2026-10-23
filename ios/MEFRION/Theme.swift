import SwiftUI

enum Theme {
    // Generated from design/tokens/tokens.json. Run scripts/sync_tokens.py to update.
    static let background = Color(red: 1.000000, green: 0.988235, blue: 0.972549)
    static let accent = Color(red: 0.964706, green: 0.325490, blue: 0.349020)
    static let actionText = Color(red:0.709804,green:0.180392,blue:0.223529)
    static let secondaryText = Color(red:0.384314,green:0.349020,blue:0.337255)
    static let text = Color(red: 0.160784, green: 0.149020, blue: 0.145098)
    static let spacing: CGFloat = 16
    static let radius: CGFloat = 20
}

struct BrandWordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("MEFRION").font(.system(size: 25, weight: .heavy, design: .rounded)).italic()
                Image(systemName: "pawprint.fill").font(.system(size: 20))
            }
            Text("いっしょに、もっと幸せに。").font(.system(size: 8, weight: .medium))
        }.foregroundStyle(Theme.accent).accessibilityElement(children: .combine)
    }
}

struct CoralButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold()).foregroundStyle(.white)
            .padding(.horizontal, 20).frame(minHeight: 44)
            .background(Theme.actionText)
            .clipShape(Capsule()).opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// A small, branded waiting state for public photos and the public feed.
struct PawLoadingView: View {
    var title: String = "写真を準備中"
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: compact ? 25 : 34, weight: .medium))
                .foregroundStyle(Theme.actionText)
                .frame(width: compact ? 54 : 72, height: compact ? 54 : 72)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .overlay { Circle().stroke(Theme.accent.opacity(0.18), lineWidth: 1) }
                .scaleEffect(pulsing && !reduceMotion ? 1.1 : 0.94)
                .opacity(pulsing && !reduceMotion ? 1 : 0.72)
            Text(title)
                .font(compact ? .caption : .subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulsing = true }
        }
    }
}

private struct BackgroundPrivacyCover:ViewModifier {
    var enabled = true
    func body(content:Content)->some View {
        content
    }
}
extension View {
    func protectWhenInactive(_ enabled:Bool=true)->some View {modifier(BackgroundPrivacyCover(enabled:enabled))}
}

enum PostTime {
    static func label(_ value:String?)->String {
        guard let value,!value.isEmpty else {return ""}
        let parser=ISO8601DateFormatter()
        parser.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        let date=parser.date(from:value) ?? {
            parser.formatOptions=[.withInternetDateTime]
            return parser.date(from:value)
        }()
        guard let date else {return String(value.prefix(10))}
        let seconds=max(0,Int(Date().timeIntervalSince(date)))
        if seconds<60 {return "たった今"}
        if seconds<3600 {return "\(seconds/60)分前"}
        if seconds<86400 {return "\(seconds/3600)時間前"}
        if seconds<604800 {return "\(seconds/86400)日前"}
        let format=DateFormatter();format.locale=Locale(identifier:"ja_JP");format.dateFormat="yyyy年M月d日"
        return format.string(from:date)
    }
}

/// The title stays centered independently of the trailing controls.
struct CompactHomeHeader<Actions:View>:View {
    @ViewBuilder var actions:Actions
    var body:some View {
        ZStack {
            Text("MEFRION").font(.system(size:18,weight:.semibold)).foregroundStyle(Theme.text)
                .accessibilityIdentifier("home-compact-brand")
            HStack(spacing:0) {Spacer();actions}
        }.frame(height:44)
    }
}

/// A completed horizontal swipe changes the selection; vertical scrolling stays available.
struct HorizontalTabSwipe:ViewModifier {
    var enabled:Bool=true
    var change:(Bool)->Void
    func body(content:Content)->some View {
        content.simultaneousGesture(DragGesture(minimumDistance:30).onEnded {value in
            guard enabled,abs(value.translation.width)>60,
                  abs(value.translation.width)>abs(value.translation.height)*1.5 else {return}
            withAnimation(.easeInOut(duration:0.2)) {change(value.translation.width<0)}
        })
    }
}

private struct RootTabSwipeKey:EnvironmentKey {
    static let defaultValue:(Bool)->Void = {_ in}
}
extension EnvironmentValues {
    var rootTabSwipe:(Bool)->Void {
        get {self[RootTabSwipeKey.self]}
        set {self[RootTabSwipeKey.self]=newValue}
    }
}

/// Observe horizontal paging without installing a SwiftUI drag recognizer that
/// can consume vertical drags inside a paged TabView nested in a feed ScrollView.
struct HorizontalPanObserver:UIViewRepresentable {
    let onChange:(Bool)->Void
    func makeUIView(context:Context)->Probe {let view=Probe();view.onChange=onChange;return view}
    func updateUIView(_ view:Probe,context:Context) {view.onChange=onChange}
    final class Probe:UIView,UIGestureRecognizerDelegate {
        var onChange:((Bool)->Void)?
        private weak var observedWindow:UIWindow?
        private var pan:UIPanGestureRecognizer?
        private var tracking=false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let pan {observedWindow?.removeGestureRecognizer(pan)}
            pan=nil;observedWindow=window
            if tracking {tracking=false;onChange?(false)}
            guard let window else{return}
            let next=UIPanGestureRecognizer(target:self,action:#selector(changed(_:)))
            next.cancelsTouchesInView=false;next.delaysTouchesBegan=false;next.delaysTouchesEnded=false
            next.maximumNumberOfTouches=1;next.delegate=self
            window.addGestureRecognizer(next);pan=next
        }
        func gestureRecognizer(_ recognizer:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool {
            guard let window, !isHidden,alpha>0.01 else{return false}
            return convert(bounds,to:window).contains(touch.location(in:window))
        }
        override func gestureRecognizerShouldBegin(_ recognizer:UIGestureRecognizer)->Bool {
            guard let pan=recognizer as? UIPanGestureRecognizer else{return false}
            let velocity=pan.velocity(in:window)
            return abs(velocity.x)>abs(velocity.y)*1.2
        }
        func gestureRecognizer(_ recognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith other:UIGestureRecognizer)->Bool {true}
        @objc private func changed(_ pan:UIPanGestureRecognizer) {
            if pan.state == .began {tracking=true;onChange?(true)}
            else if tracking && [.ended,.cancelled,.failed].contains(pan.state) {tracking=false;onChange?(false)}
        }
    }
}
