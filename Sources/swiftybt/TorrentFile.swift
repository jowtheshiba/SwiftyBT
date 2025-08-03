import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Crypto

/// Represents a BitTorrent .torrent file
public struct TorrentFile {
    
    /// Torrent file metadata
    public struct Info {
        public let pieceLength: Int
        public let pieces: [Data]
        public let name: String
        public let length: Int?
        public let files: [File]?
        public let `private`: Bool?
        
        public init(pieceLength: Int, pieces: [Data], name: String, length: Int? = nil, files: [File]? = nil, private: Bool? = nil) {
            self.pieceLength = pieceLength
            self.pieces = pieces
            self.name = name
            self.length = length
            self.files = files
            self.`private` = `private`
        }
    }
    
    /// File information in multi-file torrents
    public struct File {
        public let length: Int
        public let path: [String]
        
        public init(length: Int, path: [String]) {
            self.length = length
            self.path = path
        }
    }
    
    /// Tracker information
    public struct Tracker {
        public let url: String
        public let tier: Int
        
        public init(url: String, tier: Int = 0) {
            self.url = url
            self.tier = tier
        }
    }
    
    public let info: Info
    public let rawInfoNode: Bencode.Value
    public let announce: String?
    public let announceList: [[String]]?
    public let creationDate: Date?
    public let comment: String?
    public let createdBy: String?
    public let encoding: String?
    
    public init(info: Info, rawInfoNode: Bencode.Value, announce: String? = nil, announceList: [[String]]? = nil, creationDate: Date? = nil, comment: String? = nil, createdBy: String? = nil, encoding: String? = nil) {
        self.info = info
        self.rawInfoNode = rawInfoNode
        self.announce = announce
        self.announceList = announceList
        self.creationDate = creationDate
        self.comment = comment
        self.createdBy = createdBy
        self.encoding = encoding
    }
    
    /// Parse torrent file from data
    /// - Parameter data: Raw torrent file data
    /// - Returns: Parsed torrent file
    /// - Throws: TorrentFileError if parsing fails
    public static func parse(_ data: Data) throws -> TorrentFile {
        print("DEBUG: Starting to parse torrent file, data size: \(data.count)")
        
        let bencodeValue = try Bencode.parse(data)
        print("DEBUG: Successfully parsed bencode")
        
        guard case .dictionary(let dict) = bencodeValue else {
            print("DEBUG: Root value is not a dictionary")
            throw TorrentFileError.invalidFormat
        }
        
        print("DEBUG: Root is dictionary with \(dict.count) keys")
        print("DEBUG: Keys: \(dict.keys)")
        
        guard let infoDict = dict["info"],
              case .dictionary(let infoData) = infoDict else {
            print("DEBUG: Missing or invalid info dictionary")
            throw TorrentFileError.missingInfo
        }
        
        print("DEBUG: Info dictionary has \(infoData.count) keys")
        print("DEBUG: Info keys: \(infoData.keys)")
        
        let info = try parseInfo(infoData)
        print("DEBUG: Successfully parsed info")
        
        let announce: String?
        if let value = dict["announce"], case .string(let str) = value {
            announce = str
            print("DEBUG: Found announce: \(str)")
        } else {
            announce = nil
            print("DEBUG: No announce found")
        }
        
        let announceList: [[String]]?
        if let value = dict["announce-list"], case .list(let list) = value {
            announceList = list.compactMap { item in
                guard case .list(let tier) = item else { return nil }
                let tierStrings = tier.compactMap { tierItem -> String? in
                    guard case .string(let str) = tierItem else { return nil }
                    return str
                }
                return tierStrings.isEmpty ? nil : tierStrings
            }
            print("DEBUG: Found announce-list with \(announceList?.count ?? 0) tiers")
        } else {
            announceList = nil
            print("DEBUG: No announce-list found")
        }
        
        let creationDate: Date?
        if let value = dict["creation date"], case .integer(let timestamp) = value {
            creationDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
            print("DEBUG: Found creation date: \(timestamp)")
        } else {
            creationDate = nil
            print("DEBUG: No creation date found")
        }
        
        let comment: String?
        if let value = dict["comment"], case .string(let str) = value {
            comment = str
            print("DEBUG: Found comment: \(str)")
        } else {
            comment = nil
            print("DEBUG: No comment found")
        }
        
        let createdBy: String?
        if let value = dict["created by"], case .string(let str) = value {
            createdBy = str
            print("DEBUG: Found created by: \(str)")
        } else {
            createdBy = nil
            print("DEBUG: No created by found")
        }
        
        let encoding: String?
        if let value = dict["encoding"], case .string(let str) = value {
            encoding = str
            print("DEBUG: Found encoding: \(str)")
        } else {
            encoding = nil
            print("DEBUG: No encoding found")
        }
        
        print("DEBUG: Creating TorrentFile object")
        return TorrentFile(
            info: info,
            rawInfoNode: infoDict,
            announce: announce,
            announceList: announceList,
            creationDate: creationDate,
            comment: comment,
            createdBy: createdBy,
            encoding: encoding
        )
    }
    
    /// Parse torrent file from file URL
    /// - Parameter url: File URL
    /// - Returns: Parsed torrent file
    /// - Throws: TorrentFileError if parsing fails
    public static func parse(from url: URL) throws -> TorrentFile {
        let data = try Data(contentsOf: url)
        return try parse(data)
    }
    
    /// Get info hash (SHA1 hash of the info dictionary)
    /// - Returns: Info hash as data
    /// - Throws: TorrentFileError if encoding fails
    public func getInfoHash() throws -> Data {
        let infoData = Bencode.encode(rawInfoNode)
        return Data(Insecure.SHA1.hash(data: infoData))
    }
    
    /// Get info hash from original bencode info node
    /// - Parameter rawInfoNode: Original bencode info node
    /// - Returns: Info hash as data
    /// - Throws: TorrentFileError if encoding fails
    public func getInfoHash(rawInfoNode: Bencode.Value) throws -> Data {
        let infoData = Bencode.encode(rawInfoNode)
        return Data(Insecure.SHA1.hash(data: infoData))
    }
    
    /// Get info hash as hex string
    /// - Returns: Info hash as hex string
    /// - Throws: TorrentFileError if encoding fails
    public func getInfoHashHex() throws -> String {
        let hash = try getInfoHash()
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Get total size of all files
    /// - Returns: Total size in bytes
    public func getTotalSize() -> Int {
        if let length = info.length {
            return length
        } else if let files = info.files {
            return files.reduce(0) { $0 + $1.length }
        }
        return 0
    }
    
    /// Get all trackers from announce and announce-list
    /// - Returns: Array of tracker URLs
    public func getAllTrackers() -> [String] {
        var trackers: [String] = []
        
        if let announce = announce {
            trackers.append(announce)
        }
        
        if let announceList = announceList {
            for tier in announceList {
                trackers.append(contentsOf: tier)
            }
        }
        
        return Array(Set(trackers)) // Remove duplicates
    }
    
    private static func parseInfo(_ dict: [String: Bencode.Value]) throws -> Info {
        print("DEBUG: parseInfo called with \(dict.count) keys")
        print("DEBUG: Info keys: \(dict.keys)")
        
        guard let pieceLengthValue = dict["piece length"],
              case .integer(let pieceLength) = pieceLengthValue else {
            print("DEBUG: Missing or invalid piece length")
            throw TorrentFileError.missingPieceLength
        }
        
        print("DEBUG: Piece length: \(pieceLength)")
        
        guard let piecesValue = dict["pieces"] else {
            print("DEBUG: Missing pieces")
            throw TorrentFileError.missingPieces
        }
        
        print("DEBUG: Pieces value type: \(piecesValue)")
        
        // Pieces data is raw bytes in bencode
        let pieces: [Data]
        switch piecesValue {
        case .string(let piecesString):
            print("DEBUG: Pieces is string, length: \(piecesString.count)")
            // Legacy case - convert UTF-8 string to bytes
            pieces = stride(from: 0, to: piecesString.count, by: 20).map {
                Data(piecesString.utf8.dropFirst($0).prefix(20))
            }
        case .binary(let piecesData):
            print("DEBUG: Pieces is binary, length: \(piecesData.count)")
            // Binary data - split into 20-byte pieces
            pieces = stride(from: 0, to: piecesData.count, by: 20).map {
                Data(piecesData.dropFirst($0).prefix(20))
            }
        default:
            print("DEBUG: Pieces is neither string nor binary")
            throw TorrentFileError.missingPieces
        }
        
        print("DEBUG: Parsed \(pieces.count) pieces")
        
        guard let nameValue = dict["name"],
              case .string(let name) = nameValue else {
            print("DEBUG: Missing or invalid name")
            throw TorrentFileError.missingName
        }
        
        print("DEBUG: Name: \(name)")
        
        let length: Int?
        if let value = dict["length"], case .integer(let len) = value {
            length = Int(len)
            print("DEBUG: Length: \(length!)")
        } else {
            length = nil
            print("DEBUG: No length found")
        }
        
        let files: [File]?
        if let value = dict["files"], case .list(let fileList) = value {
            print("DEBUG: Found files list with \(fileList.count) files")
            files = fileList.compactMap { fileValue -> File? in
                guard case .dictionary(let fileDict) = fileValue else { return nil }
                
                guard let lengthValue = fileDict["length"],
                      case .integer(let fileLength) = lengthValue else { return nil }
                
                guard let pathValue = fileDict["path"],
                      case .list(let pathList) = pathValue else { return nil }
                
                let path = pathList.compactMap { pathItem -> String? in
                    guard case .string(let pathStr) = pathItem else { return nil }
                    return pathStr
                }
                
                return File(length: Int(fileLength), path: path)
            }
        } else {
            files = nil
            print("DEBUG: No files found")
        }
        
        let isPrivate: Bool?
        if let value = dict["private"], case .integer(let privateVal) = value {
            isPrivate = privateVal == 1
            print("DEBUG: Private: \(isPrivate!)")
        } else {
            isPrivate = nil
            print("DEBUG: No private flag found")
        }
        
        print("DEBUG: Creating Info object")
        return Info(
            pieceLength: Int(pieceLength),
            pieces: pieces,
            name: name,
            length: length,
            files: files,
            private: isPrivate
        )
    }
}

/// Torrent file parsing errors
public enum TorrentFileError: Error {
    case invalidFormat
    case missingInfo
    case missingPieceLength
    case missingPieces
    case missingName
    case encodingFailed
}

// MARK: - Info Dictionary Extension
private extension TorrentFile.Info {
    func toDictionary() -> [String: Bencode.Value] {
        var dict: [String: Bencode.Value] = [
            "piece length": .integer(Int64(pieceLength)),
            "name": .string(name)
        ]
        
        let piecesData = pieces.map { Data($0) }.reduce(Data(), +)
        // Pieces should remain as raw bytes
        dict["pieces"] = .binary(piecesData)
        
        if let length = length {
            dict["length"] = .integer(Int64(length))
        }
        
        if let files = files {
            let fileList = files.map { file in
                Bencode.Value.dictionary([
                    "length": .integer(Int64(file.length)),
                    "path": .list(file.path.map { .string($0) })
                ])
            }
            dict["files"] = .list(fileList)
        }
        
        if let isPrivate = `private` {
            dict["private"] = .integer(isPrivate ? 1 : 0)
        }
        
        return dict
    }
} 
