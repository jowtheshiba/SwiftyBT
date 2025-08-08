import Foundation

class MagnetParser {
    
    /// Парсит magnet-ссылку
    /// - Parameter magnetURL: Magnet-ссылка для парсинга
    /// - Returns: Объект MagnetLink с распарсенными данными
    /// - Throws: MagnetError если ссылка неверного формата
    static func parseMagnetLink(_ magnetURL: String) throws -> MagnetLink {
        return try MagnetLink(from: magnetURL)
    }
    
    /// Выводит информацию о magnet-ссылке в консоль
    /// - Parameter magnetLink: Объект MagnetLink для вывода информации
    static func printMagnetInfo(_ magnetLink: MagnetLink) {
        print("=== Magnet Link Information ===")
        print()
        
        print("Info Hash: \(magnetLink.infoHash)")
        
        if let displayName = magnetLink.displayName {
            print("Display Name: \(displayName)")
        }
        
        if !magnetLink.trackers.isEmpty {
            print("Trackers:")
            for (index, tracker) in magnetLink.trackers.enumerated() {
                print("  \(index + 1). \(tracker)")
            }
        } else {
            print("Trackers: None")
        }
        
        if let exactLength = magnetLink.exactLength {
            print("Exact Length: \(exactLength) bytes")
        }
        
        if let exactTopic = magnetLink.exactTopic {
            print("Exact Topic: \(exactTopic)")
        }
        
        if !magnetLink.keywords.isEmpty {
            print("Keywords:")
            for keyword in magnetLink.keywords {
                print("  - \(keyword)")
            }
        }
        
        print()
        print("Full Magnet URL:")
        print(magnetLink.magnetURL)
    }
    
    /// Проверяет, является ли строка magnet-ссылкой
    /// - Parameter string: Строка для проверки
    /// - Returns: true если это magnet-ссылка
    static func isMagnetLink(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme == "magnet"
    }
    
    /// Извлекает info hash из magnet-ссылки
    /// - Parameter magnetURL: Magnet-ссылка
    /// - Returns: Info hash или nil если не найден
    static func extractInfoHash(from magnetURL: String) -> String? {
        guard let magnetLink = try? MagnetLink(from: magnetURL) else { return nil }
        return magnetLink.infoHash
    }
    
    /// Создает magnet-ссылку из torrent-файла
    /// - Parameter torrent: Объект TorrentFile
    /// - Returns: Magnet-ссылка или nil если не удалось создать
    static func createMagnetLink(from torrent: TorrentFile) -> String? {
        // Для создания magnet-ссылки нужен info hash
        // Это требует кодирования секции info обратно в BEncode
        // и вычисления SHA1 хеша
        
        // TODO: Реализовать создание info hash из torrent-файла
        // Пока возвращаем nil
        return nil
    }
}
