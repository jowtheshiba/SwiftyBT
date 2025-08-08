import Foundation
import Network
import CryptoKit

@available(macOS 10.15, *)
class DHTTrackersProvider: @unchecked Sendable {
    
    private var udpSocket: NWConnection?
    private var isSearching = false
    private var foundTrackers: [TorrentURLTracker] = []
    private let queue = DispatchQueue(label: "DHTTrackersProvider", qos: .utility)
    private var transactionId: String = ""
    private var nodeId: String = ""
    private var activeConnections: [NWConnection] = []
    
    // MARK: - Public Methods
    
    /// Запускает поиск DHT трекеров для TorrentFile
    /// - Parameters:
    ///   - torrentFile: Файл торрента
    ///   - completion: Колбэк с найденными трекерами
    func searchTrackers(for torrentFile: TorrentFile, completion: @escaping @Sendable ([TorrentURLTracker]) -> Void) {
        let infoHash = getInfoHash(from: torrentFile)
        searchTrackers(infoHash: infoHash, completion: completion)
    }
    
    /// Запускает поиск DHT трекеров для MagnetLink
    /// - Parameters:
    ///   - magnetLink: Магнет-ссылка
    ///   - completion: Колбэк с найденными трекерами
    func searchTrackers(for magnetLink: MagnetLink, completion: @escaping @Sendable ([TorrentURLTracker]) -> Void) {
        let infoHash = magnetLink.infoHash
        searchTrackers(infoHash: infoHash, completion: completion)
    }
    
    /// Останавливает поиск трекеров
    func stopSearch() {
        isSearching = false
        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()
        udpSocket?.cancel()
        udpSocket = nil
    }
    
    // MARK: - Private Methods
    
    private func searchTrackers(infoHash: String, completion: @escaping @Sendable ([TorrentURLTracker]) -> Void) {
        guard !isSearching else { return }
        
        isSearching = true
        foundTrackers.removeAll()
        activeConnections.removeAll()
        
        // Генерируем случайный transaction ID и node ID
        transactionId = generateRandomString(length: 2)
        nodeId = generateRandomString(length: 20)
        
        print("🔍 Starting DHT search for info_hash: \(infoHash)")
        print("🆔 Node ID: \(nodeId)")
        print("🆔 Transaction ID: \(transactionId)")
        
        queue.async { [weak self] in
            self?.startDHTBootstrap(infoHash: infoHash, completion: completion)
        }
    }
    
    private func startDHTBootstrap(infoHash: String, completion: @escaping @Sendable ([TorrentURLTracker]) -> Void) {
        // Начинаем с bootstrap узлов
        let bootstrapNodes = DHTPredefinedNodes.getAllNodes()
        
        print("🌐 Connecting to \(bootstrapNodes.count) DHT nodes...")
        
        for node in bootstrapNodes {
            connectToDHTNode(node: node, infoHash: infoHash, completion: completion)
        }
        
        // Таймаут для поиска
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            if self?.isSearching == true {
                print("⏰ DHT search timeout reached")
                self?.stopSearch()
                completion(self?.foundTrackers ?? [])
            }
        }
    }
    
    private func connectToDHTNode(node: String, infoHash: String, completion: @escaping @Sendable ([TorrentURLTracker]) -> Void) {
        let components = node.components(separatedBy: ":")
        guard components.count == 2,
              let host = components.first,
              let portString = components.last,
              let port = UInt16(portString) else {
            print("❌ Invalid DHT node format: \(node)")
            return
        }
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        
        let connection = NWConnection(to: endpoint, using: .udp)
        activeConnections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("🌐 Connected to DHT node: \(node)")
                self?.sendDHTGetPeersQuery(connection: connection, infoHash: infoHash)
            case .failed(let error):
                print("❌ Failed to connect to \(node): \(error)")
            case .cancelled:
                print("⏹️ Connection to \(node) cancelled")
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func sendDHTGetPeersQuery(connection: NWConnection, infoHash: String) {
        // Создаем DHT GET_PEERS запрос
        let query = createDHTGetPeersQuery(infoHash: infoHash)
        
        connection.send(content: query, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("❌ Failed to send DHT query: \(error)")
            } else {
                print("📤 DHT GET_PEERS query sent")
                self?.receiveDHTResponse(connection: connection)
            }
        })
    }
    
    private func receiveDHTResponse(connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            if let error = error {
                print("❌ DHT receive error: \(error)")
                return
            }
            
            if let data = content {
                print("📥 Received DHT response (\(data.count) bytes)")
                self?.processDHTResponse(data: data, connection: connection)
            }
            
            // Продолжаем слушать, если еще ищем
            if self?.isSearching == true {
                self?.receiveDHTResponse(connection: connection)
            }
        }
    }
    
    private func processDHTResponse(data: Data, connection: NWConnection) {
        // Парсим DHT ответ
        do {
            let response = try BEncode.decode(data)
            if let dict = response.dictValue {
                if let y = dict["y"]?.stringValue {
                    switch y {
                    case "r": // response
                        print("📋 Processing DHT response...")
                        if let r = dict["r"]?.dictValue {
                            if let values = r["values"]?.listValue {
                                // Найдены трекеры!
                                print("🎯 Found \(values.count) trackers in response!")
                                for value in values {
                                    if let trackerData = value.dataValue,
                                       let trackerString = String(data: trackerData, encoding: .utf8) {
                                        let tracker = TorrentURLTracker(
                                            trackerURL: trackerString,
                                            trackerType: .udp
                                        )
                                        foundTrackers.append(tracker)
                                        print("✅ Found DHT tracker: \(trackerString)")
                                    }
                                }
                            } else {
                                print("📋 Response contains no trackers")
                            }
                        }
                    case "e": // error
                        if let e = dict["e"]?.listValue,
                           e.count >= 2,
                           let errorCode = e[0].intValue,
                           let errorMessage = e[1].stringValue {
                            print("❌ DHT error: \(errorCode) - \(errorMessage)")
                        }
                    default:
                        print("📋 Unknown DHT message type: \(y)")
                    }
                }
            }
        } catch {
            print("❌ Failed to parse DHT response: \(error)")
            print("📋 Raw data: \(data.map { String(format: "%02x", $0) }.joined())")
        }
    }
    
    private func createDHTGetPeersQuery(infoHash: String) -> Data {
        // Создаем DHT GET_PEERS запрос в bencode формате
        var queryDict: [String: BEncodeValue] = [:]
        
        // Transaction ID
        queryDict["t"] = .bytes(transactionId.data(using: .utf8)!)
        
        // Query type
        queryDict["y"] = .bytes("q".data(using: .utf8)!)
        queryDict["q"] = .bytes("get_peers".data(using: .utf8)!)
        
        // Arguments
        var args: [String: BEncodeValue] = [:]
        args["id"] = .bytes(nodeId.data(using: .utf8)!)
        args["info_hash"] = .bytes(infoHash.data(using: .utf8)!)
        queryDict["a"] = .dict(args)
        
        let query = BEncode.encode(.dict(queryDict))
        return query
    }
    
    private func getInfoHash(from torrentFile: TorrentFile) -> String {
        // Вычисляем SHA1 хеш от bencoded info секции
        let infoBEncode = torrentFile.info.toBEncodeValue()
        let infoData = BEncode.encode(infoBEncode)
        
        let hash = Insecure.SHA1.hash(data: infoData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func generateRandomString(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}
