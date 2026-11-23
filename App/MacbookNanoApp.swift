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

/// The mini MacBook: the Mac's screen above the hinge, keyboard and trackpad below it.
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
                    Screen(mac: mac).padding(.top, inset.top)
                } else {
                    VStack(spacing: 0) {
                        Screen(mac: mac).padding(.top, inset.top).frame(height: h / 2)
                        Keyboard(mac: mac).frame(height: h / 2 * 0.6)
                        Trackpad(mac: mac)
                            .overlay(alignment: .topTrailing) {
                                Button("×") { mac.disconnect() }
                                    .font(mono(20)).frame(width: 44, height: 44)
                                    .accessibilityLabel("Disconnect")
                            }
                    }
                }
            }
            .frame(width: w, height: h)
            .ignoresSafeArea()
        }
        .defersSystemGestures(on: .bottom)       // trackpad strokes near the bottom edge are not "go home"
        .persistentSystemOverlays(.hidden)
    }
}

/// Where the Mac's picture sits inside the screen area: aspect-fit × zoom, panned so the pointer stays in view.
func viewport(container: CGSize, screen: CGSize, zoom: CGFloat, cursor: CGPoint) -> CGRect {
    guard screen.width > 0, screen.height > 0 else { return .zero }
    let scale = min(container.width / screen.width, container.height / screen.height) * zoom
    func origin(_ content: CGFloat, _ box: CGFloat, _ c: CGFloat) -> CGFloat {
        content <= box ? (box - content) / 2 : min(0, max(box - content, box / 2 - c * scale))
    }
    let size = CGSize(width: screen.width * scale, height: screen.height * scale)
    return CGRect(origin: CGPoint(x: origin(size.width, container.width, cursor.x),
                                  y: origin(size.height, container.height, cursor.y)), size: size)
}

/// The Mac's screen. Pinch to zoom (it follows the pointer), tap to click right there.
struct Screen: View {
    @ObservedObject var mac: Mac
    @AppStorage("zoom") private var zoom = 1.0
    @GestureState private var pinch = 1.0

    var body: some View {
        GeometryReader { g in
            let r = viewport(container: g.size, screen: mac.size, zoom: min(max(zoom * pinch, 1), 8), cursor: mac.cursor)
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
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { t in
                mac.move(to: CGPoint(x: (t.location.x - r.minX) / scale, y: (t.location.y - r.minY) / scale))
                mac.click(.left)
            })
            .gesture(MagnifyGesture()
                .updating($pinch) { v, s, _ in s = v.magnification }
                .onEnded { v in zoom = min(max(zoom * v.magnification, 1), 8) })
            .accessibilityIdentifier("screen")
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
        VStack(alignment: .leading, spacing: 16) {
            Text("MACBOOK NANO").font(mono(24))
            Text("Your Mac, in your pocket. On the Mac, turn on System Settings → General → Sharing → Screen Sharing, then sign in here with your Mac login. Host is its name or address, like mac-mini.local.")
                .font(mono(13)).lineSpacing(6)
            field("HOST", TextField("", text: $host).keyboardType(.URL).accessibilityIdentifier("host"))
            field("USER", TextField("", text: $user).accessibilityIdentifier("user"))
            field("PASSWORD", SecureField("", text: $password).accessibilityIdentifier("password"))
            Button {
                Keychain.set(password, account: "\(user)@\(host)")
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
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(idLabel).tracking(0.84)
                Text(idLabelExpansion)
                Text("V" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
            }
            .font(mono(12))
        }
        .foregroundStyle(.black)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .padding(24)
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .onAppear { password = Keychain.get(account: "\(user)@\(host)") ?? "" }
    }

    private func field(_ label: String, _ input: some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(mono(12)).tracking(0.5)
            input.font(mono(16)).padding(10).border(.black, width: 2)
        }
    }
}
