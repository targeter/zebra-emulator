# Zebra Browser Print Emulator (macOS menu bar)

This project emulates Zebra Browser Print on macOS and captures label print requests. Instead of sending labels to a physical printer, it renders ZPL and opens a preview window.

## What it emulates

- `GET /available`
- `GET /default`
- `POST /write`
- `GET /read` and `POST /read`

The app serves HTTPS on `127.0.0.1` using a self-signed localhost certificate. It defaults to port `9100`, and you can change the port from the menu bar popover (Port field + Apply).

Label rendering size is selectable from the menu bar and persisted across launches. Supported sizes:

- `10 x 5 cm` (default)
- `10 x 15 cm`
- `10 x 21 cm`

## Run

```bash
swift run ZebraBrowserPrintEmulator
```

After launch, you will see a printer icon in the macOS menu bar. Use your Browser Print client code against `https://127.0.0.1:9100`.

For local CLI checks, use `-k` because the certificate is self-signed:

```bash
curl -k https://127.0.0.1:9100/available
```

## Behavior

- Requests to `/write` with a ZPL body containing `^XA` are treated as print jobs.
- The emulator sends ZPL to Labelary for rendering.
- The rendered image is shown in a popup window with the original ZPL payload.

## Notes

- Rendering uses the public Labelary API.
- If rendering fails, the request still returns success so client code can continue while you debug requests.
- On macOS 15+, TLS identity import is memory-only to avoid repeated Keychain private-key permission prompts.
