#!/usr/bin/env python3
"""A fake Mac: the smallest VNC (RFB 3.8) server that shows a picture and logs input.

    python3 test/fake_mac.py [port] [logfile]

No password. Draws a test card with a black square at the pointer, so a screenshot of the app proves
the picture and the pointer both make the round trip. Every key and pointer event is appended to the
log as `key <hex keysym> <down|up>` / `ptr <buttons> <x> <y>`, which the UI test's check reads.
"""
import socket, struct, sys, time

W, H = 640, 400
port = int(sys.argv[1]) if len(sys.argv) > 1 else 5999
log = open(sys.argv[2], "a", buffering=1) if len(sys.argv) > 2 else sys.stdout


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


def serve(s):
    s.sendall(b"RFB 003.008\n"); recv(s, 12)
    s.sendall(b"\x01\x01"); recv(s, 1)                         # one security type: None
    s.sendall(struct.pack(">I", 0)); recv(s, 1)                # SecurityResult ok, ClientInit
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
