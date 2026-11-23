import SwiftUI

// X11 keysyms (what VNC sends). Printable ASCII is its own keysym.
enum Sym {
    static let shift: UInt32 = 0xffe1, control: UInt32 = 0xffe3, option: UInt32 = 0xffe9, command: UInt32 = 0xffeb
    static let escape: UInt32 = 0xff1b, tab: UInt32 = 0xff09, delete: UInt32 = 0xff08, `return`: UInt32 = 0xff0d
    static let left: UInt32 = 0xff51, up: UInt32 = 0xff52, right: UInt32 = 0xff53, down: UInt32 = 0xff54
    static let home: UInt32 = 0xff50, end: UInt32 = 0xff57, pageUp: UInt32 = 0xff55, pageDown: UInt32 = 0xff56
    static let forwardDelete: UInt32 = 0xffff, f1: UInt32 = 0xffbe
    /// fn never goes to the Mac (VNC has no such key): it is a modifier for this keyboard only.
    static let fn: UInt32 = 0
    /// Not keys on the wire either: handled here.
    static let capsLock: UInt32 = 1, power: UInt32 = 2
}

/// What is printed on the keycap, laid out the way Apple prints it.
enum Legend {
    case letter(String)                       // Q
    case pair(String, String)                 // ! over 1
    case word(String, Alignment)              // tab, bottom left
    case modifier(String, String, Alignment)  // ⌘ in a top corner, "command" along the bottom
    case function(String, String)             // SF Symbol, "F1"
    case glyph(String)                        // arrows
    case blank
}

struct KeyDef: Identifiable {
    let id: String
    let legend: Legend
    let sym: UInt32
    var shiftedSym: UInt32?
    var fnSym: UInt32?              // with fn held: arrows page and jump, delete deletes forward
    var width: CGFloat = 1          // in letter-key widths
    var isModifier = false
}

private func letters(_ s: String) -> [KeyDef] {
    s.map { c in
        KeyDef(id: String(c), legend: .letter(String(c).uppercased()), sym: UInt32(c.asciiValue!),
               shiftedSym: UInt32(Character(String(c).uppercased()).asciiValue!))
    }
}

private func pairs(_ plain: String, _ shifted: String) -> [KeyDef] {
    zip(plain, shifted).map { p, s in
        KeyDef(id: String(p), legend: .pair(String(s), String(p)), sym: UInt32(p.asciiValue!), shiftedSym: UInt32(s.asciiValue!))
    }
}

private func mod(_ id: String, _ legend: Legend, _ sym: UInt32, _ width: CGFloat) -> KeyDef {
    KeyDef(id: id, legend: legend, sym: sym, width: width, isModifier: true)
}

private let functionIcons = ["sun.min", "sun.max", "rectangle.3.group", "magnifyingglass", "mic", "moon",
                             "backward.fill", "playpause.fill", "forward.fill", "speaker.fill", "speaker.wave.1.fill", "speaker.wave.3.fill"]

/// The US MacBook Pro keyboard, row by row. Every row is 14.5 letter keys wide; the last one leaves 3 for the arrows.
/// ponytail: the function row sends plain F1…F12. The pictures are Apple's, but brightness / media / volume are not
/// keys VNC can press; map them to something on the Mac if they are missed.
let keyRows: [[KeyDef]] = [
    [KeyDef(id: "esc", legend: .word("esc", .center), sym: Sym.escape, width: 1.5)]
        + (0..<12).map { KeyDef(id: "f\($0 + 1)", legend: .function(functionIcons[$0], "F\($0 + 1)"), sym: Sym.f1 + UInt32($0)) }
        + [KeyDef(id: "power", legend: .blank, sym: Sym.power)],
    pairs("`1234567890-=", "~!@#$%^&*()_+")
        + [KeyDef(id: "delete", legend: .word("delete", .bottomTrailing), sym: Sym.delete, fnSym: Sym.forwardDelete, width: 1.5)],
    [KeyDef(id: "tab", legend: .word("tab", .bottomLeading), sym: Sym.tab, width: 1.5)]
        + letters("qwertyuiop") + pairs("[]\\", "{}|"),
    [KeyDef(id: "caps", legend: .word("caps lock", .bottomLeading), sym: Sym.capsLock, width: 1.75)]
        + letters("asdfghjkl") + pairs(";'", ":\"")
        + [KeyDef(id: "return", legend: .word("return", .bottomTrailing), sym: Sym.return, width: 1.75)],
    [mod("shift", .word("shift", .bottomLeading), Sym.shift, 2.25)]
        + letters("zxcvbnm") + pairs(",./", "<>?")
        + [mod("shift-r", .word("shift", .bottomTrailing), Sym.shift, 2.25)],
    [mod("fn", .modifier("fn", "globe", .topTrailing), Sym.fn, 1),
     mod("ctrl", .modifier("⌃", "control", .topTrailing), Sym.control, 1),
     mod("opt", .modifier("⌥", "option", .topTrailing), Sym.option, 1),
     mod("cmd", .modifier("⌘", "command", .topTrailing), Sym.command, 1.25),
     KeyDef(id: "space", legend: .blank, sym: 0x20, width: 5),
     mod("cmd-r", .modifier("⌘", "command", .topLeading), Sym.command, 1.25),
     mod("opt-r", .modifier("⌥", "option", .topLeading), Sym.option, 1)],
]

/// The inverted T, each one key wide and half a key tall.
let arrowKeys = (
    left: KeyDef(id: "left", legend: .glyph("◀"), sym: Sym.left, fnSym: Sym.home),
    up: KeyDef(id: "up", legend: .glyph("▲"), sym: Sym.up, fnSym: Sym.pageUp),
    down: KeyDef(id: "down", legend: .glyph("▼"), sym: Sym.down, fnSym: Sym.pageDown),
    right: KeyDef(id: "right", legend: .glyph("▶"), sym: Sym.right, fnSym: Sym.end)
)

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

/// The key a press sends, given what is latched: fn first (arrows, delete), then shift / caps lock.
func keysym(for k: KeyDef, modifiers: Set<UInt32>, capsLock: Bool) -> UInt32 {
    if modifiers.contains(Sym.fn), let s = k.fnSym { return s }
    if case .letter = k.legend { return modifiers.contains(Sym.shift) != capsLock ? k.shiftedSym ?? k.sym : k.sym }
    return modifiers.contains(Sym.shift) ? k.shiftedSym ?? k.sym : k.sym
}

/// `unit` is one letter key's pitch (key plus the gap around it). The keyboard is 14.5 × 6 of them.
struct Keyboard: View {
    let mac: Mac
    let unit: CGFloat
    @State private var mods = ModifierLatch()
    @State private var capsLock = false
    @State private var held: [String: (sym: UInt32, repeating: Task<Void, Never>?)] = [:]
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(spacing: 0) {
            ForEach(keyRows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(keyRows[r]) { k in cap(k).frame(width: unit * k.width, height: unit) }
                    if r == keyRows.count - 1 {
                        // ◀ and ▶ are half-height keys, but the empty half above each still counts as the key
                        cap(arrowKeys.left, half: .bottom).frame(width: unit, height: unit)
                        VStack(spacing: 0) {
                            cap(arrowKeys.up, half: .top).frame(width: unit, height: unit / 2)
                            cap(arrowKeys.down, half: .bottom).frame(width: unit, height: unit / 2)
                        }
                        cap(arrowKeys.right, half: .bottom).frame(width: unit, height: unit)
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

    private func cap(_ k: KeyDef, half: VerticalEdge? = nil) -> KeyCap {
        KeyCap(key: k, unit: unit, half: half,
               lit: k.isModifier && mods.down.contains(k.sym) || k.sym == Sym.capsLock && capsLock,
               down: { down(k) }, up: { up(k) })
    }

    private func send(_ events: [ModifierLatch.Event]) {
        for e in events where e.sym != Sym.fn { mac.key(e.sym, down: e.down) }
    }

    private func down(_ k: KeyDef) {
        if k.isModifier { return send(mods.modifierDown(k.sym)) }
        if k.sym == Sym.capsLock { capsLock.toggle(); return }
        if k.sym == Sym.power {
            // the power button: hold it to hang up, like holding a real one. A brush past it on the way to delete does nothing.
            held[k.id] = (k.sym, Task {
                try? await Task.sleep(for: .milliseconds(700))
                if !Task.isCancelled { mac.disconnect() }
            })
            return
        }
        mods.keyDown()
        let sym = keysym(for: k, modifiers: mods.down, capsLock: capsLock)
        mac.key(sym, down: true)
        // Synthetic keys don't auto-repeat on the Mac, so repeat here. Never with cmd / ctrl / opt down.
        let repeats = mods.down.isSubset(of: [Sym.shift, Sym.fn])
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
        guard let h = held.removeValue(forKey: k.id) else { return }
        h.repeating?.cancel()
        if k.sym == Sym.power { return }
        mac.key(h.sym, down: false)
        send(mods.keyUp())
    }
}

/// A MacBook keycap: black, rounded, white legend. The whole cell is the touch target, gap included.
struct KeyCap: View {
    let key: KeyDef
    let unit: CGFloat
    var half: VerticalEdge?
    let lit: Bool
    let down: () -> Void, up: () -> Void
    @State private var pressed = false

    private var gap: CGFloat { unit * 0.06 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.11, style: .continuous)
        shape.fill(Color(white: pressed ? 0.38 : lit ? 0.28 : 0.11))
            .overlay(shape.strokeBorder(Color(white: 0.2), lineWidth: 0.5))
            .overlay { legend.foregroundStyle(.white).padding(unit * 0.09) }
            .padding(gap)
            .frame(maxHeight: .infinity, alignment: half == nil ? .center : .bottom)
            .padding(.top, half == .bottom && key.id != "down" ? unit / 2 : 0)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true; down() } }
                .onEnded { _ in pressed = false; up() })
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, now in now }
            .accessibilityElement()
            .accessibilityLabel(key.id == "power" ? "Disconnect (hold)" : key.id)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("key-" + key.id)
    }

    private func text(_ s: String, _ size: CGFloat) -> some View {
        Text(s).font(.system(size: unit * size)).lineLimit(1).minimumScaleFactor(0.5)
    }

    @ViewBuilder private var legend: some View {
        switch key.legend {
        case .letter(let s):
            text(s, 0.34)
        case .pair(let top, let bottom):
            VStack(spacing: unit * 0.02) { text(top, 0.26); text(bottom, 0.26) }
        case .word(let s, let at):
            text(s, 0.2).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: at)
                .overlay(alignment: .topLeading) {
                    // caps lock's light
                    if key.sym == Sym.capsLock {
                        Circle().fill(lit ? Color.green : Color(white: 0.22)).frame(width: unit * 0.09, height: unit * 0.09)
                    }
                }
        case .modifier(let symbol, let word, let corner):
            let trailing = corner == .topTrailing
            ZStack {
                text(symbol, symbol == "fn" ? 0.2 : 0.24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner)
                Group {
                    if word == "globe" { Image(systemName: "globe").font(.system(size: unit * 0.22)) } else { text(word, 0.17) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: word == "globe" ? .bottomLeading : trailing ? .bottomTrailing : .bottomLeading)
            }
        case .function(let icon, let name):
            VStack(spacing: unit * 0.04) {
                Image(systemName: icon).font(.system(size: unit * 0.2))
                text(name, 0.14)
            }
        case .glyph(let s):
            text(s, 0.16)
        case .blank:
            // Touch ID: a ring where the sensor is
            if key.sym == Sym.power { Circle().strokeBorder(Color(white: 0.25), lineWidth: 1).padding(unit * 0.08) }
        }
    }
}
