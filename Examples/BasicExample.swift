import Foundation
import SwiftyBT
import Logging

// Configure logging
LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .info
    return handler
}

@main
struct BasicExample {
    static func main() async {
        print("SwiftyBT Basic Example")
        print("======================")
        
        // Create torrent client
        let client = TorrentClient()
        
        // Example: Parse a torrent file
        do {
            // This would be a real .torrent file path
            let torrentPath = "/path/to/example.torrent"
            let torrentURL = URL(fileURLWithPath: torrentPath)
            
            if FileManager.default.fileExists(atPath: torrentPath) {
                let session = try client.loadTorrent(from: torrentURL)
                
                print("Torrent loaded: \(session.torrentFile.info.name)")
                print("Total size: \(session.torrentFile.getTotalSize()) bytes")
                print("Pieces: \(session.torrentFile.info.pieces.count)")
                print("Info hash: \(session.infoHashHex)")
                
                // Get trackers
                let trackers = session.torrentFile.getAllTrackers()
                print("Trackers: \(trackers)")
                
                // Start the session (commented out for safety)
                // try await session.start(downloadPath: "/tmp/downloads")
                
                // Monitor status
                let status = session.getStatus()
                print("Status: \(status.name)")
                print("Progress: \(Int(status.progress * 100))%")
                print("Peers: \(status.peerCount)")
                
            } else {
                print("Torrent file not found at: \(torrentPath)")
                print("Please provide a valid .torrent file path")
            }
            
        } catch {
            print("Error: \(error)")
        }
        
        // Example: Tracker communication
        do {
            let trackerClient = TrackerClient()
            
            // Create example data
            let infoHash = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
            let peerId = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
            
            print("\nTesting tracker communication...")
            
            // Note: This would fail with a real tracker URL, but shows the API
            // let response = try await trackerClient.announce(
            //     url: "http://tracker.example.com:6881/announce",
            //     infoHash: infoHash,
            //     peerId: peerId,
            //     port: 6881,
            //     uploaded: 0,
            //     downloaded: 0,
            //     left: 1000000,
            //     event: .started
            // )
            
            print("Tracker communication API ready")
            
        } catch {
            print("Tracker error: \(error)")
        }
        
        // Example: Bencode parsing
        do {
            print("\nTesting bencode parser...")
            
            // Test bencode parsing
            let bencodeString = "d4:name5:teste"
            let value = try Bencode.parse(bencodeString)
            
            print("Parsed bencode: \(bencodeString)")
            
            // Test encoding
            let encoded = Bencode.encode(value)
            let encodedString = String(data: encoded, encoding: .utf8) ?? "invalid"
            print("Encoded: \(encodedString)")
            
        } catch {
            print("Bencode error: \(error)")
        }
        
        print("\nExample completed!")
    }
} 