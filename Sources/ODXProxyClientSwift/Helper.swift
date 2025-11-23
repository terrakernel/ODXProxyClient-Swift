import Foundation

// MARK: - AnyEncodable for params
public struct AnyEncodable: Encodable, @unchecked Sendable {
    private let value: Any

    public init<T>(_ value: T?) {
        self.value = value ?? ()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self.value {
        case is NSNull, is Void:
            try container.encodeNil()
        case let value as Bool:
            try container.encode(value)
        case let value as Int:
            try container.encode(value)
        case let value as Int8:
            try container.encode(value)
        case let value as Int16:
            try container.encode(value)
        case let value as Int32:
            try container.encode(value)
        case let value as Int64:
            try container.encode(value)
        case let value as UInt:
            try container.encode(value)
        case let value as UInt8:
            try container.encode(value)
        case let value as UInt16:
            try container.encode(value)
        case let value as UInt32:
            try container.encode(value)
        case let value as UInt64:
            try container.encode(value)
        case let value as Float:
            try container.encode(value)
        case let value as Double:
            try container.encode(value)
        case let value as String:
            try container.encode(value)
        case let value as [Any?]:
            try container.encode(value.map { AnyEncodable($0) })
        case let value as [String: Any?]:
            try container.encode(value.mapValues { AnyEncodable($0) })
        default:
            throw EncodingError.invalidValue(self.value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyEncodable value cannot be encoded"))
        }
    }
}

// MARK: - AnyCodable for error data
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init<T>(_ value: T?) {
        self.value = value ?? ()
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = ()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self.value {
        case is NSNull, is Void:
            try container.encodeNil()
        case let value as Bool:
            try container.encode(value)
        case let value as Int:
            try container.encode(value)
        case let value as Double:
            try container.encode(value)
        case let value as String:
            try container.encode(value)
        case let value as [Any]:
            try container.encode(value.map { AnyCodable($0) })
        case let value as [String: Any]:
            try container.encode(value.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(self.value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}


// MARK: - ULID
public struct ULID: Sendable {
    public let ulidString: String
    
    public init() {
        self.ulidString = ULID.generate()
    }
    
    private static func generate() -> String {
        let time = String(format:"%010X", Int(Date().timeIntervalSince1970 * 1000))
        var random = ""
        for _ in 0..<16 {
            random += String(format: "%X", Int.random(in: 0...15))
        }
        return time + random
    }
}

public extension String {
    
    /// A helper function that returns `false` if the string is empty;
    /// otherwise it returns the string unchanged.
    ///
    /// Useful when sending data to Odoo fields where `false` represents an
    /// optional or unset value.
    public var DefaultOrFalse: Any {
        self.isEmpty ? false: self
    }
}

public extension Array where Element: Codable {
    /// Returns `false` when the array is empty,
    /// or the array itself when it contains values.
    ///
    /// Useful for preparing Many2many or One2many fields in Odoo RPC payloads.
    public var DefaultOrFalse: Any {
        self.isEmpty ? false: self
    }
}


// MARK: - JSONDecoder and JSONEncoder Helper extension which will process the json in the background

public extension JSONDecoder {
    
    /// Decodes a `Decodable & Sendable` type from raw `Data` on a background thread,
    /// using a detached task.
    ///
    /// This is useful when parsing large JSON payloads, such as Odoo responses
    /// containing hundreds of records or deep nested relational fields.
    /// By offloading the decoding to a background thread, your UI stays responsive
    /// and avoids blocking the main actor.
    ///
    /// ## Concurrency
    /// - Runs inside `Task.detached(priority: .medium)`
    /// - Guaranteed to execute off the main actor
    /// - `T` must conform to `Sendable` to be safely transferred across concurrency boundaries
    ///
    /// ## Example
    /// ```swift
    /// struct Product: Decodable, Sendable { ... }
    ///
    /// let data = fetchFromServer()
    ///
    /// let product: Product = try await JSONDecoder.decodeInBackground(
    ///     Product.self,
    ///     from: data
    /// )
    /// ```
    ///
    /// ## Notes
    /// - Uses a fresh `JSONDecoder()` inside the detached task for thread-safety.
    /// - Any decoding error is automatically propagated back to the caller.
    /// - Ideal for workloads where JSON is the primary format (e.g., Odoo RPC / REST API).
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: Raw JSON data received from the network.
    /// - Returns: A fully-decoded instance of type `T`.
    /// - Throws: Any decoding error thrown by `JSONDecoder`.
    static func decodeInBackground<T: Decodable & Sendable>(
        _ type: T.Type,
        from data: Data
    ) async throws -> T {
        try await Task.detached(priority: .medium){
            try JSONDecoder().decode(T.self, from: data)
        }.value
    }
}


public extension JSONEncoder {
    
    /// Encodes any `Encodable & Sendable` value into `Data` on a background thread,
    /// using a detached task.
    ///
    /// This allows you to offload heavy JSON encoding work away from the main actor,
    /// keeping the UI responsive—especially useful when encoding large API payloads,
    /// arrays with hundreds of items, or deeply nested Odoo structures.
    ///
    /// ## Concurrency
    /// - Uses `Task.detached(priority: .medium)`
    /// - Guaranteed to run outside the main actor
    /// - `T` must conform to `Sendable` to safely cross concurrency boundaries
    ///
    /// ## Example
    /// ```swift
    /// struct Product: Codable, Sendable { ... }
    ///
    /// let encoded = try await JSONEncoder.encodeInBackground(product)
    /// upload(encoded)
    /// ```
    ///
    /// ## Notes
    /// - Creating a fresh `JSONEncoder()` inside the task avoids any thread-affinity issues.
    /// - If encoding throws (for example due to invalid types or dates), the task correctly
    ///   propagates the error back to the caller.
    /// - Designed for high-performance apps where JSON is the primary transport format
    ///   (such as Odoo API clients).
    ///
    /// - Parameter value: The encodable value to serialize.
    /// - Returns: Serialized `Data` produced by `JSONEncoder`.
    /// - Throws: Any encoding error thrown by `JSONEncoder`.
    static func encodeInBackground<T: Encodable & Sendable>(
        _ value: T
    ) async throws -> Data {
        try await Task.detached(priority: .medium){
            try JSONEncoder().encode(value)
        }.value
    }
}
