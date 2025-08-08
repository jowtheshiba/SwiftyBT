import Foundation

struct DHTPredefinedNodes {
    
    /// Предопределенные DHT узлы для подключения
    static let predefinedNodes: [String] = [
        "router.bittorrent.com:6881",
        "router.utorrent.com:6881", 
        "router.bitcomet.com:6881",
        "dht.transmissionbt.com:6881",
        "dht.aelitis.com:6881"
    ]
    
    /// Возвращает все предопределенные узлы
    /// - Returns: Массив всех узлов
    static func getAllNodes() -> [String] {
        return predefinedNodes
    }
}
