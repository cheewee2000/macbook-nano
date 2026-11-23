import SwiftUI
import CoreText

/// Folded (cover display, or any ordinary iPhone) stays portrait; rotation only on the unfolded inner display.
/// Same test as the other CW&T apps: the Duo's inner display is the only iPhone screen whose short side is ≥ 490 pt.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        let size = window?.bounds.size ?? .zero
        return min(size.width, size.height) >= 490 ? .all : .portrait
    }
}

@main
struct MacbookNanoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        if let u = Bundle.main.url(forResource: "SpaceMono-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)
        }
    }
    var body: some Scene {
        WindowGroup { Root().preferredColorScheme(.light).tint(.black) }
    }
}

func mono(_ size: CGFloat) -> Font { .custom("SpaceMono-Regular", size: size) }

struct Root: View {
    @StateObject private var mac = Mac()
    @Environment(\.scenePhase) private var phase
    @AppStorage("host") private var host = ""
    @AppStorage("user") private var user = ""

    var body: some View {
        Group {
            if mac.status == .connected { Laptop(mac: mac) } else { Connect(mac: mac) }
        }
        .background(.white)
        // Opening the app is opening the lid: reconnect to the saved Mac. iOS drops the socket in the background.
        .onChange(of: phase, initial: true) { _, p in
            guard p == .active, mac.status != .connected, mac.status != .connecting, !host.isEmpty else { return }
            mac.connect(host: host, user: user, password: Keychain.get(account: "\(user)@\(host)") ?? "")
        }
        .onChange(of: mac.status == .connected, initial: true) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
    }
}

/// The mini MacBook: the Mac's screen above the hinge, a MacBook Pro's deck (keyboard, trackpad) below it.
/// The hinge is the middle of the whole window, so the split is measured with the safe areas included.
struct Laptop: View {
    @ObservedObject var mac: Mac

    var body: some View {
        GeometryReader { g in
            let inset = g.safeAreaInsets
            let w = g.size.width + inset.leading + inset.trailing, h = g.size.height + inset.top + inset.bottom
            Group {
                if w > h {
                    // on its side the hinge is vertical, no laptop to be had: all screen, touch it to click
                    Screen(mac: mac)
                } else {
                    VStack(spacing: 0) {
                        Screen(mac: mac).frame(height: h / 2)
                        Deck(mac: mac, bottomInset: inset.bottom)
                    }
                }
            }
            .frame(width: w, height: h)
            .background(.black)                  // the lid's bezel, around a Mac screen that is not the lid's shape
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)              // the iOS keyboard sliding away after sign-in must not squeeze the laptop
        .statusBarHidden()                       // no bar over the Mac's screen: the lid is all Mac, to the top edge
        .defersSystemGestures(on: .bottom)       // trackpad strokes near the bottom edge are not "go home"
        .persistentSystemOverlays(.hidden)
    }
}

/// The lower half of a MacBook Pro: aluminium, the black keyboard well, the glass trackpad centred under it.
struct Deck: View {
    let mac: Mac
    let bottomInset: CGFloat

    var body: some View {
        GeometryReader { g in
            let margin = g.size.width * 0.014, well = g.size.width * 0.006
            let unit = (g.size.width - 2 * (margin + well)) / 14.5
            let pad = RoundedRectangle(cornerRadius: unit * 0.22, style: .continuous)
            VStack(spacing: 0) {
                Keyboard(mac: mac, unit: unit)
                    .padding(well)
                    .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: unit * 0.2, style: .continuous))
                    .padding([.horizontal, .top], margin)
                Trackpad(mac: mac)
                    .background(Color(white: 0.80), in: pad)
                    .overlay(pad.strokeBorder(Color(white: 0.66), lineWidth: 1))
                    .clipShape(pad)
                    .frame(width: g.size.width * 0.46)   // a MacBook Pro's trackpad is a little under half the deck
                    .padding(.top, margin)
                    .padding(.bottom, max(margin, bottomInset))
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(white: 0.84))
    }
}

/// Where the Mac's picture sits inside the screen area: aspect-fit × zoom, with Mac pixel `center` in the middle.
func viewport(container: CGSize, screen: CGSize, zoom: CGFloat, center: CGPoint) -> CGRect {
    guard screen.width > 0, screen.height > 0 else { return .zero }
    let scale = min(container.width / screen.width, container.height / screen.height) * zoom
    func origin(_ content: CGFloat, _ box: CGFloat, _ c: CGFloat) -> CGFloat {
        content <= box ? (box - content) / 2 : box / 2 - c * scale
    }
    let size = CGSize(width: screen.width * scale, height: screen.height * scale)
    return CGRect(origin: CGPoint(x: origin(size.width, container.width, center.x),
                                  y: origin(size.height, container.height, center.y)), size: size)
}

/// A view centre that never shows past the Mac screen's edges. `visible` is the size of the view in Mac pixels.
func clamped(center: CGPoint, screen: CGSize, visible: CGSize) -> CGPoint {
    func axis(_ c: CGFloat, _ s: CGFloat, _ v: CGFloat) -> CGFloat { v >= s ? s / 2 : min(max(c, v / 2), s - v / 2) }
    return CGPoint(x: axis(center.x, screen.width, visible.width), y: axis(center.y, screen.height, visible.height))
}

/// The view follows the pointer: it stays still while the pointer is in the middle 80% and is pushed along at the edges.
func following(_ pointer: CGPoint, center: CGPoint, visible: CGSize) -> CGPoint {
    func axis(_ p: CGFloat, _ c: CGFloat, _ v: CGFloat) -> CGFloat { min(max(c, p - v * 0.4), p + v * 0.4) }
    return CGPoint(x: axis(pointer.x, center.x, visible.width), y: axis(pointer.y, center.y, visible.height))
}

/// The Mac's screen. Pinch to zoom, two fingers to pan, tap to click right there.
struct Screen: View {
    @ObservedObject var mac: Mac

    var body: some View {
        GeometryReader { g in
            let r = viewport(container: g.size, screen: mac.size, zoom: mac.zoom, center: mac.center)
            let scale = mac.size.width > 0 ? r.width / mac.size.width : 1
            ZStack(alignment: .topLeading) {
                LayerView(layer: mac.layer).frame(width: r.width, height: r.height)
                if let c = mac.cursorImage {
                    Image(decorative: c, scale: 1 / scale)
                        .offset(x: (mac.cursor.x - mac.cursorHotspot.x) * scale, y: (mac.cursor.y - mac.cursorHotspot.y) * scale)
                }
            }
            .offset(x: r.minX, y: r.minY)
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipped()
            .overlay { ScreenTouch(mac: mac) }
            .onChange(of: g.size, initial: true) { _, size in mac.viewSize = size }
        }
    }
}

/// Touches on the Mac's screen. UIKit, because SwiftUI has no two-finger pan.
struct ScreenTouch: UIViewRepresentable {
    let mac: Mac

    func makeCoordinator() -> Touch { Touch(mac) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(), c = context.coordinator
        v.isMultipleTouchEnabled = true
        v.accessibilityIdentifier = "screen"
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Touch.pan))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        for g in [UITapGestureRecognizer(target: c, action: #selector(Touch.tap)),
                  UIPinchGestureRecognizer(target: c, action: #selector(Touch.pinch)), pan] {
            g.delegate = c
            v.addGestureRecognizer(g)
        }
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {}

    final class Touch: NSObject, UIGestureRecognizerDelegate {
        let mac: Mac
        init(_ mac: Mac) { self.mac = mac }

        // pinch and pan are one gesture to the hand: both at once
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        @objc func tap(_ g: UITapGestureRecognizer) { mac.click(at: g.location(in: g.view)) }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            mac.pinch(by: g.scale, at: g.location(in: g.view))
            g.scale = 1
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            mac.pan(by: g.translation(in: g.view))
            g.setTranslation(.zero, in: g.view)
        }
    }
}

struct LayerView: UIViewRepresentable {
    let layer: CALayer

    final class Host: UIView {
        var hosted: CALayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            hosted?.frame = bounds
            CATransaction.commit()
        }
    }

    func makeUIView(context: Context) -> Host {
        let v = Host()
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear
        v.hosted = layer
        v.layer.addSublayer(layer)
        return v
    }

    func updateUIView(_ v: Host, context: Context) {}
}

/// The ID label comes from https://label.cwandt.com (never invented here).
let idLabel = "CWT_STENGM0_2610"
let idLabelExpansion = "(S)oft (T)iny (E)lectrons (N)n/a di(G)ital (M)ake (0)1 · 2610 = date"

struct Connect: View {
    @ObservedObject var mac: Mac
    @AppStorage("host") private var host = ""
    @AppStorage("user") private var user = ""
    @State private var password = ""

    var body: some View {
        // A ScrollView, so the keyboard coming up scrolls the form instead of squeezing the text into one line.
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("MACBOOK NANO").font(mono(24))
            Text("Your Mac, in your pocket. On the Mac, turn on System Settings → General → Sharing → Screen Sharing, then sign in here with your Mac login. Host is its name or address, like mac-mini.local.")
                .font(mono(13)).lineSpacing(6)
            field("HOST", TextField("", text: $host).keyboardType(.URL).accessibilityIdentifier("host"))
            field("USER", TextField("", text: $user).accessibilityIdentifier("user"))
            // .oneTimeCode: the one content type that stops iOS offering "Save Password?", which lands on top of
            // the Mac keyboard the moment the session opens. The password is already in this app's Keychain.
            field("PASSWORD", SecureField("", text: $password).textContentType(.oneTimeCode).accessibilityIdentifier("password"))
            Button {
                // a suggestion tapped on the keyboard leaves a trailing space, which the Mac takes as part of the name
                host = host.trimmingCharacters(in: .whitespaces); user = user.trimmingCharacters(in: .whitespaces)
                Keychain.set(password, account: "\(user)@\(host)")
                // put the iOS keyboard away now: left up, it is still sliding off the Mac keyboard when the session opens
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                mac.connect(host: host, user: user, password: password)
            } label: {
                Text(mac.status == .connecting ? "CONNECTING" : "CONNECT").font(mono(12)).tracking(0.5)
                    .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14).background(.black)
            }
            .disabled(host.isEmpty || mac.status == .connecting)
            if case .failed(let why) = mac.status {
                Text("ERROR").font(mono(12)).foregroundStyle(Color(red: 0.843, green: 0.173, blue: 0.051))
                Text(why).font(mono(13)).lineSpacing(6)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(idLabel).tracking(0.84)
                Text(idLabelExpansion)
                Text("V" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
            }
            .font(mono(12)).padding(.top, 24)
        }
        .foregroundStyle(.black)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .padding(24)
        .frame(maxWidth: 560, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { password = Keychain.get(account: "\(user)@\(host)") ?? "" }
    }

    private func field(_ label: String, _ input: some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(mono(12)).tracking(0.5)
            input.font(mono(16)).padding(10).border(.black, width: 2)
        }
    }
}
