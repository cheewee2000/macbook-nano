import SwiftUI

// X11 keysyms (what VNC sends). Printable ASCII is its own keysym.
enum Sym {
    static let shift: UInt32 = 0xffe1, control: UInt32 = 0xffe3, option: UInt32 = 0xffe9, command: UInt32 = 0xffeb
    static let escape: UInt32 = 0xff1b, tab: UInt32 = 0xff09, delete: UInt32 = 0xff08, `return`: UInt32 = 0xff0d
    static let left: UInt32 = 0xff51, up: UInt32 = 0xff52, right: UInt32 = 0xff53, down: UInt32 = 0xff54
}

struct KeyDef: Identifiable {
    let id: String
    let label: String
    var shifted: String?
    let sym: UInt32
    var shiftedSym: UInt32?
    var width: CGFloat = 1          // in letter-key widths
    var isModifier = false
}

private func chars(_ plain: String, _ shifted: String) -> [KeyDef] {
    zip(plain, shifted).map { p, s in
        KeyDef(id: String(p), label: p.isLetter ? String(s) : String(p), shifted: String(s),
               sym: UInt32(p.asciiValue!), shiftedSym: UInt32(s.asciiValue!))
    }
}

private func mod(_ id: String, _ label: String, _ sym: UInt32, _ width: CGFloat) -> KeyDef {
    KeyDef(id: id, label: label, sym: sym, width: width, isModifier: true)
}

/// MacBook rows and widths (every row is 14.5 letter keys wide). esc sits where caps lock was, there is no function row.
let keyRows: [[KeyDef]] = [
    chars("`1234567890-=", "~!@#$%^&*()_+") + [KeyDef(id: "delete", label: "DEL", sym: Sym.delete, width: 1.5)],
    [KeyDef(id: "tab", label: "TAB", sym: Sym.tab, width: 1.5)] + chars("qwertyuiop[]\\", "QWERTYUIOP{}|"),
    [KeyDef(id: "esc", label: "ESC", sym: Sym.escape, width: 1.75)] + chars("asdfghjkl;'", "ASDFGHJKL:\"")
        + [KeyDef(id: "return", label: "RETURN", sym: Sym.return, width: 1.75)],
    [mod("shift", "SHIFT", Sym.shift, 2.25)] + chars("zxcvbnm,./", "ZXCVBNM<>?") + [mod("shift-r", "SHIFT", Sym.shift, 2.25)],
    [mod("ctrl", "CTRL", Sym.control, 1.25), mod("opt", "OPT", Sym.option, 1.25), mod("cmd", "CMD", Sym.command, 1.5),
     KeyDef(id: "space", label: "", sym: 0x20, width: 5.5),
     KeyDef(id: "left", label: "←", sym: Sym.left, width: 1.25), KeyDef(id: "down", label: "↓", sym: Sym.down, width: 1.25),
     KeyDef(id: "up", label: "↑", sym: Sym.up, width: 1.25), KeyDef(id: "right", label: "→", sym: Sym.right, width: 1.25)],
]

/// Modifier keys on glass. Tap one and it stays down for the next key (cmd, then C). Hold it while typing
/// and it behaves like a real key (hold cmd, tap tab, tab, tab). Tap a latched one again to let go.
/// Each call returns the key events to send to the Mac.
struct ModifierLatch {
    typealias Event = (sym: UInt32, down: Bool)
    private(set) var down = Set<UInt32>()        // held on the Mac
    private var touching = Set<UInt32>()         // finger on it now
    private var releaseOnLift = Set<UInt32>()    // chorded, or touched again while latched

    mutating func modifierDown(_ m: UInt32) -> [Event] {
        touching.insert(m)
        if down.contains(m) { releaseOnLift.insert(m); return [] }
        down.insert(m)
        return [(m, true)]
    }

    mutating func modifierUp(_ m: UInt32) -> [Event] {
        touching.remove(m)
        guard releaseOnLift.remove(m) != nil else { return [] }   // a plain tap: stays latched
        down.remove(m)
        return [(m, false)]
    }

    mutating func keyDown() { releaseOnLift.formUnion(touching) }

    mutating func keyUp() -> [Event] {
        let done = down.subtracting(touching)
        down.subtract(done)
        releaseOnLift.subtract(done)
        return done.map { ($0, false) }
    }
}

struct Keyboard: View {
    let mac: Mac
    @State private var mods = ModifierLatch()
    @State private var held: [String: (sym: UInt32, repeating: Task<Void, Never>?)] = [:]
    @Environment(\.scenePhase) private var phase

    var body: some View {
        GeometryReader { g in
            let unit = g.size.width / 14.5, rowHeight = g.size.height / CGFloat(keyRows.count)
            let shift = mods.down.contains(Sym.shift)
            VStack(spacing: 0) {
                ForEach(keyRows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(keyRows[r]) { k in
                            KeyCap(id: k.id, label: shift ? k.shifted ?? k.label : k.label,
                                   on: k.isModifier && mods.down.contains(k.sym),
                                   down: { down(k) }, up: { up(k) })
                                .frame(width: unit * k.width, height: rowHeight)
                        }
                    }
                }
            }
        }
        .onChange(of: phase) { _, p in
            guard p != .active else { return }
            for h in held.values { h.repeating?.cancel() }
            held = [:]; mods = ModifierLatch(); mac.releaseKeys()
        }
    }

    private func send(_ events: [ModifierLatch.Event]) { for e in events { mac.key(e.sym, down: e.down) } }

    private func down(_ k: KeyDef) {
        if k.isModifier { return send(mods.modifierDown(k.sym)) }
        mods.keyDown()
        let sym = mods.down.contains(Sym.shift) ? k.shiftedSym ?? k.sym : k.sym
        mac.key(sym, down: true)
        // Synthetic keys don't auto-repeat on the Mac, so repeat here. Never with cmd / ctrl / opt down.
        let repeats = mods.down.isSubset(of: [Sym.shift])
        held[k.id] = (sym, !repeats ? nil : Task {
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                mac.key(sym, down: true)
                try? await Task.sleep(for: .milliseconds(50))
            }
        })
    }

    private func up(_ k: KeyDef) {
        if k.isModifier { return send(mods.modifierUp(k.sym)) }
        if let h = held.removeValue(forKey: k.id) { h.repeating?.cancel(); mac.key(h.sym, down: false) }
        send(mods.keyUp())
    }
}

/// One button style: the design system's, inverted while pressed or latched.
struct KeyCap: View {
    let id: String, label: String, on: Bool
    let down: () -> Void, up: () -> Void
    @State private var pressed = false

    var body: some View {
        Text(label).font(.custom("SpaceMono-Regular", size: 14)).lineLimit(1).minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(pressed || on ? .white : .black)
            .background(pressed || on ? .black : .white)
            .border(.black, width: 0.5)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true; down() } }
                .onEnded { _ in pressed = false; up() })
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, now in now }
            .accessibilityElement()
            .accessibilityLabel(label.isEmpty ? "space" : label)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("key-" + id)
    }
}
