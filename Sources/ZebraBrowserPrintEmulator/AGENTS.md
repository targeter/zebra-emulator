# MODULE KNOWLEDGE BASE

Generated: 2026-03-01T22:15:33Z
Parent: `../../AGENTS.md`

## OVERVIEW

Runtime module for app lifecycle, local HTTPS Browser Print emulation, ZPL rendering, and preview window behavior.

## WHERE TO LOOK

| Task | File | Notes |
|------|------|-------|
| App startup | `AppMain.swift` | `@main` app entry, `AppDelegate`, menu bar scene |
| Shared state + preferences | `AppState.swift` | persisted keys, server restart on port/size changes |
| Endpoint routing | `ServerController.swift` | Browser Print route contract + event emission |
| Request/response wire format | `HTTPTypes.swift` | HTTP parse + response serialization |
| TLS cert lifecycle | `TLSIdentityManager.swift` | self-signed cert files + identity import |
| ZPL rendering | `ZPLRenderer.swift` | Labelary URL + selected dimensions |
| Preview UI behavior | `PreviewWindowManager.swift` | active-monitor placement, focus behavior, payload collapse state |

## CONVENTIONS

- Keep route compatibility stable for `/available`, `/default`, `/write`, `/read`.
- Preserve persisted keys: `emulator.port`, `emulator.label-size`, `preview.payload.expanded`.
- Label size mapping is canonical in `AppState`: `10x5`, `10x15`, `10x21`.
- TLS identity is local/self-signed; cert material stored in Application Support.

## ANTI-PATTERNS

- Do not alter `/available` response shape away from Browser Print-compatible payload.
- Do not activate app or make preview windows steal focus.
- Do not break top-right active-monitor placement logic.

## QUICK VERIFY

```bash
swift build
swift run ZebraBrowserPrintEmulator
curl -k https://127.0.0.1:9100/available
```
