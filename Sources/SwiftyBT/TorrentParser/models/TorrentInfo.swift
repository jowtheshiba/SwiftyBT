import Foundation

struct TorrentInfo {
    let pieceLength: Int64
    let pieces: Data
    let privateFlag: Bool?
    let name: String
    let files: [TorrentFileEntry]?
    let length: Int64?
    
    init(from bencodeValue: BEncodeValue) throws {
        guard let dict = bencodeValue.dictValue else {
            throw TorrentError.invalidInfo("Info section is not a dictionary")
        }
        
        guard let pieceLength = dict["piece length"]?.intValue else {
            throw TorrentError.invalidInfo("Missing piece length")
        }
        self.pieceLength = pieceLength
        
        guard let pieces = dict["pieces"]?.dataValue else {
            throw TorrentError.invalidInfo("Missing pieces")
        }
        self.pieces = pieces
        
        self.privateFlag = dict["private"]?.intValue == 1
        
        guard let name = dict["name"]?.stringValue else {
            throw TorrentError.invalidInfo("Missing name")
        }
        self.name = name
        
        if let filesArray = dict["files"]?.listValue {
            self.files = try filesArray.map { try TorrentFileEntry(from: $0) }
            self.length = nil
        } else {
            self.files = nil
            guard let length = dict["length"]?.intValue else {
                throw TorrentError.invalidInfo("Missing length for single file torrent")
            }
            self.length = length
        }
    }
}
