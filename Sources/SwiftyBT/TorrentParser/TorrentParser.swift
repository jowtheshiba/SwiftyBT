import Foundation

class TorrentParser {
    
    /// Парсит torrent-файл по указанному пути
    /// - Parameter path: Путь к torrent-файлу
    /// - Returns: Объект TorrentFile с распарсенными данными
    /// - Throws: TorrentError если файл не найден или имеет неверный формат
    static func parseTorrentFile(at path: String) throws -> TorrentFile {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        
        let bencodeValue = try BEncode.decode(data)
        return try TorrentFile(from: bencodeValue)
    }
    
    /// Выводит детальную информацию о всех данных в torrent-файле
    /// - Parameter torrent: Объект TorrentFile для вывода информации
    static func printDetailedTorrentInfo(_ torrent: TorrentFile) {
        print("=== Detailed Torrent File Information ===")
        print()
        
        // Основные поля
        if let announce = torrent.announce {
            print("Announce URL: \(announce)")
        } else {
            print("Announce URL: NOT FOUND")
        }
        
        if let announceList = torrent.announceList {
            print("Announce List:")
            for (index, group) in announceList.enumerated() {
                print("  Group \(index + 1):")
                for url in group {
                    print("    \(url)")
                }
            }
        } else {
            print("Announce List: NOT FOUND")
        }
        
        // Детальная информация о трекерах
        print()
        print("=== Tracker Information ===")
        print("Primary tracker: \(torrent.announce ?? "None")")
        print("Tracker groups count: \(torrent.announceList?.count ?? 0)")
        if let announceList = torrent.announceList {
            for (groupIndex, group) in announceList.enumerated() {
                print("  Group \(groupIndex + 1) (\(group.count) trackers):")
                for (trackerIndex, tracker) in group.enumerated() {
                    print("    \(trackerIndex + 1). \(tracker)")
                }
            }
        }
        
        if let creationDate = torrent.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            print("Creation Date: \(formatter.string(from: creationDate))")
        }
        
        if let comment = torrent.comment {
            print("Comment: \(comment)")
        }
        
        if let createdBy = torrent.createdBy {
            print("Created By: \(createdBy)")
        }
        
        if let encoding = torrent.encoding {
            print("Encoding: \(encoding)")
        }
        
        print()
        print("=== Info Section Details ===")
        print("Name: \(torrent.info.name)")
        print("Piece Length: \(torrent.info.pieceLength) bytes")
        print("Number of Pieces: \(torrent.info.pieces.count / 20)")
        print("Pieces Data Size: \(torrent.info.pieces.count) bytes")
        
        if let privateFlag = torrent.info.privateFlag {
            print("Private: \(privateFlag)")
        }
        
        if let files = torrent.info.files {
            print("Files:")
            for (index, file) in files.enumerated() {
                let pathString = file.path.joined(separator: "/")
                print("  \(index + 1). \(pathString) (\(file.length) bytes)")
                print("     Path components: \(file.path)")
            }
        } else if let length = torrent.info.length {
            print("Single File Size: \(length) bytes")
        }
        
        let totalSize = torrent.info.files?.reduce(0) { $0 + $1.length } ?? torrent.info.length ?? 0
        print("Total Size: \(totalSize) bytes")
        
        // Дополнительная информация о pieces
        print()
        print("=== Pieces Information ===")
        let pieceCount = torrent.info.pieces.count / 20
        print("Total Pieces: \(pieceCount)")
        print("Piece Size: \(torrent.info.pieceLength) bytes")
        
        // Показываем первые несколько хешей pieces
        if pieceCount > 0 {
            print("First 3 piece hashes:")
            for i in 0..<min(3, pieceCount) {
                let startIndex = i * 20
                let endIndex = startIndex + 20
                let pieceHash = torrent.info.pieces.subdata(in: startIndex..<endIndex)
                print("  Piece \(i): \(pieceHash.map { String(format: "%02x", $0) }.joined())")
            }
        }
    }
    
    /// Выводит информацию о torrent-файле в консоль
    /// - Parameter torrent: Объект TorrentFile для вывода информации
    static func printTorrentInfo(_ torrent: TorrentFile) {
        print("=== Torrent File Information ===")
        print()
        
        if let announce = torrent.announce {
            print("Announce URL: \(announce)")
        }
        
        if let announceList = torrent.announceList {
            print("Announce List:")
            for (index, group) in announceList.enumerated() {
                print("  Group \(index + 1):")
                for url in group {
                    print("    \(url)")
                }
            }
        }
        
        if let creationDate = torrent.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            print("Creation Date: \(formatter.string(from: creationDate))")
        }
        
        if let comment = torrent.comment {
            print("Comment: \(comment)")
        }
        
        if let createdBy = torrent.createdBy {
            print("Created By: \(createdBy)")
        }
        
        if let encoding = torrent.encoding {
            print("Encoding: \(encoding)")
        }
        
        print()
        print("=== Info Section ===")
        print("Name: \(torrent.info.name)")
        print("Piece Length: \(torrent.info.pieceLength) bytes")
        print("Number of Pieces: \(torrent.info.pieces.count / 20)")
        
        if let privateFlag = torrent.info.privateFlag {
            print("Private: \(privateFlag)")
        }
        
        if let files = torrent.info.files {
            print("Files:")
            for file in files {
                let pathString = file.path.joined(separator: "/")
                print("  \(pathString) (\(file.length) bytes)")
            }
        } else if let length = torrent.info.length {
            print("Single File Size: \(length) bytes")
        }
        
        let totalSize = torrent.info.files?.reduce(0) { $0 + $1.length } ?? torrent.info.length ?? 0
        print("Total Size: \(totalSize) bytes")
    }
}
