import Foundation

struct TorrentFileEntry {
    let length: Int64
    let path: [String]
    
    init(from bencodeValue: BEncodeValue) throws {
        guard let dict = bencodeValue.dictValue else {
            throw TorrentError.invalidFile("File entry is not a dictionary")
        }
        
        guard let length = dict["length"]?.intValue else {
            throw TorrentError.invalidFile("Missing file length")
        }
        self.length = length
        
        guard let pathArray = dict["path"]?.listValue else {
            throw TorrentError.invalidFile("Missing file path")
        }
        
        self.path = try pathArray.map { value in
            guard let pathComponent = value.stringValue else {
                throw TorrentError.invalidFile("Invalid path component")
            }
            return pathComponent
        }
    }
}
