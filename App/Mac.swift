import SwiftUI
import Security
import RoyalVNCKit

/// One Screen Sharing session with the Mac. A thin wrapper over RoyalVNCKit
/// (MIT, github.com/royalapplications/royalvnc); the delegate handling follows its iOS demo.
final class Mac: NSObject, ObservableObject, VNCConnectionDelegate {
    enum Status: Equatable { case idle, connecting, connected, failed(String) }

    @Published var status = Status.idle
    @Published var size = CGSize.zero            // framebuffer, px
    @Published var cursor = CGPoint.zero         // pointer, framebuffer px
    @Published var cursorImage: CGImage?         // only when the Mac sends its cursor separately from the picture
    @Published var cursorHotspot = CGPoint.zero
    /// The Mac's picture. Set straight from the delegate so a frame never goes through SwiftUI.
    let layer = CALayer()

    private var connection: VNCConnection?
    private var user = "", password = ""
    private var keysDown = Set<UInt32>()

    func connect(host: String, user: String, password: String) {
        disconnect()
        // ponytail: "host" or "host:port" only; a bare IPv6 address needs its own parsing if that ever comes up
        let parts = host.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let name = parts.first else { return }
        self.user = user; self.password = password
        let c = VNCConnection(settings: .init(
            isDebugLoggingEnabled: false, hostname: String(name),
            port: parts.count > 1 ? UInt16(parts[1]) ?? 5900 : 5900,
            isShared: true, isScalingEnabled: true, useDisplayLink: false,
            inputMode: .forwardKeyboardShortcutsIfNotInUseLocally,   // .none means view-only: nothing is sent
            isClipboardRedirectionEnabled: true, colorDepth: .depth24Bit, frameEncodings: .default))
        c.delegate = self
        connection = c
        status = .connecting
        c.connect()
    }

    func disconnect() {
        connection?.delegate = nil
        connection?.disconnect()
        connection = nil
        keysDown = []
        status = .idle
    }

    // MARK: Input

    func move(by d: CGSize) { move(to: CGPoint(x: cursor.x + d.width, y: cursor.y + d.height)) }

    func move(to p: CGPoint) {
        cursor = CGPoint(x: min(max(p.x, 0), max(size.width - 1, 0)), y: min(max(p.y, 0), max(size.height - 1, 0)))
        connection?.mouseMove(x: UInt16(cursor.x), y: UInt16(cursor.y))
    }

    func button(_ b: VNCMouseButton, down: Bool) {
        if down { connection?.mouseButtonDown(b, x: UInt16(cursor.x), y: UInt16(cursor.y)) }
        else { connection?.mouseButtonUp(b, x: UInt16(cursor.x), y: UInt16(cursor.y)) }
    }

    func click(_ b: VNCMouseButton) { button(b, down: true); button(b, down: false) }

    func scroll(_ wheel: VNCMouseWheel) {
        connection?.mouseWheel(wheel, x: UInt16(cursor.x), y: UInt16(cursor.y), steps: 1)
    }

    /// `sym` is an X11 keysym, which is what VNC speaks. RoyalVNCKit remaps cmd / opt for Apple's server.
    func key(_ sym: UInt32, down: Bool) {
        if down { keysDown.insert(sym); connection?.keyDown(VNCKeyCode(sym)) }
        else { keysDown.remove(sym); connection?.keyUp(VNCKeyCode(sym)) }
    }

    /// Leaving the app mid-press must not leave cmd (or anything) held on the Mac.
    func releaseKeys() { for k in keysDown { key(k, down: false) } }

    // MARK: VNCConnectionDelegate (called off the main thread)

    func connection(_ c: VNCConnection, stateDidChange state: VNCConnection.ConnectionState) {
        DispatchQueue.main.async {
            guard c === self.connection else { return }
            switch state.status {
            case .connecting: self.status = .connecting
            case .connected: self.status = .connected
            case .disconnecting: break
            case .disconnected:
                self.connection = nil
                self.keysDown = []
                self.status = .failed(state.error?.localizedDescription ?? "The Mac closed the connection.")
            @unknown default: break
            }
        }
    }

    func connection(_ c: VNCConnection, credentialFor type: VNCAuthenticationType,
                    completion: @escaping (VNCCredential?) -> Void) {
        completion(type.requiresUsername
                   ? VNCUsernamePasswordCredential(username: user, password: password)
                   : VNCPasswordCredential(password: password))
    }

    func connection(_ c: VNCConnection, didCreateFramebuffer fb: VNCFramebuffer) { resized(fb, center: true) }
    func connection(_ c: VNCConnection, didResizeFramebuffer fb: VNCFramebuffer) { resized(fb, center: false) }

    private func resized(_ fb: VNCFramebuffer, center: Bool) {
        let s = fb.cgSize
        DispatchQueue.main.async {
            self.size = s
            self.cursor = center ? CGPoint(x: s.width / 2, y: s.height / 2)
                                 : CGPoint(x: min(self.cursor.x, s.width - 1), y: min(self.cursor.y, s.height - 1))
        }
    }

    func connection(_ c: VNCConnection, didUpdateFramebuffer fb: VNCFramebuffer,
                    x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
        // ponytail: a whole-frame image per update, as the RoyalVNC demo does. Fine on a LAN at 1080p;
        // if a 4K Mac feels slow, lower its resolution or switch this to RoyalVNCKit's IOSurface path.
        let image = fb.cgImage
        DispatchQueue.main.async {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.layer.contents = image
            CATransaction.commit()
        }
    }

    func connection(_ c: VNCConnection, didUpdateCursor cursor: VNCCursor) {
        let image = cursor.isEmpty ? nil : cursor.cgImage, hotspot = cursor.cgHotspot
        DispatchQueue.main.async { self.cursorImage = image; self.cursorHotspot = hotspot }
    }
}

/// The Mac login password lives in the Keychain, never in UserDefaults.
enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.cwandt.macbooknano",
         kSecAttrAccount as String: account]
    }

    static func set(_ password: String, account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = Data(password.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
    }
}
