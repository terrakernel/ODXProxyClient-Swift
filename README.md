# ODX Proxy Swift Client

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5.7-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20macOS%20%7C%20macCatalyst%20%7C%20tvOS%20%7C%20visionOS%20%20%7C%20watchOS-blue.svg)](https://developer.apple.com/swift/)

ODXProxy Swift Client is a modern, lightweight, and performant Swift package designed to interact with the ODXProxy API. It enables native Swift applications, especially those built with SwiftUI, to communicate seamlessly with Odoo instances.

Built with performance and ease of use in mind, this client leverages Swift's modern concurrency features (`async/await`) for clean, efficient, and responsive networking.

## Features

-   **Modern Swift:** Utilizes `async/await` for clean and highly performant asynchronous code.
-   **SwiftUI First:** Designed to integrate seamlessly into SwiftUI applications and other modern Swift projects.
-   **Lean & Robust:** Minimal dependencies and a focus on maintainable, easy-to-understand code.
-   **Type Safe:** Leverages Swift's strong type system with `Codable` models for reliable API interaction.
-   **Comprehensive API Coverage:** Provides methods for all key Odoo operations like `search_read`, `write`, `create`, `unlink`, and more.
-   **Singleton Client:** A shared `OdxProxyClient` instance for easy, app-wide access.

## Requirements

-   iOS 15.0+ / macOS 12.0+ / watchOS 8.0+ / tvOS 15.0+
-   Swift 5.7+
-   Xcode 14.0+

## Installation

You can add ODX Proxy Swift Client to your Xcode project using Swift Package Manager.

1.  In Xcode, select **File > Add Packages...**
2.  Enter the repository URL: `https://github.com/terrakernel/odxproxyswift.git`
3.  Choose the package options, and add the package to your desired target.

## Usage

### 1. Configuration

Before making any API calls, you must configure the shared client instance. This is typically done once when your application starts, for example, in your SwiftUI `App`'s initializer.

```swift
import SwiftUI

@main
struct YourApp: App {
    init() {
        // 1. Define your Odoo instance details
        let odooInstance = OdxInstanceInfo(
            url: "https://your-odoo-instance.com",
            userId: 123,
            db: "your_database_name",
            apiKey: "your-odoo-api-key"
        )

        // 2. Define the ODX Proxy client configuration
        let clientInfo = OdxProxyClientInfo(
            instance: odooInstance,
            odxApiKey: "your-odx-proxy-api-key",
            gatewayUrl: "https://gateway.odxproxy.io" // Optional, defaults to this URL
        )

        // 3. Configure the shared client`

        OdxProxyClient.shared.configure(with: clientInfo)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

2. Making API Calls
Once configured, you can use the static methods on the OdxApi enum from anywhere in your app, such as a SwiftUI view's .task modifier or a view model.
Here's an example of fetching partner records and displaying them in a SwiftUI List.

```swift  
import SwiftUI

// Define a Codable model that matches the fields you request
struct Partner: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String?
}

struct ContentView: View {
    @State private var partners: [Partner] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List(partners) { partner in
                VStack(alignment: .leading) {
                    Text(partner.name).font(.headline)
                    if let email = partner.email {
                        Text(email).font(.subheadline).foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Partners")
            .task {
                await fetchPartners()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: {}) {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private func fetchPartners() async {
        do {
            // Define context and keywords for the request
            let context = OdxClientRequestContext(tz: "UTC")
            let keyword = OdxClientKeywordRequest(
                fields: ["id", "name", "email"],
                limit: 20,
                context: context
            )
            
            // Define a search domain (e.g., only fetch companies)
            // Use AnyEncodable for heterogeneous arrays
            let domain: [AnyEncodable] = [
                AnyEncodable(["is_company", "=", true])
            ]

            // Make the API call using async/await
            let response: OdxServerResponse<[Partner]> = try await OdxApi.searchRead(
                model: "res.partner",
                params: domain,
                keyword: keyword
            )

            if let result = response.result {
                // Update the UI on the main thread
                await MainActor.run {
                    self.partners = result
                }
            } else if let error = response.error {
                self.errorMessage = error.message
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
```

API Overview
All API methods are static functions on the OdxApi enum.
Method	Description
search()	Performs a search and returns record IDs.
searchRead()	Performs a search and returns a list of records with their data.
read()	Reads records by their IDs.
fieldsGet()	Retrieves metadata for model fields.
searchCount()	Counts the number of records matching a filter.
create()	Creates a new record.
write()	Updates existing records.
remove()	Deletes records (unlink).
callMethod()	Calls an arbitrary method on an Odoo model.
Error Handling
The client can throw errors of type OdxProxyError. You can catch these to handle specific issues like network failures or server-side problems.

```swift
do {
    // ... make api call
} catch OdxProxyError.serverError(let serverError) {
    print("Server Error \(serverError.code): \(serverError.message)")
} catch OdxProxyError.networkError(let underlyingError) {
    print("Network Error: \(underlyingError.localizedDescription)")
} catch {
    print("An unexpected error occurred: \(error.localizedDescription)")
}
```

License
This project is licensed under the MIT License. See the LICENSE file for details.
Copyright (c) 2025 TERRAKERNEL PTE. LTD.
Author: Julian Wajong julian.wajong@gmail.com
