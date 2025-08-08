import Foundation

struct TorrentFile {
    let announce: String?
    let announceList: [[String]]?
    let creationDate: Date?
    let comment: String?
    let createdBy: String?
    let encoding: String?
    let info: TorrentInfo
    
    init(from bencodeValue: BEncodeValue) throws {
        guard let dict = bencodeValue.dictValue else {
            throw TorrentError.invalidTorrent("Torrent file is not a dictionary")
        }
        
        self.announce = dict["announce"]?.stringValue
        
        if let announceListValue = dict["announce-list"]?.listValue {
            self.announceList = try announceListValue.map { group in
                guard let groupArray = group.listValue else {
                    throw TorrentError.invalidTorrent("Invalid announce list group")
                }
                return try groupArray.map { value in
                    guard let url = value.stringValue else {
                        throw TorrentError.invalidTorrent("Invalid announce URL")
                    }
                    return url
                }
            }
        } else {
            self.announceList = nil
        }
        
        if let creationDateValue = dict["creation date"]?.intValue {
            self.creationDate = Date(timeIntervalSince1970: TimeInterval(creationDateValue))
        } else {
            self.creationDate = nil
        }
        
        self.comment = dict["comment"]?.stringValue
        self.createdBy = dict["created by"]?.stringValue
        self.encoding = dict["encoding"]?.stringValue
        
        guard let infoValue = dict["info"] else {
            throw TorrentError.invalidTorrent("Missing info section")
        }
        
        self.info = try TorrentInfo(from: infoValue)
    }
}
