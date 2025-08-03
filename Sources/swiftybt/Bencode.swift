import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Bencode parser for BitTorrent .torrent files
public struct Bencode {
    
    /// Bencode value types
    public enum Value {
        case string(String)
        case binary(Data)  // For binary data like pieces
        case integer(Int64)
        case list([Value])
        case dictionary([String: Value])
    }
    
    /// Parse bencode data
    /// - Parameter data: Raw bencode data
    /// - Returns: Parsed bencode value
    /// - Throws: BencodeError if parsing fails
    public static func parse(_ data: Data) throws -> Value {
        print("DEBUG: Bencode.parse called with \(data.count) bytes")
        print("DEBUG: First 50 bytes: \(Array(data.prefix(50)))")
        
        var scanner = BencodeScanner(data: data)
        let result = try scanner.parse()
        
        print("DEBUG: Bencode.parse completed successfully")
        return result
    }
    
    /// Parse bencode string
    /// - Parameter string: Bencode string
    /// - Returns: Parsed bencode value
    /// - Throws: BencodeError if parsing fails
    public static func parse(_ string: String) throws -> Value {
        guard let data = string.data(using: .utf8) else {
            throw BencodeError.invalidEncoding
        }
        return try parse(data)
    }
    
    /// Encode value to bencode format
    /// - Parameter value: Bencode value to encode
    /// - Returns: Encoded data
    public static func encode(_ value: Value) -> Data {
        switch value {
        case .string(let string):
            let length = string.count
            return "\(length):\(string)".data(using: .utf8) ?? Data()
        case .binary(let data):
            let length = data.count
            var result = "\(length):".data(using: .utf8) ?? Data()
            result.append(data)
            return result
        case .integer(let int):
            return "i\(int)e".data(using: .utf8) ?? Data()
        case .list(let list):
            var data = "l".data(using: .utf8) ?? Data()
            for item in list {
                data.append(encode(item))
            }
            data.append("e".data(using: .utf8) ?? Data())
            return data
        case .dictionary(let dict):
            var data = "d".data(using: .utf8) ?? Data()
            let sortedKeys = dict.keys.sorted()
            for key in sortedKeys {
                data.append(encode(.string(key)))
                data.append(encode(dict[key]!))
            }
            data.append("e".data(using: .utf8) ?? Data())
            return data
        }
    }
}

/// Bencode parsing errors
public enum BencodeError: Error {
    case invalidFormat
    case invalidEncoding
    case unexpectedEnd
    case invalidInteger
    case invalidString
    case invalidList
    case invalidDictionary
}

/// Internal scanner for parsing bencode data
private struct BencodeScanner {
    private let data: Data
    private var index: Data.Index
    
    init(data: Data) {
        self.data = data
        self.index = data.startIndex
    }
    
    mutating func parse() throws -> Bencode.Value {
        guard index < data.endIndex else {
            print("DEBUG: Unexpected end at index \(index)")
            throw BencodeError.unexpectedEnd
        }
        
        let byte = data[index]
        print("DEBUG: Parsing byte \(byte) (ASCII: \(Character(UnicodeScalar(byte)))) at index \(index)")
        
        switch byte {
        case ASCII.zero...ASCII.nine:
            print("DEBUG: Parsing string")
            return try parseString()
        case ASCII.i:
            print("DEBUG: Parsing integer")
            return try parseInteger()
        case ASCII.l:
            print("DEBUG: Parsing list")
            return try parseList()
        case ASCII.d:
            print("DEBUG: Parsing dictionary")
            return try parseDictionary()
        default:
            print("DEBUG: Invalid format, byte: \(byte)")
            throw BencodeError.invalidFormat
        }
    }
    
    private mutating func parseString() throws -> Bencode.Value {
        print("DEBUG: parseString called at index \(index)")
        let length = try parseLength()
        print("DEBUG: String length: \(length)")
        
        guard index + length <= data.endIndex else {
            print("DEBUG: String would exceed data bounds")
            throw BencodeError.unexpectedEnd
        }
        
        let stringData = data[index..<(index + length)]
        print("DEBUG: String data: \(Array(stringData))")
        
        // For bencode, we need to handle both text and binary data
        // We'll try UTF-8 first, but if it fails, we'll use the raw data
        if let string = String(data: stringData, encoding: .utf8) {
            print("DEBUG: Parsed as UTF-8 string: \(string)")
            index += length
            return .string(string)
        } else {
            print("DEBUG: Parsed as binary data")
            // For binary data, we need to preserve the original bytes
            index += length
            return .binary(stringData)
        }
    }
    
    private mutating func parseLength() throws -> Int {
        print("DEBUG: parseLength called at index \(index)")
        var length = 0
        while index < data.endIndex && data[index] != ASCII.colon {
            print("DEBUG: Reading digit: \(data[index])")
            guard data[index] >= 48 && data[index] <= 57 else {
                print("DEBUG: Invalid character in length: \(data[index])")
                throw BencodeError.invalidString
            }
            length = length * 10 + Int(data[index] - ASCII.zero)
            index += 1
        }
        
        print("DEBUG: Parsed length: \(length)")
        
        guard index < data.endIndex && data[index] == ASCII.colon else {
            print("DEBUG: Expected colon but got: \(data[index])")
            throw BencodeError.invalidString
        }
        
        print("DEBUG: Found colon, advancing index")
        index += 1
        return length
    }
    
    private mutating func parseInteger() throws -> Bencode.Value {
        index += 1 // Skip 'i'
        var isNegative = false
        
        if index < data.endIndex && data[index] == ASCII.minus {
            isNegative = true
            index += 1
        }
        
        var value: Int64 = 0
        while index < data.endIndex && data[index] != ASCII.e {
            guard data[index] >= 48 && data[index] <= 57 else {
                throw BencodeError.invalidInteger
            }
            value = value * 10 + Int64(data[index] - ASCII.zero)
            index += 1
        }
        
        guard index < data.endIndex && data[index] == ASCII.e else {
            throw BencodeError.invalidInteger
        }
        
        index += 1
        return .integer(isNegative ? -value : value)
    }
    
    private mutating func parseList() throws -> Bencode.Value {
        index += 1 // Skip 'l'
        var list: [Bencode.Value] = []
        
        while index < data.endIndex && data[index] != ASCII.e {
            let value = try parse()
            list.append(value)
        }
        
        guard index < data.endIndex && data[index] == ASCII.e else {
            throw BencodeError.invalidList
        }
        
        index += 1
        return .list(list)
    }
    
    private mutating func parseDictionary() throws -> Bencode.Value {
        print("DEBUG: parseDictionary called at index \(index)")
        index += 1 // Skip 'd'
        var dict: [String: Bencode.Value] = [:]
        
        while index < data.endIndex && data[index] != ASCII.e {
            print("DEBUG: Parsing dictionary key at index \(index)")
            let keyValue = try parse()
            guard case .string(let key) = keyValue else {
                print("DEBUG: Dictionary key is not a string")
                throw BencodeError.invalidDictionary
            }
            
            print("DEBUG: Dictionary key: \(key)")
            print("DEBUG: Parsing dictionary value at index \(index)")
            let value = try parse()
            print("DEBUG: Dictionary value: \(value)")
            dict[key] = value
        }
        
        print("DEBUG: Dictionary parsing complete, found 'e' at index \(index)")
        guard index < data.endIndex && data[index] == ASCII.e else {
            print("DEBUG: Expected 'e' but got: \(data[index])")
            throw BencodeError.invalidDictionary
        }
        
        index += 1
        print("DEBUG: Dictionary parsing finished, returning \(dict.count) items")
        return .dictionary(dict)
    }
}

/// ASCII character constants
private enum ASCII {
    static let digit = UInt8(ascii: "0")
    static let zero = UInt8(ascii: "0")
    static let nine = UInt8(ascii: "9")
    static let i = UInt8(ascii: "i")
    static let l = UInt8(ascii: "l")
    static let d = UInt8(ascii: "d")
    static let e = UInt8(ascii: "e")
    static let colon = UInt8(ascii: ":")
    static let minus = UInt8(ascii: "-")
}

private extension UInt8 {
    var isNumber: Bool {
        return self >= ASCII.zero && self <= ASCII.nine
    }
} 