# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Swift Package (SPM) library exposing a typed `async/await` client for the ODXProxy gateway, which proxies JSON-RPC calls to Odoo. Targets iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+, macCatalyst 15+. `swift-tools-version: 6.2.0`.

The wire protocol is documented in `SYSTEM_ARCHITECTURE.md` at the repo root. Treat that as the source of truth for endpoint shapes, error codes, and the JSON-RPC envelope — `CLAUDE.md` only highlights how the Swift code maps onto it.

## Commands

```bash
swift build
swift test
swift test --filter ODXProxyClientIntegrationTests/searchRead_returnsRecords
```

Tests use `swift-testing` (not XCTest). Swift 6.2 bundles `Testing`, so `Package.swift` declares no external `swift-testing` dependency — just `import Testing` directly. If a stale `.build` or `Package.resolved` is around from earlier setups, a clean rebuild may be needed (`rm -rf .build .swiftpm/xcode Package.resolved && swift package reset`).

## Integration tests + credentials

The integration suite is gated behind `TestCredentials.swift` (gitignored). All 9 tests **skip** when credentials are absent — they do not fail.

- Template: `Tests/ODXProxyClientSwiftTests/TestCredentials.swift.example` (committed)
- Local: `Tests/ODXProxyClientSwiftTests/TestCredentials.swift` (gitignored — fill in here)

For a fresh clone:
```bash
cp Tests/ODXProxyClientSwiftTests/TestCredentials.swift.example \
   Tests/ODXProxyClientSwiftTests/TestCredentials.swift
# edit values
swift test
```

Skip mechanism: `@Suite(.disabled(if: !TestCredentials.isConfigured, ...))`. Do NOT switch to `try #require(...)` inside test bodies — that records a failure, not a skip.

All integration tests are READ-ONLY against `res.partner`. If you add mutating tests (create/write/unlink), gate them on a separate flag — they hit the user's real Odoo instance.

## Architecture

Five source files in `Sources/ODXProxyClientSwift/`:

- **`OdxProxyClient.swift`** — singleton (`OdxProxyClient.shared`), `final class`, `@unchecked Sendable`. Holds an `NSLock`-protected `Config` snapshot (URLSession, four cached endpoint URLs, OdxInstanceInfo) plus a `configurationError` sentinel. Exposes internal helpers `postExecuteRPC`, `postVersionRequest`, `getAboutInfo`, `getLicenseInfo`. All share two private helpers — `postEnvelope` (POST → `OdxServerResponse<T>`) and `getRaw` (GET → flat `T`). Both call `Task.checkCancellation()` before encode and again before decode.
- **`OdxApi.swift`** — public `enum` with static methods for the data API (`/api/odoo/execute`): `search`, `searchRead`, `read`, `fieldsGet`, `searchCount`, `create`, `write`/`update`, `remove`, `callMethod`, `version`. Each builds an `OdxClientRequest`, strips pagination/ordering keywords where irrelevant, and delegates to the client.
- **`OdxOps.swift`** — public `enum` for ops endpoints (`/_/about`, `/_/license`). Kept separate from `OdxApi` per spec §7.10 (ops, not data API).
- **`OdxModels.swift`** — request/response Codable types: `OdxClientRequest`, `OdxServerResponse<T>`, `OdxServerErrorResponse`, `OdxVersionRequest`, `OdxAboutInfo`, `OdxLicenseInfo`, plus the `OdxParams` recursive enum and `OdxMany2One`/`OptionalOdxValue<T>` helpers for Odoo's loose JSON conventions.
- **`OdxErrors.swift`** — `OdxProxyError` enum with typed cases mapped from JSON-RPC codes (`authFailure`, `invalidAction`, `missingFunctionName`, `upstreamTimeout`, `upstreamConnect`, `proxyInternal`, `licenseInvalid`, `odooLogic`), plus `notConfigured` / `invalidURL` / `networkError` / `invalidResponse` / `decodingError` / `serverError`. `from(_:httpStatus:)` is the central mapper.
- **`Helper.swift`** — `AnyEncodable` / `AnyCodable` for heterogeneous JSON, a fast hex-table `ULID` (request id, not a real ULID — low 40 bits of timestamp + 16 random hex chars), `String.DefaultOrFalse` / `Array.DefaultOrFalse` (return `Any`, fragile but kept for caller compatibility).

### Threading (this library is built for SwiftUI)

Nothing public is `@MainActor` isolated. All API methods are `nonisolated async`. Per SE-0338, when called from `@MainActor` (typical SwiftUI `.task { ... }`), the body executes on the global cooperative executor — **JSON encode/decode and URLSession I/O run off the main thread.**

Specific design choices that protect this:
- `OdxProxyClient` is a `final class @unchecked Sendable` with an internal `NSLock`. The lock is only held by a sync helper (`snapshotConfig()`); async functions never call `lock.lock()` directly (Swift 6.2 forbids it).
- `JSONEncoder` and `JSONDecoder` are stored properties on the singleton (no per-call allocation).
- `URLSessionConfiguration.ephemeral` — no `URLCache` writes; authenticated responses don't sit in shared caches.
- The previous `URLSession` is `finishTasksAndInvalidate()`-ed on every `configure(...)` to avoid leaks.
- `Task.checkCancellation()` is called before encode and before decode in `postEnvelope` / `getRaw`. When a SwiftUI view disappears mid-request, the work doesn't waste CPU finishing a decode nobody wants.

If you reintroduce `@MainActor`, `Task.detached`, or background-decode helpers, you'll undo PR B. The point of dropping all three was to let SE-0338 handle off-main execution naturally.

### Request shape

Every data-API call sends `{ id, action, model_id, keyword, fn_name?, params, odoo_instance }` to `POST /api/odoo/execute`. The `action` string drives Odoo (`search`, `search_read`, `read`, `fields_get`, `search_count`, `create`, `write`, `unlink`, `call_method`). Only `callMethod` populates `fn_name` — the client-side guard throws `.missingFunctionName` for empty strings, mirroring proxy code `-32002`.

### Response decoding (non-obvious bits)

- `OdxServerResponse.init(from:)` decodes `id` as either `Int` or `String` (Odoo's own JSON-RPC id is sometimes int; the proxy round-trips it). Do not break this dual-path decode.
- `result` and `error` are mutually exclusive per spec §6. The custom decode reads `error` first; only attempts `result` decode when no error is present. This means a result that fails to decode against `T` surfaces a `DecodingError` (wrapped as `OdxProxyError.decodingError`) instead of silently producing `result == nil`.
- `OdxParams` stores numbers as `Double`. Odoo IDs above 2^53 would lose precision — academic, but be aware if you ever swap to `Int`.
- `OdxMany2One` and `OptionalOdxValue<T>` exist because Odoo returns `false` (not `null`) for unset relational/optional fields. Don't replace them with vanilla `Optional<T>`.

### Error handling

`postEnvelope` routes both non-2xx responses and 200-OK-with-error envelopes through `OdxProxyError.from(_:httpStatus:)`. The mapper distinguishes Odoo logic errors (200 OK + unknown code → `.odooLogic`) from proxy-layer errors with unknown codes (non-200 → `.serverError`). Existing code that did `catch OdxProxyError.serverError(let r)` and inspected `r.code` will no longer fire for the documented JSON-RPC codes — those hit their typed case.
