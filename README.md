# Macbook Nano

An iPhone Duo app that turns the phone into a mini MacBook for a Mac on the network.
Hold the unfolded Duo with the hinge horizontal: the Mac's screen is above the hinge,
a Mac keyboard and trackpad are below it.

It is a VNC client for macOS's built-in Screen Sharing. Nothing to install on the Mac.

## Use

1. On the Mac: System Settings → General → Sharing → Screen Sharing: on.
2. In the app: host (`mac-mini.local`, an IP, or `host:port`), your Mac user name and password.
   The password is kept in the iPhone's Keychain. The app reconnects every time it is opened.

| Where | Gesture | Does |
| --- | --- | --- |
| Trackpad | one finger | move the pointer |
| Trackpad | tap / two-finger tap | click / right-click |
| Trackpad | two fingers | scroll |
| Trackpad | hold, then move | drag |
| Screen | tap | click right there |
| Screen | pinch | zoom (follows the pointer) |
| Keyboard | tap SHIFT / CTRL / OPT / CMD | held for the next key (CMD, then C) |
| Keyboard | hold a modifier | a real held key (hold CMD, tap TAB, TAB) |
| Trackpad corner | × | disconnect |

Unfolded on its side (hinge vertical) the whole display is the Mac's screen.
Away from home, put both devices on Tailscale and use the Mac's Tailscale name as the host.

## Build

```sh
xcodegen
xcodebuild -project MacbookNano.xcodeproj -scheme MacbookNano -configuration Release -destination 'platform=iOS,name=chePhoneDuo' -allowProvisioningUpdates build
```

Always Release. Logging in to a Mac is a 4096-bit key exchange that takes about 3 s optimized and minutes
in a Debug build, by which time the Mac has hung up ("Security handshaking failed").

## Check

```sh
test/run.sh
```

Runs the unit tests, then drives the app in the Duo simulator against `test/fake_mac.py`
(a small VNC server that logs you in the way a real Mac does, with the same key sizes) and checks that
the login, keys, pointer moves and click it logged are the ones sent.

## Credits

VNC protocol: [RoyalVNCKit](https://github.com/royalapplications/royalvnc) (MIT, Royal Apps), used as a Swift package.
The connection delegate follows its [iOS demo](https://github.com/royalapplications/royalvnc-demo) (MIT).

CWT_STENGM0_2610
