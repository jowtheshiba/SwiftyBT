import Foundation

enum TorrentError: Error, LocalizedError {
    case invalidTorrent(String)
    case invalidInfo(String)
    case invalidFile(String)
    case fileNotFound(String)
    case invalidBEncode(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidTorrent(let message):
            return "Invalid torrent file: \(message)"
        case .invalidInfo(let message):
            return "Invalid info section: \(message)"
        case .invalidFile(let message):
            return "Invalid file entry: \(message)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidBEncode(let message):
            return "Invalid BEncode: \(message)"
        }
    }
}
