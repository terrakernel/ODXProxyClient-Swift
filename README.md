# ODX Proxy Swift Client

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20macOS%20%7C%20macCatalyst%20%7C%20tvOS%20%7C%20visionOS%20%20%7C%20watchOS-blue.svg)](https://developer.apple.com/swift/)

A modern, lightweight Swift client for the [ODXProxy](https://odxproxy.io) gateway — a reverse proxy that fronts one or more Odoo instances and exposes a unified JSON-RPC API. Designed primarily for SwiftUI apps that need to talk to Odoo without dragging in heavy networking stacks.

The wire protocol is documented in [`SYSTEM_ARCHITECTURE.md`](SYSTEM_ARCHITECTURE.md).

## Features

- **`async/await` everywhere.** No callbacks, no Combine boilerplate.
- **SwiftUI-first threading.** All JSON encoding/decoding and network I/O run on the cooperative thread pool — never on the main actor — so views stay responsive even on large payloads. Configured once and you can call the API from any view, view model, or `Task`.
- **Type-safe responses.** Generic `OdxServerResponse<T>` decodes Odoo records directly into your `Codable` types.
- **Typed errors.** Each JSON-RPC error code from the proxy maps to a distinct `OdxProxyError` case, so you can `catch` exactly the failure you care about.
- **Cancellation-aware.** Honors `Task` cancellation between network and decode, so a SwiftUI view that disappears mid-request doesn't waste CPU finishing a decode nobody wants.
- **Singleton client.** One configure call, one shared instance.

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+ / visionOS 1.0+ / macCatalyst 15.0+
- Swift 6.2+
- Xcode 26+

## Installation

In Xcode: **File → Add Packages…** and enter the repository URL:

```
https://github.com/terrakernel/odxproxyswift.git
```

Or in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/terrakernel/odxproxyswift.git", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "ODXProxyClientSwift", package: "odxproxyswift")
    ])
]
```

---

## Quick start

The smallest working end-to-end example: configure once in `App.init()`, then call from a view. The whole library follows this two-step pattern.

```swift
import SwiftUI
import ODXProxyClientSwift

@main
struct MyApp: App {
    init() {
        OdxProxyClient.shared.configure(
            with: OdxProxyClientInfo(
                instance: OdxInstanceInfo(
                    url: "https://erp.example.com",
                    userId: 2,
                    db: "prod",
                    apiKey: "<odoo user api key>"
                ),
                odxApiKey: "<proxy x-api-key>",
                gatewayUrl: "https://gateway.odxproxy.io"
            )
        )
    }
    var body: some Scene { WindowGroup { ContentView() } }
}

struct Partner: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
}

struct ContentView: View {
    @State private var partners: [Partner] = []

    var body: some View {
        List(partners) { Text($0.name) }
            .task {
                let context = OdxClientRequestContext(tz: "UTC")
                let keyword = OdxClientKeywordRequest(fields: ["id", "name"], limit: 50, context: context)
                let params  = OdxParams([[]] as [[Any]])    // empty domain = match all

                // Return type annotation IS required for generic inference.
                let response: OdxServerResponse<[Partner]> =
                    try! await OdxApi.searchRead(model: "res.partner", params: params, keyword: keyword)

                partners = response.result ?? []
            }
    }
}
```

> [!IMPORTANT]
> **Common gotchas — read these before writing code.**
>
> 1. **Generic returns must be annotated at the call site.** `let response: OdxServerResponse<[Partner]> = try await OdxApi.searchRead(...)` — Swift can't infer `T` from the call alone. If you omit the annotation, the call won't compile.
> 2. **`try await` on every call.** Every `OdxApi.*` and `OdxOps.*` method is `async throws`.
> 3. **Configure before any call.** Calling an API method before `OdxProxyClient.shared.configure(...)` throws `OdxProxyError.notConfigured`.
> 4. **`@OdxOptional` requires `var`, not `let`.** Property wrappers can't wrap immutable stored properties.
> 5. **`OdxParams([])` does NOT compile** — Swift can't infer the inner type. Use `OdxParams([[]] as [[Any]])` for an empty domain, or supply a typed inner array. See the [params cookbook](#5-building-params-with-odxparams).
> 6. **`Partner` / `Product` / etc. are YOUR types**, not library types. Define a `Codable` struct that matches the `fields` you requested.

---

## 1. Configuration — once, at app startup

The client is a singleton (`OdxProxyClient.shared`). You configure it **once** and then call the API from anywhere. Configuration is synchronous and cheap, so the natural place is your SwiftUI `App.init()`.

### Minimal example

```swift
import SwiftUI
import ODXProxyClientSwift

@main
struct MyApp: App {
    init() {
        let odooInstance = OdxInstanceInfo(
            url: "https://erp.example.com",
            userId: 2,
            db: "prod",
            apiKey: "<odoo user's api key>"
        )

        let clientInfo = OdxProxyClientInfo(
            instance: odooInstance,
            odxApiKey: "<proxy x-api-key>",
            gatewayUrl: "https://gateway.odxproxy.io"   // optional; this is the default
        )

        OdxProxyClient.shared.configure(with: clientInfo)
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### Parameters explained

| Parameter | Meaning |
|---|---|
| `OdxInstanceInfo.url` | Base URL of your Odoo server (the proxy will forward to this). |
| `OdxInstanceInfo.userId` | Odoo user id (an integer; uid 2 is usually `admin`). |
| `OdxInstanceInfo.db` | Odoo database name. |
| `OdxInstanceInfo.apiKey` | The **Odoo** user's API key (created in Odoo under user preferences → Account Security). **Not** the proxy key. |
| `OdxProxyClientInfo.odxApiKey` | The **proxy's** `x-api-key` header value. Different from the Odoo key above. |
| `OdxProxyClientInfo.gatewayUrl` | Base URL of the ODX proxy. Trailing slash is fine — the client strips it. Defaults to `https://gateway.odxproxy.io` when `nil`. |

### Optional: custom request timeout

```swift
OdxProxyClient.shared.configure(with: clientInfo, timeout: 30)  // seconds
```

Default is 60 seconds. Applies to each individual request.

### Re-configuring

You can call `configure(with:timeout:)` again at runtime (e.g. after a user switches accounts). The previous `URLSession` is drained and invalidated before being replaced — no leaks.

### What happens if you skip configuration?

Calling any API method before `configure(...)` throws `OdxProxyError.notConfigured`. If the gateway URL was malformed, you'll get `OdxProxyError.invalidURL` instead.

---

## 2. Calling the API from any view

Once `configure(...)` has run, every API method on `OdxApi` and `OdxOps` is callable from anywhere using `async`/`await`. You don't need to inject anything — the singleton makes the configuration globally available.

The library handles thread-hopping for you: JSON encode/decode and network I/O **always run off the main actor**, so you don't need to wrap calls in `Task.detached` or worry about UI hitches on large responses.

### From SwiftUI `.task { ... }` (most common)

`.task` is the idiomatic place to fetch on view appear. Its body is on `@MainActor`, but the library's `async` methods automatically hop off:

```swift
struct PartnersView: View {
    @State private var partners: [Partner] = []
    @State private var errorMessage: String?

    var body: some View {
        List(partners) { partner in
            VStack(alignment: .leading) {
                Text(partner.name).font(.headline)
                if let email = partner.email {
                    Text(email).foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await loadPartners()
        }
        .refreshable {
            await loadPartners()
        }
        .alert("Error",
               isPresented: .constant(errorMessage != nil),
               actions: { Button("OK") { errorMessage = nil } },
               message: { Text(errorMessage ?? "") })
    }

    private func loadPartners() async {
        do {
            let context = OdxClientRequestContext(tz: "UTC")
            let keyword = OdxClientKeywordRequest(
                fields: ["id", "name", "email"],
                limit: 50,
                context: context
            )
            let params = OdxParams([
                [["is_company", "=", true]]
            ])

            let response: OdxServerResponse<[Partner]> = try await OdxApi.searchRead(
                model: "res.partner",
                params: params,
                keyword: keyword
            )

            partners = response.result ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct Partner: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let email: String?
}
```

A few things to notice:

- **No `MainActor.run` needed.** Since `loadPartners()` is called from `.task`, it's already on the main actor when execution resumes after the `await`. Assignment to `partners` is on main.
- **Auto-cancellation.** If the user navigates away, `.task` cancels the underlying `Task`. The library checks `Task.isCancelled` between encode/network/decode, so an in-flight decode is short-circuited.
- **Pull-to-refresh.** `.refreshable` reuses the same async method.

### From a view model (`@MainActor` `ObservableObject`)

Cleaner for non-trivial screens, since you can hold state, retries, derived bindings, etc.

```swift
@MainActor
final class PartnersViewModel: ObservableObject {
    @Published var partners: [Partner] = []
    @Published var isLoading = false
    @Published var error: Error?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let context = OdxClientRequestContext(tz: "UTC")
            let keyword = OdxClientKeywordRequest(
                fields: ["id", "name", "email"],
                limit: 50,
                context: context
            )
            let response: OdxServerResponse<[Partner]> = try await OdxApi.searchRead(
                model: "res.partner",
                params: OdxParams([[]] as [[Any]]),
                keyword: keyword
            )
            partners = response.result ?? []
            error = nil
        } catch {
            self.error = error
        }
    }
}

struct PartnersView: View {
    @StateObject private var vm = PartnersViewModel()

    var body: some View {
        List(vm.partners) { partner in
            Text(partner.name)
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}
```

The view model is `@MainActor`, but `OdxApi.searchRead` is `nonisolated async` — Swift's runtime hops off main for the network + decode automatically.

### From a button or other UI action

```swift
Button("Refresh") {
    Task {
        await viewModel.load()
    }
}
```

### Running multiple requests concurrently

Use a `TaskGroup` or `async let`:

```swift
async let partners: OdxServerResponse<[Partner]> = OdxApi.searchRead(...)
async let products: OdxServerResponse<[Product]> = OdxApi.searchRead(...)
let (p, q) = try await (partners, products)
```

All requests share the same `URLSession`, so connection reuse is automatic.

---

## 3. Data API reference (`OdxApi`)

All methods are static `async throws` on the `OdxApi` enum. Each example below is self-contained — defines its own `keyword` / model struct — so it copy-pastes cleanly.

> [!NOTE]
> Every call needs `import ODXProxyClientSwift`. Every example below assumes the singleton has already been configured (see §1). All examples build a `keyword` inline because most methods take one — for repeated use, define it once at the top of your file or view model.

### `search` — return matching record IDs

```swift
public static func search(
    model: String,
    params: OdxParams,
    keyword: OdxClientKeywordRequest,
    id: String? = nil
) async throws -> OdxServerResponse<[Int]>
```

```swift
let keyword = OdxClientKeywordRequest(context: OdxClientRequestContext(tz: "UTC"))

let response = try await OdxApi.search(
    model: "res.partner",
    params: OdxParams([[["is_company", "=", true]]]),
    keyword: keyword
)
let ids: [Int] = response.result ?? []
```

### `searchRead` — search and read in one call (most common)

```swift
public static func searchRead<T: Codable & Sendable>(
    model: String,
    params: OdxParams,
    keyword: OdxClientKeywordRequest,
    id: String? = nil
) async throws -> OdxServerResponse<[T]>
```

```swift
struct Partner: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
}

let keyword = OdxClientKeywordRequest(
    fields: ["id", "name"],
    limit: 50,
    context: OdxClientRequestContext(tz: "UTC")
)

let response: OdxServerResponse<[Partner]> = try await OdxApi.searchRead(
    model: "res.partner",
    params: OdxParams([[["is_company", "=", true]]]),
    keyword: keyword
)
let partners: [Partner] = response.result ?? []
```

> [!TIP]
> The generic `T` is the **record** type, not the array. `searchRead` returns `OdxServerResponse<[T]>`, so you annotate with `[Partner]` and get `[Partner]?` in `result`.

### `read` — read specific records by id

```swift
public static func read<T: Codable & Sendable>(
    model: String,
    params: OdxParams,
    keyword: OdxClientKeywordRequest,
    id: String? = nil
) async throws -> OdxServerResponse<T>
```

```swift
struct Partner: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
}

let keyword = OdxClientKeywordRequest(
    fields: ["id", "name"],
    context: OdxClientRequestContext(tz: "UTC")
)

// params is [[ids]] — array containing one array of ids
let response: OdxServerResponse<[Partner]> = try await OdxApi.read(
    model: "res.partner",
    params: OdxParams([[1, 2, 3]] as [[Any]]),
    keyword: keyword
)
```

### `fieldsGet` — model schema (field types, help text, relations)

```swift
public static func fieldsGet<T: Codable & Sendable>(
    model: String,
    keyword: OdxClientKeywordRequest,
    id: String? = nil
) async throws -> OdxServerResponse<T>
```

```swift
let keyword = OdxClientKeywordRequest(context: OdxClientRequestContext(tz: "UTC"))

// `T` is a dict of field-name → metadata. Use [String: AnyCodable] to accept any shape.
let response: OdxServerResponse<[String: AnyCodable]> = try await OdxApi.fieldsGet(
    model: "res.partner",
    keyword: keyword
)
let schema = response.result ?? [:]
```

### `searchCount` — count matching records

```swift
public static func searchCount(
    model: String,
    params: OdxParams,
    keyword: OdxClientKeywordRequest,
    id: String? = nil
) async throws -> OdxServerResponse<Int>
```

```swift
let keyword = OdxClientKeywordRequest(context: OdxClientRequestContext(tz: "UTC"))

let response = try await OdxApi.searchCount(
    model: "res.partner",
    params: OdxParams([[["is_company", "=", true]]]),
    keyword: keyword
)
let count: Int = response.result ?? 0
```

### `create` — create a record (or records)

```swift
public static func create<T: Codable & Sendable>(
    model: String,
    params: OdxParams,
    keyword: OdxClientKeywordRequest,
    id: String? = nil
) async throws -> OdxServerResponse<T>
```

```swift
let keyword = OdxClientKeywordRequest(context: OdxClientRequestContext(tz: "UTC"))

let response: OdxServerResponse<Int> = try await OdxApi.create(
    model: "res.partner",
    params: OdxParams([
        ["name": "Acme Inc", "is_company": true]
    ]),
    keyword: keyword
)
let newId: Int? = response.result
```

### `write` / `update` — update records by id

```swift
public static func write<T: Codable & Sendable>(
    model: String,
    params: OdxParams,
    keyword: OdxClientKeywordRequest,
    id: String? = nil
) async throws -> OdxServerResponse<T>
```

```swift
let keyword = OdxClientKeywordRequest(context: OdxClientRequestContext(tz: "UTC"))

// params shape: [ [ids], { fields: values } ]
let response: OdxServerResponse<Bool> = try await OdxApi.write(
    model: "res.partner",
    params: OdxParams([[42], ["name": "Updated Name"]] as [Any]),
    keyword: keyword
)
```

`OdxApi.update` is an alias of `write` with the identical signature.

### `remove` — delete records (unlink)

```swift
public static func remove<T: Codable & Sendable>(
    model: String,
    params: OdxParams,
    keyword: OdxClientKeywordRequest,
    id: String? = nil
) async throws -> OdxServerResponse<T>
```

```swift
let keyword = OdxClientKeywordRequest(context: OdxClientRequestContext(tz: "UTC"))

let response: OdxServerResponse<Bool> = try await OdxApi.remove(
    model: "res.partner",
    params: OdxParams([[42]] as [[Any]]),
    keyword: keyword
)
```

### `callMethod` — call any model method (custom or built-in)

```swift
public static func callMethod<T: Codable & Sendable>(
    model: String,
    functionName: String,
    params: OdxParams,
    keyword: OdxClientKeywordRequest,
    id: String? = nil
) async throws -> OdxServerResponse<T>
```

```swift
let orderId = 42
let keyword = OdxClientKeywordRequest(context: OdxClientRequestContext(tz: "UTC"))

let response: OdxServerResponse<Bool> = try await OdxApi.callMethod(
    model: "sale.order",
    functionName: "action_confirm",
    params: OdxParams([[orderId]] as [[Any]]),
    keyword: keyword
)
```

An empty `functionName` throws `OdxProxyError.missingFunctionName` client-side — no wasted round-trip.

### `version` — query the Odoo instance's version banner

```swift
public static func version<T: Codable & Sendable>(
    url: String? = nil,
    id: String? = nil
) async throws -> OdxServerResponse<T>
```

```swift
struct VersionInfo: Codable, Sendable {
    let serverVersion: String?
    enum CodingKeys: String, CodingKey { case serverVersion = "server_version" }
}

// url defaults to the configured Odoo URL. Pass `url:` to query a different one.
let response: OdxServerResponse<VersionInfo> = try await OdxApi.version()
```

---

## 4. Ops API reference (`OdxOps`)

Operational, non-data endpoints. Kept separate from `OdxApi` per the proxy spec.

### `about` — proxy build identifier and version

```swift
public static func about() async throws -> OdxServerResponse<OdxAboutInfo>
```

```swift
let response = try await OdxOps.about()
if let info = response.result {
    print("Proxy \(info.version) (build \(info.build))")
}
```

`OdxAboutInfo` is `{ build: String, version: String }`.

### `license` — proxy license status

```swift
public static func license() async throws -> OdxLicenseInfo
```

```swift
let info = try await OdxOps.license()
print("\(info.licensee), valid until \(info.validUntil), valid: \(info.isValid)")
```

> [!NOTE]
> `license()` returns `OdxLicenseInfo` **directly**, not wrapped in `OdxServerResponse`. The proxy's `/_/license` endpoint emits a flat object, not a JSON-RPC envelope. This is the only method in the library that doesn't return an envelope.
>
> `OdxLicenseInfo` is `{ licensee: String, validUntil: String, isValid: Bool }`.

---

## 5. Building params with `OdxParams`

`OdxParams` is a recursive enum (`.string` / `.number` / `.bool` / `.null` / `.array` / `.object`) that holds any JSON shape Odoo expects. The `init(_ value: Any)` initializer converts from native Swift values.

### A 60-second primer on Odoo domains

Odoo "domains" are the search filters you pass as `params` to `search`, `searchRead`, and `searchCount`. They're nested arrays:

- Each **filter** is a 3-element array: `[field_name, operator, value]`
- A **domain** is an array of filters: `[["field1", "=", v1], ["field2", "!=", v2]]`
- Filters are **AND-ed** by default
- For OR / NOT, prefix the domain with `"|"` (OR), `"&"` (AND, explicit), or `"!"` (NOT). Each prefix node applies to the **next two** terms (`"|"`/`"&"`) or **next one** term (`"!"`).
- For data-API calls, the domain is the **first** positional arg to `execute_kw`, so the full `params` shape is `[[domain]]` — array containing one element, which is the domain itself.

Common operators: `=`, `!=`, `>`, `<`, `>=`, `<=`, `in`, `not in`, `like`, `ilike`, `=ilike`, `child_of`, `parent_of`.

Reference: [Odoo ORM domain documentation](https://www.odoo.com/documentation/16.0/developer/reference/backend/orm.html#search-domains).

### Cookbook — every shape you'll actually need

#### Empty domain (match all)

```swift
let p = OdxParams([[]] as [[Any]])
```

> [!CAUTION]
> The `as [[Any]]` annotation matters. `OdxParams([[]])` may not compile or may infer the wrong inner type. The cast tells Swift the inner array is a heterogeneous `[Any]`.

#### Single filter

```swift
let p = OdxParams([
    [["is_company", "=", true]]
])
```

The double-nesting is correct: outer `[ ... ]` is the `params` positional-args array, the inner `[ ... ]` is the domain itself.

#### Multiple filters (implicit AND)

```swift
let p = OdxParams([
    [
        ["is_company", "=", true],
        ["active", "=", true]
    ]
])
```

#### OR between two filters

```swift
let p = OdxParams([
    [
        "|",
        ["email", "ilike", "@acme.com"],
        ["name", "ilike", "Acme"]
    ]
])
```

#### NOT a filter

```swift
let p = OdxParams([
    [
        "!",
        ["is_company", "=", true]
    ]
])
```

#### `in` operator

```swift
let p = OdxParams([
    [
        ["state", "in", ["draft", "sent"]]
    ]
])
```

#### Read by ids — `[[ids]]`

```swift
let p = OdxParams([[1, 2, 3]] as [[Any]])
```

#### Create payload — `[{ fields }]`

```swift
let p = OdxParams([
    ["name": "Acme Inc", "is_company": true, "email": "hello@acme.com"]
])
```

#### Write payload — `[[ids], { fields }]`

```swift
let p = OdxParams([[1, 2, 3], ["active": false]] as [Any])
```

The outer `as [Any]` is required because the two elements have different Swift types (`[Int]` vs `[String: Bool]`) — without the cast, Swift can't pick a common element type.

#### `callMethod` payload — `[[args], { kwargs }]`

```swift
let orderId = 42
let p = OdxParams([[orderId], ["context": ["lang": "en_US"]]] as [Any])
```

### Type acceptance

`OdxParams.init(_ value: Any)` accepts: `String`, `Int`, `Double`, `Bool`, `NSNull`, `[Any]`, and `[String: Any]`. Anything else falls back to `.null` silently — if your params look empty server-side, check this first.

---

## 6. Error handling

The client throws `OdxProxyError`. The major cases:

| Case | When |
|---|---|
| `.notConfigured` | You called an API before `configure(...)`. |
| `.invalidURL` | `configure(...)` got a malformed `gatewayUrl`. |
| `.networkError(Error)` | Underlying `URLError` (DNS, connection refused, etc.) |
| `.invalidResponse(URLResponse?)` | Non-HTTP response from the proxy. |
| `.decodingError(Error)` | The response body didn't match your `T` (or wasn't valid JSON). |
| `.authFailure(_)` | Proxy `x-api-key` missing/wrong (proxy code `-32000`). |
| `.invalidAction(_)` | Action not in the proxy's allowlist (proxy code `-32001`). |
| `.missingFunctionName(_)` | `callMethod` without `fn_name` (proxy code `-32002`, also thrown client-side). |
| `.upstreamTimeout(_)` | Proxy → Odoo upstream timed out (proxy code `-32003`). |
| `.upstreamConnect(_)` | Proxy couldn't connect to Odoo (proxy code `-32004`). |
| `.proxyInternal(_)` | Internal proxy error (proxy code `-32005`). |
| `.licenseInvalid(_)` | Proxy license expired/invalid (proxy code `0`, HTTP 403). |
| `.odooLogic(_)` | Odoo-side business error (200 OK + error envelope, e.g. validation, access denied). |
| `.serverError(_)` | Unknown error code — fallback. |

Each `_` payload is an `OdxServerErrorResponse` with `code: Int`, `message: String`, and `data: AnyCodable?`. Catch broadly or narrowly:

```swift
do {
    let response: OdxServerResponse<[Partner]> = try await OdxApi.searchRead(...)
    // ...
} catch OdxProxyError.authFailure(let err) {
    print("Auth failed: \(err.message) — check your proxy x-api-key")
} catch OdxProxyError.upstreamTimeout(let err) {
    // Show a retry button
    print("Odoo timed out: \(err.message)")
} catch OdxProxyError.odooLogic(let err) {
    // Validation or access-rights error from Odoo itself
    showAlert(err.message)
} catch OdxProxyError.notConfigured {
    fatalError("Configure OdxProxyClient.shared in App.init before making API calls")
} catch {
    print("Unexpected error: \(error.localizedDescription)")
}
```

---

## 7. Working with Odoo's JSON quirks

Odoo sometimes returns `false` instead of `null` for unset values, and Many2One relations come back as `[id, name]` arrays. Two helper types normalize this:

### `OdxMany2One`

```swift
struct Product: Codable, Sendable {
    let id: Int
    let name: String
    let categ_id: OdxMany2One    // [1, "All"] OR false OR null
}

let category = product.categ_id
print(category.id ?? -1, category.name ?? "")
```

### `@OdxOptional` property wrapper

For scalar fields where Odoo may return `false` to mean "unset". You declare the field as a normal Swift `Optional` and the wrapper handles the wire-format quirk transparently.

> [!IMPORTANT]
> `@OdxOptional` requires `var` (not `let`) — property wrappers can't wrap immutable stored properties. Use it inside `struct`s normally; the synthesized memberwise init still works.

```swift
struct Product: Codable, Sendable {
    let id: Int
    let name: String

    @OdxOptional var barcode: String?        // "ABC123", false, null, or missing
    @OdxOptional var notes: String?
}

if let barcode = product.barcode {           // String? — read it like a normal Optional
    print(barcode)
}
```

**Decode behavior** (all four cases produce `nil`):

| Wire JSON           | `product.barcode` |
|---------------------|-------------------|
| `"ABC123"`          | `.some("ABC123")` |
| `false`             | `nil` (Odoo convention) |
| `null`              | `nil` |
| key absent          | `nil` |
| something else (`42`, `[]`) | throws `DecodingError` |

**Encode behavior** — `nil` round-trips back as JSON `false`, matching what Odoo expects when you're writing the field back:

```swift
let p = Product(id: 1, name: "Widget", barcode: nil, notes: "blue")
let data = try JSONEncoder().encode(p)
// → {"id":1,"name":"Widget","barcode":false,"notes":"blue"}
```

**Caveat — `Bool?`:** when `Wrapped == Bool`, the wire literal `false` always decodes as `nil` because Odoo uses the same value for both "actually false" and "unset". This is a wire-format limitation, not a library bug. If you need to distinguish, use a separate "is set" field or `Int?` with 0/1.

> Migration from earlier versions: `OptionalOdxValue<T>` has been replaced by `@OdxOptional`. The change is mechanical:
> `let foo: OptionalOdxValue<T>` → `@OdxOptional var foo: T?`, and drop `.value` at every read site.

---

## 8. Threading details (for the curious)

If you're not curious, skip this section — the defaults Just Work.

- `OdxProxyClient` is a `final class @unchecked Sendable`. Its mutable state is a `Config` snapshot guarded by an `NSLock`. Reads are constant-time and held for nanoseconds.
- All public API methods are `nonisolated async`. Per [SE-0338](https://github.com/apple/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md), when called from `@MainActor`, the body runs on the global cooperative executor — not the main actor.
- `JSONEncoder` and `JSONDecoder` are cached on the client (no per-call allocation).
- `URLSessionConfiguration.ephemeral` — no `URLCache` writes, so authenticated responses don't sit in a shared cache.
- `Task.checkCancellation()` is checked before encode and again before decode, so a cancelled `.task` doesn't waste CPU finishing a discarded response.

What this means in practice: you can call `OdxApi.searchRead(...)` from a `@MainActor` view, view model, or `Task { }` — the heavy work is automatically off the main thread, with no `.detached`, no `MainActor.run`, no manual queue management on your part.

---

## 9. Integration tests

Integration tests live in `Tests/ODXProxyClientSwiftTests/`. They run against a real proxy + Odoo instance.

```bash
cp Tests/ODXProxyClientSwiftTests/TestCredentials.swift.example \
   Tests/ODXProxyClientSwiftTests/TestCredentials.swift
# edit TestCredentials.swift to fill in your gateway / Odoo credentials
swift test
```

`TestCredentials.swift` is gitignored — your credentials never get committed. If any field is left empty, the entire suite is **skipped** (not failed) via `@Suite(.disabled(if: !TestCredentials.isConfigured))`, so a clean clone passes by default.

All tests are READ-ONLY against `res.partner`. To add mutating tests (create/write/unlink), gate them on a separate flag.

---

## License

MIT. See [`LICENSE`](LICENSE).

Copyright (c) 2025 TERRAKERNEL PTE. LTD.
Author: Julian Wajong &lt;julian.wajong@gmail.com&gt;
