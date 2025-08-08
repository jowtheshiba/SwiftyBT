import Foundation

public enum BEncodeValue: Equatable {
    case int(Int64)
    case bytes(Data)
    case list([BEncodeValue])
    case dict([String: BEncodeValue])
}

public enum BEncodeError: Error {
    case invalidFormat(String)
}

public struct BEncode {
    public static func decode(_ data: Data) throws -> BEncodeValue {
        var index = data.startIndex
        let value = try decodeValue(data, &index)
        return value
    }

    public static func decodePrefix(_ data: Data) throws -> (BEncodeValue, Int) {
        var index = data.startIndex
        let value = try decodeValue(data, &index)
        let consumed = data.distance(from: data.startIndex, to: index)
        return (value, consumed)
    }

    private static func decodeValue(_ data: Data, _ index: inout Data.Index) throws -> BEncodeValue {
        guard index < data.endIndex else { throw BEncodeError.invalidFormat("Unexpected EOF") }
        let byte = data[index]
        switch byte {
        case UInt8(ascii: "i"): // integer
            index = data.index(after: index)
            return try decodeInt(data, &index)
        case UInt8(ascii: "l"): // list
            index = data.index(after: index)
            return try decodeList(data, &index)
        case UInt8(ascii: "d"): // dict
            index = data.index(after: index)
            return try decodeDict(data, &index)
        case UInt8(ascii: "0")...UInt8(ascii: "9"): // bytes with length prefix
            return try decodeBytes(data, &index)
        default:
            throw BEncodeError.invalidFormat("Unexpected byte: \(byte)")
        }
    }

    private static func decodeInt(_ data: Data, _ index: inout Data.Index) throws -> BEncodeValue {
        var isNegative = false
        var numberString = ""
        guard index < data.endIndex else { throw BEncodeError.invalidFormat("EOF in int") }
        if data[index] == UInt8(ascii: "-") { isNegative = true; index = data.index(after: index) }
        while index < data.endIndex, data[index] != UInt8(ascii: "e") {
            let b = data[index]
            guard b >= UInt8(ascii: "0"), b <= UInt8(ascii: "9") else { throw BEncodeError.invalidFormat("Non-digit in int") }
            numberString.append(Character(UnicodeScalar(b)))
            index = data.index(after: index)
        }
        guard index < data.endIndex, data[index] == UInt8(ascii: "e") else { throw BEncodeError.invalidFormat("int not terminated") }
        index = data.index(after: index)
        let value = Int64(numberString) ?? 0
        return .int(isNegative ? -value : value)
    }

    private static func decodeBytes(_ data: Data, _ index: inout Data.Index) throws -> BEncodeValue {
        var lenStr = ""
        while index < data.endIndex {
            let byte = data[index]
            if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
                lenStr.append(Character(UnicodeScalar(byte)))
                index = data.index(after: index)
            } else {
                break
            }
        }
        guard index < data.endIndex, data[index] == UInt8(ascii: ":") else { throw BEncodeError.invalidFormat("Missing colon in bytes") }
        index = data.index(after: index)
        guard let length = Int(lenStr) else { throw BEncodeError.invalidFormat("Invalid length") }
        guard data.distance(from: index, to: data.endIndex) >= length else { throw BEncodeError.invalidFormat("Bytes EOF") }
        let slice = data[index..<data.index(index, offsetBy: length)]
        index = data.index(index, offsetBy: length)
        return .bytes(Data(slice))
    }

    private static func decodeList(_ data: Data, _ index: inout Data.Index) throws -> BEncodeValue {
        var values: [BEncodeValue] = []
        while index < data.endIndex, data[index] != UInt8(ascii: "e") {
            values.append(try decodeValue(data, &index))
        }
        guard index < data.endIndex, data[index] == UInt8(ascii: "e") else { throw BEncodeError.invalidFormat("list not terminated") }
        index = data.index(after: index)
        return .list(values)
    }

    private static func decodeDict(_ data: Data, _ index: inout Data.Index) throws -> BEncodeValue {
        var dict: [String: BEncodeValue] = [:]
        while index < data.endIndex, data[index] != UInt8(ascii: "e") {
            guard case .bytes(let keyData) = try decodeBytes(data, &index) else {
                throw BEncodeError.invalidFormat("dict key not bytes")
            }
            let key = String(data: keyData, encoding: .utf8) ?? String(decoding: keyData, as: UTF8.self)
            let value = try decodeValue(data, &index)
            dict[key] = value
        }
        guard index < data.endIndex, data[index] == UInt8(ascii: "e") else { throw BEncodeError.invalidFormat("dict not terminated") }
        index = data.index(after: index)
        return .dict(dict)
    }
}

extension BEncodeValue {
    public subscript(_ key: String) -> BEncodeValue? {
        if case .dict(let d) = self { return d[key] }
        return nil
    }
    public var dataValue: Data? {
        if case .bytes(let d) = self { return d }
        return nil
    }
    public var stringValue: String? {
        if case .bytes(let d) = self { return String(data: d, encoding: .utf8) }
        return nil
    }
    public var intValue: Int64? {
        if case .int(let i) = self { return i }
        return nil
    }
    public var listValue: [BEncodeValue]? {
        if case .list(let a) = self { return a }
        return nil
    }
    public var dictValue: [String: BEncodeValue]? {
        if case .dict(let d) = self { return d }
        return nil
    }
}


