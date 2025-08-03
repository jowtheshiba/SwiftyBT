import Foundation

/// Tracker announce event types
public enum AnnounceEvent: String {
    case started = "started"
    case stopped = "stopped"
    case completed = "completed"
    case empty = ""
}

/// Tracker event types for UDP
public enum TrackerEvent: Int {
    case none = 0
    case completed = 1
    case started = 2
    case stopped = 3
}

/// Tracker response with peer information
public struct TrackerResponse {
    public let interval: Int
    public let minInterval: Int?
    public let complete: Int?
    public let incomplete: Int?
    public let peers: [Peer]
    public let warning: String?
    
    public init(interval: Int, minInterval: Int? = nil, complete: Int? = nil, incomplete: Int? = nil, peers: [Peer], warning: String? = nil) {
        self.interval = interval
        self.minInterval = minInterval
        self.complete = complete
        self.incomplete = incomplete
        self.peers = peers
        self.warning = warning
    }
}

/// Scrape response with torrent statistics
public struct ScrapeResponse {
    public let files: [Data: ScrapeFileInfo]
    
    public init(files: [Data: ScrapeFileInfo]) {
        self.files = files
    }
}

/// File information from scrape response
public struct ScrapeFileInfo {
    public let complete: Int
    public let downloaded: Int
    public let incomplete: Int
    public let name: String?
    
    public init(complete: Int, downloaded: Int, incomplete: Int, name: String? = nil) {
        self.complete = complete
        self.downloaded = downloaded
        self.incomplete = incomplete
        self.name = name
    }
}

/// Peer information
public struct Peer {
    public let address: String
    public let port: UInt16
    public let peerId: Data?
    
    public init(address: String, port: UInt16, peerId: Data? = nil) {
        self.address = address
        self.port = port
        self.peerId = peerId
    }
}

/// Tracker client errors
public enum TrackerError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, responseBody: String)
    case trackerFailure(reason: String, responseDetails: String)
    case missingInterval
    case invalidPeerFormat
}

/// Extension to convert AnnounceEvent to TrackerEvent
extension TrackerEvent {
    init(from announceEvent: AnnounceEvent) {
        switch announceEvent {
        case .started:
            self = .started
        case .stopped:
            self = .stopped
        case .completed:
            self = .completed
        case .empty:
            self = .none
        }
    }
} 