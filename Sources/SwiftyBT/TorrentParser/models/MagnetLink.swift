import Foundation

struct MagnetLink {
    let infoHash: String
    let displayName: String?
    let trackers: [String]
    let exactLength: Int64?
    let exactTopic: String?
    let keywords: [String]
    
    init(from urlString: String) throws {
        guard let url = URL(string: urlString),
              url.scheme == "magnet" else {
            throw MagnetError.invalidMagnetURL("Invalid magnet URL format")
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw MagnetError.invalidMagnetURL("Cannot parse magnet URL")
        }
        
        // Извлекаем info hash
        guard let infoHashItem = queryItems.first(where: { $0.name == "xt" }),
              let infoHashValue = infoHashItem.value,
              infoHashValue.hasPrefix("urn:btih:") else {
            throw MagnetError.missingInfoHash("Missing or invalid info hash")
        }
        
        self.infoHash = String(infoHashValue.dropFirst("urn:btih:".count))
        
        // Извлекаем display name
        if let displayNameItem = queryItems.first(where: { $0.name == "dn" }),
           let displayNameValue = displayNameItem.value {
            self.displayName = displayNameValue.removingPercentEncoding
        } else {
            self.displayName = nil
        }
        
        // Извлекаем трекеры
        self.trackers = queryItems
            .filter { $0.name == "tr" }
            .compactMap { $0.value?.removingPercentEncoding }
        
        // Извлекаем exact length
        if let exactLengthItem = queryItems.first(where: { $0.name == "xl" }),
           let exactLengthValue = exactLengthItem.value {
            self.exactLength = Int64(exactLengthValue)
        } else {
            self.exactLength = nil
        }
        
        // Извлекаем exact topic
        if let exactTopicItem = queryItems.first(where: { $0.name == "kt" }),
           let exactTopicValue = exactTopicItem.value {
            self.exactTopic = exactTopicValue.removingPercentEncoding
        } else {
            self.exactTopic = nil
        }
        
        // Извлекаем keywords
        self.keywords = queryItems
            .filter { $0.name == "kt" }
            .compactMap { $0.value?.removingPercentEncoding }
    }
    
    /// Создает magnet-ссылку из параметров
    init(infoHash: String, displayName: String? = nil, trackers: [String] = [], exactLength: Int64? = nil) {
        self.infoHash = infoHash
        self.displayName = displayName
        self.trackers = trackers
        self.exactLength = exactLength
        self.exactTopic = nil
        self.keywords = []
    }
    
    /// Возвращает полную magnet-ссылку
    var magnetURL: String {
        var components = URLComponents()
        components.scheme = "magnet"
        components.queryItems = []
        
        // Info hash
        components.queryItems?.append(URLQueryItem(name: "xt", value: "urn:btih:\(infoHash)"))
        
        // Display name
        if let displayName = displayName {
            components.queryItems?.append(URLQueryItem(name: "dn", value: displayName))
        }
        
        // Trackers
        for tracker in trackers {
            components.queryItems?.append(URLQueryItem(name: "tr", value: tracker))
        }
        
        // Exact length
        if let exactLength = exactLength {
            components.queryItems?.append(URLQueryItem(name: "xl", value: String(exactLength)))
        }
        
        return components.url?.absoluteString ?? ""
    }
}
