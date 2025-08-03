import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Bencode parser for BitTorrent .torrent files
public struct Bencode {
    
    /// Bencode value types
    public enum Value {
        case string(String)
        case integer(Int64)
        case list([Value])
        case dictionary([String: Value])
    }
    
    /// Parse bencode data
    /// - Parameter data: Raw bencode data
    /// - Returns: Parsed bencode value
    /// - Throws: BencodeError if parsing fails
    public static func parse(_ data: Data) throws -> Value {
        var scanner = BencodeScanner(data: data)
        return try scanner.parse()
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
            throw BencodeError.unexpectedEnd
        }
        
        let byte = data[index]
        
        switch byte {
        case ASCII.zero...ASCII.nine:
            return try parseString()
        case ASCII.i:
            return try parseInteger()
        case ASCII.l:
            return try parseList()
        case ASCII.d:
            return try parseDictionary()
        default:
            throw BencodeError.invalidFormat
        }
    }
    
    private mutating func parseString() throws -> Bencode.Value {
        let length = try parseLength()
        guard index + length <= data.endIndex else {
            throw BencodeError.unexpectedEnd
        }
        
        let stringData = data[index..<(index + length)]
        guard let string = String(data: stringData, encoding: .utf8) else {
            throw BencodeError.invalidString
        }
        
        index += length
        return .string(string)
    }
    
    private mutating func parseLength() throws -> Int {
        var length = 0
        while index < data.endIndex && data[index] != ASCII.colon {
            guard data[index] >= 48 && data[index] <= 57 else {
                throw BencodeError.invalidString
            }
            length = length * 10 + Int(data[index] - ASCII.zero)
            index += 1
        }
        
        guard index < data.endIndex && data[index] == ASCII.colon else {
            throw BencodeError.invalidString
        }
        
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
        index += 1 // Skip 'd'
        var dict: [String: Bencode.Value] = [:]
        
        while index < data.endIndex && data[index] != ASCII.e {
            let keyValue = try parse()
            guard case .string(let key) = keyValue else {
                throw BencodeError.invalidDictionary
            }
            
            let value = try parse()
            dict[key] = value
        }
        
        guard index < data.endIndex && data[index] == ASCII.e else {
            throw BencodeError.invalidDictionary
        }
        
        index += 1
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