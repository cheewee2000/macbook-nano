#!/usr/bin/env python3
"""A fake Mac: the smallest VNC (RFB 3.8) server that shows a picture and logs input.

    python3 test/fake_mac.py [port] [logfile] [password]

With a password it logs you in the way a real Mac does (protocol 003.889, Apple Remote Desktop login,
security type 30: Diffie-Hellman, then user name and password under AES-128-ECB) and logs
`auth <user> ok|fail`. Any user name, that one password. Without one there is no login. Draws a test card with a black square at the pointer, so a screenshot of the app proves
the picture and the pointer both make the round trip. Every key and pointer event is appended to the
log as `key <hex keysym> <down|up>` / `ptr <buttons> <x> <y>`, which the UI test's check reads.
"""
import hashlib, secrets, socket, struct, subprocess, sys, time

W, H = 640, 400
port = int(sys.argv[1]) if len(sys.argv) > 1 else 5999
log = open(sys.argv[2], "a", buffering=1) if len(sys.argv) > 2 else sys.stdout
password = sys.argv[3] if len(sys.argv) > 3 else None
# The numbers a real Mac used on 2026-11-23: generator 5 and a 4096-bit prime (512-byte keys). Any prime will do
# for a test; this one came from `openssl prime -generate -bits 4096`.
GENERATOR, KEY_BYTES = 5, 512
PRIME = int("FFC661C028EDCE537210B83DFF048EE18DBD2B06FDC1791A6B7EDF924D948B4F109371962AE9DDAE61B23F9A7994A76D"
            "0CAFA1F1B6403C0EBC905D891D59FB8DFBF7F4D551A0831FFABDE8DC9DAA6DEA2DE6A692DB0DE806916F078549B90910"
            "EFAF8CC5A801D4B22A4E1BD02C16237B90DEBB5B94EDAAACA4D30E2BBE734C10A4B84143B7587C82C10E671728C08A6C"
            "DB69D3486624B44DE6BE22FC0C1446FCB7FF0E775A58FE06A6AA191C9BF78D0CD5F0476439BB3C83F91E31F006D4E70B"
            "CE2346FEC37945D72CF0A19F44266A884EDD53EF58EB0DF31CDC2161A651558A18F20DC03C350B9B53801A9F45E4E002"
            "D0B30AD62465FDA294B7C03142BA32B52D3BBCD62763459761B847977FE57B05F4570EB0E509ED3D821DF16F38F75964"
            "4242C7D392B8110ABEC5AB4041E59E79A8C11A43A64D14E3DA865EB24B9994EC181F449CA408704FDCD48FAE0353714C"
            "533363CF5D6366D3607979D0C13170D2237D2091E0B2BCC2C87A787D5A50C0C9AD96A65DB6425D113E624AD25377F765"
            "8D9577B3A352EF74F3D83880E3DD420E5FA4D99C8367119E7801F19855DDC026FCB1A1F92D7E09E75EB78EE5BC5B2D6E"
            "A53B565778CE2B7781324B6C087FF92D31A3C42F42A99D0826D4E86C17B085653AC38CB908406005EEF3B7399F0DBA18"
            "B8199DB990F5A69A20DA97657FFF7EFB07B9FFDAF325AC2BD25249A0E34854A7", 16)


def recv(s, n):
    b = b""
    while len(b) < n:
        chunk = s.recv(n - len(b))
        if not chunk:
            raise ConnectionError
        b += chunk
    return b


cards = {}


def card(fmt):
    """The test card as rows of pixels in the client's format (built once per format: pure Python is slow)."""
    if fmt not in cards:
        bpp, big, rs, gs, bs = fmt
        def pixel(r, g, b):
            return ((r << rs) | (g << gs) | (b << bs)).to_bytes(bpp // 8, "big" if big else "little")
        white, black, grey = pixel(255, 255, 255), pixel(0, 0, 0), pixel(220, 220, 220)
        def at(x, y):
            if x < 4 or y < 4 or x >= W - 4 or y >= H - 4 or (y < 24 and x % 80 < 40):
                return black                                   # border + a "menu bar" of ticks
            return grey if (x // 40 + y // 40) % 2 else white
        cards[fmt] = ([b"".join(at(x, y) for x in range(W)) for y in range(H)], black)
    return cards[fmt]


def frame(fmt, px, py):
    rows, black = card(fmt)
    rows, n = list(rows), len(black)
    x0, x1 = max(px - 6, 0), min(px + 6, W)
    for y in range(max(py - 6, 0), min(py + 6, H)):            # a black square at the pointer
        rows[y] = rows[y][:x0 * n] + black * (x1 - x0) + rows[y][x1 * n:]
    return b"".join(rows)


def apple_login(s):
    """Security type 30. True if the password that arrives is the right one."""
    n = KEY_BYTES
    private = secrets.randbelow(PRIME - 2) + 1
    s.sendall(struct.pack(">HH", GENERATOR, n) + PRIME.to_bytes(n, "big") + pow(GENERATOR, private, PRIME).to_bytes(n, "big"))
    cipher, public = recv(s, 128), int.from_bytes(recv(s, n), "big")
    secret = pow(public, private, PRIME).to_bytes(n, "big")
    key = hashlib.md5(secret).hexdigest()
    plain = subprocess.run(["openssl", "enc", "-d", "-aes-128-ecb", "-nopad", "-K", key],
                           input=cipher, capture_output=True, check=True).stdout
    user, got = (part.split(b"\0")[0].decode("utf8", "replace") for part in (plain[:64], plain[64:]))
    ok = got == password
    log.write(f"auth {user!r} {'ok' if ok else 'fail'}\n")
    return ok


def serve(s):
    if password is None:
        s.sendall(b"RFB 003.008\n"); recv(s, 12)
        s.sendall(b"\x01\x01"); recv(s, 1)                     # one security type: None
        s.sendall(struct.pack(">I", 0))                        # SecurityResult ok
    else:
        s.sendall(b"RFB 003.889\n"); recv(s, 12)
        s.sendall(b"\x01\x1e"); recv(s, 1)                     # one security type: 30, Apple Remote Desktop
        if not apple_login(s):
            why = b"Authentication failed."
            s.sendall(struct.pack(">II", 1, len(why)) + why)
            return
        s.sendall(struct.pack(">I", 0))
    recv(s, 1)                                                 # ClientInit
    name = b"Fake Mac"
    s.sendall(struct.pack(">HHBBBBHHHBBB3xI", W, H, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0, len(name)) + name)
    fmt, px, py = (32, 0, 16, 8, 0), W // 2, H // 2
    while True:
        t = recv(s, 1)[0]
        if t == 0:                                             # SetPixelFormat
            bpp, _, big, _, _, _, _, rs, gs, bs = struct.unpack(">3xBBBBHHHBBB3x", recv(s, 19))
            fmt = (bpp, big, rs, gs, bs)
        elif t == 2:                                           # SetEncodings (ignored: always raw)
            recv(s, 4 * struct.unpack(">xH", recv(s, 3))[0])
        elif t == 3:                                           # FramebufferUpdateRequest
            if recv(s, 9)[0]:
                time.sleep(0.05)                               # incremental: 20 fps is plenty
            s.sendall(struct.pack(">BxHHHHHi", 0, 1, 0, 0, W, H, 0) + frame(fmt, px, py))
        elif t == 4:                                           # KeyEvent
            down, sym = struct.unpack(">B2xI", recv(s, 7))
            log.write(f"key {sym:x} {'down' if down else 'up'}\n")
        elif t == 5:                                           # PointerEvent
            buttons, px, py = struct.unpack(">BHH", recv(s, 5))
            log.write(f"ptr {buttons} {px} {py}\n")
        elif t == 6:                                           # ClientCutText
            recv(s, struct.unpack(">3xI", recv(s, 7))[0])
        else:
            raise ConnectionError(f"unknown message {t}")


srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port))
srv.listen(1)
while True:
    conn, _ = srv.accept()
    try:
        serve(conn)
    except (ConnectionError, struct.error, OSError):
        pass
    conn.close()
