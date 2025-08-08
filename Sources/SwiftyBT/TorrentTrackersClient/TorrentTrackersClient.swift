import Foundation

@available(iOS 13.0, macOS 10.15, *)
actor TorrentTrackersClient {
    
    private var trackers: Set<TorrentURLTracker> = []
    
    /// Обрабатывает трекеры из TorrentFile и добавляет их в общий сет
    /// - Parameter torrentFile: TorrentFile для извлечения трекеров
    func processInitialTrackers(from torrentFile: TorrentFile) {
        // Добавляем основной трекер
        if let announce = torrentFile.announce {
            if let tracker = createTracker(from: announce) {
                trackers.insert(tracker)
            }
        }
        
        // Добавляем трекеры из announce list
        if let announceList = torrentFile.announceList {
            for group in announceList {
                for trackerURL in group {
                    if let tracker = createTracker(from: trackerURL) {
                        trackers.insert(tracker)
                    }
                }
            }
        }
    }
    
    /// Обрабатывает трекеры из MagnetLink и добавляет их в общий сет
    /// - Parameter magnetLink: MagnetLink для извлечения трекеров
    func processInitialTrackers(from magnetLink: MagnetLink) {
        for trackerURL in magnetLink.trackers {
            if let tracker = createTracker(from: trackerURL) {
                trackers.insert(tracker)
            }
        }
    }
    
    /// Создает TorrentURLTracker из URL строки
    /// - Parameter urlString: URL строка трекера
    /// - Returns: TorrentURLTracker или nil если URL неверный
    private func createTracker(from urlString: String) -> TorrentURLTracker? {
        guard let url = URL(string: urlString) else { return nil }
        
        let trackerType: TrackerType
        switch url.scheme?.lowercased() {
        case "udp":
            trackerType = .udp
        case "http":
            trackerType = .http
        case "https":
            trackerType = .https
        default:
            return nil
        }
        
        return TorrentURLTracker(trackerURL: urlString, trackerType: trackerType)
    }
    
    /// Возвращает все трекеры
    /// - Returns: Массив всех трекеров
    func getAllTrackers() -> [TorrentURLTracker] {
        return Array(trackers)
    }
    
    /// Возвращает количество трекеров
    /// - Returns: Количество трекеров
    func getTrackersCount() -> Int {
        return trackers.count
    }
    
    /// Добавляет трекер в общий сет
    /// - Parameter tracker: Трекер для добавления
    func addTracker(_ tracker: TorrentURLTracker) {
        trackers.insert(tracker)
    }
    
    /// Удаляет трекер из общего сета
    /// - Parameter tracker: Трекер для удаления
    func removeTracker(_ tracker: TorrentURLTracker) {
        trackers.remove(tracker)
    }
    
    /// Удаляет трекер по URL
    /// - Parameter url: URL трекера для удаления
    func removeTracker(withURL url: String) {
        trackers.removeAll()
    }
    
    /// Очищает все трекеры
    func clearAllTrackers() {
        trackers.removeAll()
    }
    
    /// Проверяет, содержит ли клиент указанный трекер
    /// - Parameter tracker: Трекер для проверки
    /// - Returns: true если трекер найден
    func containsTracker(_ tracker: TorrentURLTracker) -> Bool {
        return trackers.contains(tracker)
    }
    
    /// Возвращает трекеры определенного типа
    /// - Parameter type: Тип трекеров для фильтрации
    /// - Returns: Массив трекеров указанного типа
    func getTrackers(ofType type: TrackerType) -> [TorrentURLTracker] {
        return Array(trackers.filter { $0.trackerType == type })
    }
}
