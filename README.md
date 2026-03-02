# Zebra Browser Print Emulator (macOS menu bar)

This project emulates Zebra Browser Print on macOS and captures label print requests. Instead of sending labels to a physical printer, it renders ZPL and opens a preview window.

## What it emulates

- `GET /available`
- `GET /default`
- `POST /write`
- `GET /read` and `POST /read`

The app serves both HTTP and HTTPS on `127.0.0.1`:

- HTTP defaults to `9100`
- HTTPS defaults to `9101` (self-signed localhost certificate)

You can change both ports from the menu bar popover.

Label rendering size is selectable from the menu bar and persisted across launches. Supported sizes:

- `10 x 5 cm` (default)
- `10 x 15 cm`
- `10 x 21 cm`

## Run

```bash
swift run ZebraBrowserPrintEmulator
```

## Open in Xcode (native app target)

Generate the Xcode project:

```bash
gem install --user-install xcodeproj
swift scripts/generate-app-icon.swift
./scripts/generate-xcodeproj.rb
```

Then open:

```bash
open ZebraBrowserPrintEmulator.xcodeproj
```

Inside Xcode you can configure Signing & Capabilities and other app target properties.

The icon is generated to `XcodeApp/Resources/AppIcon.icns`.

After launch, you will see a printer icon in the macOS menu bar. You can use Browser Print client code against either:

- `http://127.0.0.1:9100`
- `https://127.0.0.1:9101`

For local CLI checks, use `-k` because the certificate is self-signed:

```bash
curl http://127.0.0.1:9100/available
curl -k https://127.0.0.1:9101/available
```

## Behavior

- Requests to `/write` with a ZPL body containing `^XA` are treated as print jobs.
- The emulator sends ZPL to Labelary for rendering.
- The rendered image is shown in a popup window with the original ZPL payload.

## Notes

- Rendering uses the public Labelary API.
- If rendering fails, the request still returns success so client code can continue while you debug requests.
- On macOS 15+, TLS identity import is memory-only to avoid repeated Keychain private-key permission prompts.

## Package for distribution

Create a distributable `.app` and zip archive:

```bash
./scripts/package-macos.sh
```

Artifacts are written to `dist/`:

- `dist/Zebra Browser Print Emulator.app`
- `dist/Zebra Browser Print Emulator.zip`

Optional signing before sharing:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-macos.sh
```
