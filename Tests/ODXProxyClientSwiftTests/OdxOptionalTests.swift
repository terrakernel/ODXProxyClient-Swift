//
//  OdxOptionalTests.swift
//
//  Pure-Swift unit tests for the @OdxOptional property wrapper. No
//  credentials, no network — these always run.
//

import Testing
import Foundation

@testable import ODXProxyClientSwift

@Suite("OdxOptional property wrapper")
struct OdxOptionalTests {

    private struct Item: Codable, Equatable {
        let id: Int
        @OdxOptional var note: String?

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id && lhs.note == rhs.note
        }
    }

    // MARK: - Decoding

    @Test("decodes a real string value")
    func decode_string() throws {
        let json = #"{"id":1,"note":"hello"}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(Item.self, from: json)
        #expect(item.note == "hello")
    }

    @Test("decodes Odoo's false-for-unset convention as nil")
    func decode_falseAsNil() throws {
        let json = #"{"id":1,"note":false}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(Item.self, from: json)
        #expect(item.note == nil)
    }

    @Test("decodes JSON null as nil")
    func decode_nullAsNil() throws {
        let json = #"{"id":1,"note":null}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(Item.self, from: json)
        #expect(item.note == nil)
    }

    @Test("decodes an absent key as nil")
    func decode_absentKeyAsNil() throws {
        let json = #"{"id":1}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(Item.self, from: json)
        #expect(item.note == nil)
    }

    @Test("surfaces type mismatch as a DecodingError (no silent nil)")
    func decode_typeMismatchThrows() {
        let json = #"{"id":1,"note":42}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Item.self, from: json)
        }
    }

    // MARK: - Encoding

    @Test("encodes nil as JSON false (Odoo convention)")
    func encode_nilAsFalse() throws {
        let item = Item(id: 1, note: nil)
        let data = try JSONEncoder().encode(item)
        let str = String(decoding: data, as: UTF8.self)
        #expect(str.contains("\"note\":false"))
    }

    @Test("encodes a value normally")
    func encode_valueAsValue() throws {
        let item = Item(id: 1, note: "hello")
        let data = try JSONEncoder().encode(item)
        let str = String(decoding: data, as: UTF8.self)
        #expect(str.contains("\"note\":\"hello\""))
    }

    @Test("round-trips through encode → decode")
    func roundTrip_preservesValue() throws {
        let original = Item(id: 1, note: "round-trip")
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Item.self, from: data)
        #expect(original == restored)
    }

    @Test("round-trips a nil value through encode → decode")
    func roundTrip_preservesNil() throws {
        let original = Item(id: 1, note: nil)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Item.self, from: data)
        #expect(original == restored)
    }
}
