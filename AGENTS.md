# PROJECT KNOWLEDGE BASE

Generated: 2026-03-01T22:15:33Z
Commit: 013a23f
Branch: main

## OVERVIEW

macOS menu bar Swift executable emulating Zebra Browser Print over local HTTPS. It captures ZPL print jobs and opens rendered previews instead of sending to hardware.

## STRUCTURE

```text
zebra-emulator/
├── Sources/ZebraBrowserPrintEmulator/  # runtime app + HTTPS server + rendering + preview windows
├── scripts/                             # distribution packaging entrypoint
├── Packaging/                           # app bundle metadata
├── README.md
├── Package.swift
└── AGENTS.md
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| App entry + lifecycle | `Sources/ZebraBrowserPrintEmulator/AppMain.swift` | `@main`, `AppDelegate`, menu bar scene |
| Stateful config + restarts | `Sources/ZebraBrowserPrintEmulator/AppState.swift` | persisted port/label size, server restart wiring |
| HTTPS server + routes | `Sources/ZebraBrowserPrintEmulator/ServerController.swift` | `/available`, `/default`, `/write`, `/read` |
| HTTP parsing primitives | `Sources/ZebraBrowserPrintEmulator/HTTPTypes.swift` | request parse, response serialization |
| TLS identity handling | `Sources/ZebraBrowserPrintEmulator/TLSIdentityManager.swift` | self-signed cert generation/loading |
| ZPL render API | `Sources/ZebraBrowserPrintEmulator/ZPLRenderer.swift` | Labelary call with selected label dimensions |
| Preview window behavior | `Sources/ZebraBrowserPrintEmulator/PreviewWindowManager.swift` | monitor placement, no focus steal, payload collapse state |
| Packaging flow | `scripts/package-macos.sh`, `Packaging/Info.plist` | `.app` + `.zip`, optional signing |

## CONVENTIONS

- Browser Print compatibility takes precedence over internal API preferences.
- Local endpoint is HTTPS on `127.0.0.1:<port>` with self-signed cert.
- Persisted settings keys are stable: `emulator.port`, `emulator.https-port`, `emulator.printers`, `emulator.label-size`, `preview.payload.expanded`.
- Label sizes exposed in UI map to Labelary dimensions: `10x5`, `10x15`, `10x21`.

## ANTI-PATTERNS (THIS PROJECT)

- Do not change endpoint contracts (`/available`, `/default`, `/write`, `/read`) unless explicitly requested.
- Do not make preview windows steal focus.
- Do not break top-right active-monitor placement behavior for preview popups.

## COMMANDS

```bash
swift run ZebraBrowserPrintEmulator
swift build
./scripts/package-macos.sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-macos.sh
```

## NOTES

- No `Tests/` target currently; verification is build + runtime smoke checks.
- Packaging artifacts are emitted in `dist/` and ignored by git.
- See `Sources/ZebraBrowserPrintEmulator/AGENTS.md` for module-level implementation map.
