import Foundation
import Logging

/// Extended tracker client with support for multiple trackers and additional features
public class ExtendedTrackerClient {
    private let logger: Logger
    private let baseTrackerClient: TrackerClient
    private let additionalTrackers: [String]
    private let maxConcurrentAnnounces = 5
    private let announceTimeout: TimeInterval = 10.0
    
    public init(additionalTrackers: [String] = []) {
        self.logger = Logger(label: "SwiftyBT.ExtendedTracker")
        self.baseTrackerClient = TrackerClient()
        self.additionalTrackers = additionalTrackers
    }
    
    /// Get comprehensive list of trackers for a torrent
    /// - Parameter torrentFile: Torrent file
    /// - Returns: Array of all available trackers
    public func getAllTrackers(for torrentFile: TorrentFile) -> [String] {
        var trackers: [String] = []
        
        // Add trackers from torrent file
        trackers.append(contentsOf: torrentFile.getAllTrackers())
        
        // Add additional public trackers
        trackers.append(contentsOf: getPublicTrackers())
        
        // Add additional trackers from configuration
        trackers.append(contentsOf: additionalTrackers)
        
        // Remove duplicates while preserving order
        var uniqueTrackers: [String] = []
        var seen: Set<String> = []
        
        for tracker in trackers {
            let normalized = normalizeTrackerURL(tracker)
            if !seen.contains(normalized) {
                uniqueTrackers.append(tracker)
                seen.insert(normalized)
            }
        }
        
        return uniqueTrackers
    }
    
    /// Announce to multiple trackers concurrently
    /// - Parameters:
    ///   - torrentFile: Torrent file
    ///   - infoHash: Info hash of the torrent
    ///   - peerId: Client peer ID
    ///   - port: Port for incoming connections
    ///   - uploaded: Bytes uploaded
    ///   - downloaded: Bytes downloaded
    ///   - left: Bytes left to download
    ///   - event: Announce event type
    /// - Returns: Combined tracker responses
    /// - Throws: TrackerError if all trackers fail
    public func announceToMultipleTrackers(
        torrentFile: TorrentFile,
        infoHash: Data,
        peerId: Data,
        port: UInt16,
        uploaded: Int64 = 0,
        downloaded: Int64 = 0,
        left: Int64,
        event: AnnounceEvent = .started
    ) async throws -> ExtendedTrackerResponse {
        let trackers = getAllTrackers(for: torrentFile)
        logger.info("Announcing to \(trackers.count) trackers")
        
        let results = await withTaskGroup(of: (String, Result<TrackerResponse, Error>).self) { group in
            for tracker in trackers {
                group.addTask {
                    do {
                        let response = try await self.baseTrackerClient.announce(
                            url: tracker,
                            infoHash: infoHash,
                            peerId: peerId,
                            port: port,
                            uploaded: uploaded,
                            downloaded: downloaded,
                            left: left,
                            event: event
                        )
                        return (tracker, .success(response))
                    } catch {
                        return (tracker, .failure(error))
                    }
                }
            }
            
            var responses: [TrackerResponse] = []
            var errors: [String: Error] = [:]
            
            for await (tracker, result) in group {
                switch result {
                case .success(let response):
                    responses.append(response)
                case .failure(let error):
                    errors[tracker] = error
                }
            }
            
            return (responses, errors)
        }
        
        let responses = results.0
        let errors = results.1
        
        // Log results
        logger.info("Successfully announced to \(responses.count) trackers")
        
        for (tracker, error) in errors {
            logger.warning("Failed to announce to \(tracker): \(error)")
        }
        
        // Create combined response
        let combinedResponse = combineTrackerResponses(responses)
        
        return ExtendedTrackerResponse(
            responses: responses,
            errors: errors,
            combinedPeers: combinedResponse.peers.map { "\($0.address):\($0.port)" },
            totalPeers: combinedResponse.peers.count,
            successfulTrackers: responses.count,
            failedTrackers: errors.keys.count
        )
    }
    
    /// Scrape multiple trackers concurrently
    /// - Parameters:
    ///   - torrentFile: Torrent file
    ///   - infoHashes: Array of info hashes to scrape
    /// - Returns: Combined scrape responses
    /// - Throws: TrackerError if all trackers fail
    public func scrapeMultipleTrackers(
        torrentFile: TorrentFile,
        infoHashes: [Data]
    ) async throws -> ExtendedScrapeResponse {
        let trackers = getAllTrackers(for: torrentFile)
        logger.info("Scraping \(trackers.count) trackers")
        
        let results = await withTaskGroup(of: (String, Result<ScrapeResponse, Error>).self) { group in
            for tracker in trackers {
                group.addTask {
                    do {
                        let response = try await self.baseTrackerClient.scrape(
                            url: tracker,
                            infoHashes: infoHashes
                        )
                        return (tracker, .success(response))
                    } catch {
                        return (tracker, .failure(error))
                    }
                }
            }
            
            var responses: [ScrapeResponse] = []
            var errors: [String: Error] = [:]
            
            for await (tracker, result) in group {
                switch result {
                case .success(let response):
                    responses.append(response)
                case .failure(let error):
                    errors[tracker] = error
                }
            }
            
            return (responses, errors)
        }
        
        let responses = results.0
        let errors = results.1
        
        // Log results
        logger.info("Successfully scraped \(responses.count) trackers")
        
        for (tracker, error) in errors {
            logger.warning("Failed to scrape \(tracker): \(error)")
        }
        
        // Create combined response
        let combinedResponse = combineScrapeResponses(responses)
        
        return ExtendedScrapeResponse(
            responses: responses,
            errors: errors,
            combinedStats: combinedResponse,
            successfulTrackers: responses.count,
            failedTrackers: errors.keys.count
        )
    }
    
    /// Get public trackers list
    /// - Returns: Array of public tracker URLs
    private func getPublicTrackers() -> [String] {
        // Use UDPTrackersProvider for comprehensive tracker list
        return UDPTrackersProvider.getAllUDPTrackers()
    }
    
    /// Normalize tracker URL for deduplication
    /// - Parameter url: Tracker URL
    /// - Returns: Normalized URL
    private func normalizeTrackerURL(_ url: String) -> String {
        var normalized = url.lowercased()
        
        // Remove trailing slash
        if normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        
        // Remove /announce suffix for comparison
        if normalized.hasSuffix("/announce") {
            normalized = String(normalized.dropLast(9))
        }
        
        return normalized
    }
    
    /// Combine multiple tracker responses
    /// - Parameter responses: Array of tracker responses
    /// - Returns: Combined response
    private func combineTrackerResponses(_ responses: [TrackerResponse]) -> TrackerResponse {
        var allPeers: Set<String> = []
        var totalInterval: Int = 0
        var totalMinInterval: Int = 0
        var totalComplete: Int = 0
        var totalIncomplete: Int = 0
        
        for response in responses {
            allPeers.formUnion(response.peers.map { "\($0.address):\($0.port)" })
            totalInterval += response.interval
            totalMinInterval += response.minInterval ?? 0
            totalComplete += response.complete ?? 0
            totalIncomplete += response.incomplete ?? 0
        }
        
        let averageInterval = responses.isEmpty ? 1800 : totalInterval / responses.count
        let averageMinInterval = responses.isEmpty ? 900 : totalMinInterval / responses.count
        
        let peerObjects = allPeers.map { peerString in
            let components = peerString.split(separator: ":")
            guard components.count == 2,
                  let port = UInt16(components[1]) else {
                return Peer(address: peerString, port: 0)
            }
            return Peer(address: String(components[0]), port: port)
        }
        
        return TrackerResponse(
            interval: averageInterval,
            minInterval: averageMinInterval,
            complete: totalComplete,
            incomplete: totalIncomplete,
            peers: peerObjects
        )
    }
    
    /// Combine multiple scrape responses
    /// - Parameter responses: Array of scrape responses
    /// - Returns: Combined scrape response
    private func combineScrapeResponses(_ responses: [ScrapeResponse]) -> ScrapeResponse {
        // For now, create a simple combined response
        // In a real implementation, you would aggregate the file statistics
        return ScrapeResponse(files: [:])
    }
    
    /// Test tracker connectivity
    /// - Parameter tracker: Tracker URL
    /// - Returns: True if tracker is reachable
    public func testTracker(_ tracker: String) async -> Bool {
        do {
            _ = try await baseTrackerClient.announce(
                url: tracker,
                infoHash: Data(repeating: 0, count: 20),
                peerId: Data(repeating: 0, count: 20),
                port: 6881,
                uploaded: 0,
                downloaded: 0,
                left: 0,
                event: .started
            )
            return true
        } catch {
            logger.warning("Tracker \(tracker) is not reachable: \(error)")
            return false
        }
    }
    
    /// Test multiple trackers and return working ones
    /// - Parameter trackers: Array of tracker URLs
    /// - Returns: Array of working tracker URLs
    public func testTrackers(_ trackers: [String]) async -> [String] {
        var workingTrackers: [String] = []
        
        await withTaskGroup(of: (String, Bool).self) { group in
            for tracker in trackers {
                group.addTask {
                    let isWorking = await self.testTracker(tracker)
                    return (tracker, isWorking)
                }
            }
            
            for await (tracker, isWorking) in group {
                if isWorking {
                    workingTrackers.append(tracker)
                }
            }
        }
        
        return workingTrackers
    }
}

/// Extended tracker response with multiple tracker results
public struct ExtendedTrackerResponse {
    public let responses: [TrackerResponse]
    public let errors: [String: Error]
    public let combinedPeers: [String]
    public let totalPeers: Int
    public let successfulTrackers: Int
    public let failedTrackers: Int
    
    public init(
        responses: [TrackerResponse],
        errors: [String: Error],
        combinedPeers: [String],
        totalPeers: Int,
        successfulTrackers: Int,
        failedTrackers: Int
    ) {
        self.responses = responses
        self.errors = errors
        self.combinedPeers = combinedPeers
        self.totalPeers = totalPeers
        self.successfulTrackers = successfulTrackers
        self.failedTrackers = failedTrackers
    }
}

/// Extended scrape response with multiple tracker results
public struct ExtendedScrapeResponse {
    public let responses: [ScrapeResponse]
    public let errors: [String: Error]
    public let combinedStats: ScrapeResponse
    public let successfulTrackers: Int
    public let failedTrackers: Int
    
    public init(
        responses: [ScrapeResponse],
        errors: [String: Error],
        combinedStats: ScrapeResponse,
        successfulTrackers: Int,
        failedTrackers: Int
    ) {
        self.responses = responses
        self.errors = errors
        self.combinedStats = combinedStats
        self.successfulTrackers = successfulTrackers
        self.failedTrackers = failedTrackers
    }
} 