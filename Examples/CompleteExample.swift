import Foundation
import SwiftyBT
import NIOPosix
import Logging
import CryptoKit

/// Complete example demonstrating SwiftyBT with real torrent usage
@main
struct CompleteExample {
    static func main() async {
        // Configure logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }
        
        let logger = Logger(label: "CompleteExample")
        logger.info("🚀 Starting SwiftyBT Complete Example")
        
        // Create event loop group
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 4)
        defer {
            try? eventLoopGroup.syncShutdownGracefully()
        }
        
        // Initialize BitTorrent client with all features enabled
        let client = TorrentClient(
            eventLoopGroup: eventLoopGroup,
            enableDHT: true,
            enablePEX: true
        )
        
        // Example torrent URLs (replace with real torrents)
        let torrentURLs = [
            // Popular Linux distributions (good for testing)
            "https://releases.ubuntu.com/22.04.3/ubuntu-22.04.3-desktop-amd64.iso.torrent",
            "https://download.fedoraproject.org/pub/fedora/linux/releases/38/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-38-1.6.torrent",
            
            // Open source software
            "https://www.blender.org/download/previous-versions/",
            
            // Public domain content
            "https://archive.org/download/",
        ]
        
        logger.info("📋 Available torrent examples:")
        for (index, url) in torrentURLs.enumerated() {
            logger.info("  \(index + 1). \(url)")
        }
        
        // For demonstration, we'll create a simple test torrent
        logger.info("🎯 Creating test torrent for demonstration...")
        
        do {
            // Create a test torrent file
            let testTorrentPath = try createTestTorrent()
            logger.info("✅ Created test torrent at: \(testTorrentPath)")
            
            // Load the torrent
            let session = try client.loadTorrent(from: URL(fileURLWithPath: testTorrentPath))
            logger.info("📦 Loaded torrent: \(session.torrentFile.info.name)")
            
            // Set download path
            let downloadPath = FileManager.default.currentDirectoryPath + "/downloads"
            logger.info("📁 Download path: \(downloadPath)")
            
            // Start the torrent session
            logger.info("▶️ Starting torrent session...")
            try await session.start(downloadPath: downloadPath)
            
            // Monitor progress
            await monitorProgress(session: session)
            
        } catch {
            logger.error("❌ Error: \(error)")
        }
    }
    
    /// Create a test torrent file for demonstration
    private static func createTestTorrent() throws -> String {
        let testContent = "This is a test file for SwiftyBT demonstration.\n" +
                         "It contains some sample data to demonstrate the BitTorrent protocol.\n" +
                         "In real usage, you would use actual torrent files from trackers.\n"
        
        let testFilePath = FileManager.default.currentDirectoryPath + "/test_file.txt"
        try testContent.write(toFile: testFilePath, atomically: true, encoding: .utf8)
        
        // Create a simple torrent file (this is a simplified version)
        let torrentContent = """
        d8:announce35:udp://tracker.opentrackr.org:1337/announce13:creation datei1703123456e4:infod6:lengthi\(testContent.count)e4:name13:test_file.txt12:piece lengthi16384e6:pieces20:\(SHA1_hash(data: testContent.data(using: .utf8)!).base64EncodedString())ee
        """
        
        let torrentPath = FileManager.default.currentDirectoryPath + "/test.torrent"
        try torrentContent.write(toFile: torrentPath, atomically: true, encoding: .utf8)
        
        return torrentPath
    }
    
    /// Simple SHA1 hash function (for demonstration)
    private static func SHA1_hash(data: Data) -> Data {
        // In a real implementation, use a proper SHA1 library
        let hash = CryptoKit.SHA256.hash(data: data)
        return Data(hash.prefix(20))
    }
    
    /// Monitor torrent progress
    private static func monitorProgress(session: TorrentSession) async {
        let logger = Logger(label: "ProgressMonitor")
        
        logger.info("📊 Starting progress monitoring...")
        
        var lastProgress = 0.0
        var lastTime = Date()
        
        while session.getStatus().isRunning {
            let status = session.getStatus()
            let currentTime = Date()
            let timeDiff = currentTime.timeIntervalSince(lastTime)
            
            // Calculate speeds
            let downloadSpeed = timeDiff > 0 ? Double(status.downloadSpeed) / timeDiff : 0
            let uploadSpeed = timeDiff > 0 ? Double(status.uploadSpeed) / timeDiff : 0
            
            // Format speeds
            let downloadSpeedStr = formatSpeed(downloadSpeed)
            let uploadSpeedStr = formatSpeed(uploadSpeed)
            
            // Progress bar
            let progressBar = createProgressBar(progress: status.progress)
            
            // Clear line and print status
            print("\r📦 \(status.name)")
            print("   Progress: \(progressBar) \(Int(status.progress * 100))%")
            print("   Downloaded: \(formatBytes(status.downloadedBytes)) / \(formatBytes(Int64(status.totalSize)))")
            print("   Speed: ↓ \(downloadSpeedStr) ↑ \(uploadSpeedStr)")
            print("   Peers: \(status.peerCount)")
            print("   ETA: \(calculateETA(status: status, downloadSpeed: downloadSpeed))")
            
            lastProgress = status.progress
            lastTime = currentTime
            
            // Check if download is complete
            if status.progress >= 1.0 {
                logger.info("✅ Download completed!")
                break
            }
            
            // Wait before next update
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        logger.info("🏁 Progress monitoring finished")
    }
    
    /// Create a visual progress bar
    private static func createProgressBar(progress: Double) -> String {
        let width = 30
        let filled = Int(progress * Double(width))
        let empty = width - filled
        
        let filledBar = String(repeating: "█", count: filled)
        let emptyBar = String(repeating: "░", count: empty)
        
        return filledBar + emptyBar
    }
    
    /// Format bytes to human readable format
    private static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", size, units[unitIndex])
    }
    
    /// Format speed to human readable format
    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        return formatBytes(Int64(bytesPerSecond)) + "/s"
    }
    
    /// Calculate estimated time to completion
    private static func calculateETA(status: TorrentStatus, downloadSpeed: Double) -> String {
        guard downloadSpeed > 0 else { return "∞" }
        
        let remainingBytes = status.leftBytes
        let seconds = Double(remainingBytes) / downloadSpeed
        
        if seconds.isInfinite || seconds.isNaN {
            return "∞"
        }
        
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}

/// Real-world usage examples
extension CompleteExample {
    
    /// Example: Download a popular Linux distribution
    static func downloadLinuxDistribution() async {
        let logger = Logger(label: "LinuxDownload")
        
        // Example torrent URLs for Linux distributions
        let linuxTorrents = [
            "https://releases.ubuntu.com/22.04.3/ubuntu-22.04.3-desktop-amd64.iso.torrent",
            "https://download.fedoraproject.org/pub/fedora/linux/releases/38/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-38-1.6.torrent",
            "https://download.opensuse.org/distribution/leap/15.5/iso/openSUSE-Leap-15.5-DVD-x86_64.iso.torrent"
        ]
        
        logger.info("🐧 Available Linux distributions:")
        for (index, url) in linuxTorrents.enumerated() {
            logger.info("  \(index + 1). \(url)")
        }
        
        // In a real application, you would:
        // 1. Download the .torrent file
        // 2. Parse it with TorrentFile.parse()
        // 3. Start the download
    }
    
    /// Example: Download open source software
    static func downloadOpenSourceSoftware() async {
        let logger = Logger(label: "OpenSourceDownload")
        
        // Example software torrents
        let softwareTorrents = [
            "https://www.blender.org/download/previous-versions/",
            "https://www.gimp.org/downloads/",
            "https://www.audacityteam.org/download/"
        ]
        
        logger.info("🔧 Available open source software:")
        for (index, url) in softwareTorrents.enumerated() {
            logger.info("  \(index + 1). \(url)")
        }
    }
    
    /// Example: Download public domain content
    static func downloadPublicDomainContent() async {
        let logger = Logger(label: "PublicDomainDownload")
        
        // Example public domain content
        let publicDomainTorrents = [
            "https://archive.org/download/",
            "https://www.gutenberg.org/",
            "https://commons.wikimedia.org/"
        ]
        
        logger.info("📚 Available public domain content:")
        for (index, url) in publicDomainTorrents.enumerated() {
            logger.info("  \(index + 1). \(url)")
        }
    }
    
    /// Example: Advanced usage with multiple torrents
    static func advancedUsage() async {
        let logger = Logger(label: "AdvancedUsage")
        
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 4)
        defer { try? eventLoopGroup.syncShutdownGracefully() }
        
        let client = TorrentClient(
            eventLoopGroup: eventLoopGroup,
            enableDHT: true,
            enablePEX: true
        )
        
        // Example: Download multiple torrents simultaneously
        let torrentPaths = [
            "/path/to/torrent1.torrent",
            "/path/to/torrent2.torrent",
            "/path/to/torrent3.torrent"
        ]
        
        var sessions: [TorrentSession] = []
        
        // Load all torrents
        for path in torrentPaths {
            do {
                let session = try client.loadTorrent(from: URL(fileURLWithPath: path))
                sessions.append(session)
                logger.info("📦 Loaded torrent: \(session.torrentFile.info.name)")
            } catch {
                logger.error("❌ Failed to load torrent \(path): \(error)")
            }
        }
        
        // Start all sessions
        for session in sessions {
            do {
                try await session.start(downloadPath: "/downloads")
                logger.info("▶️ Started session for: \(session.torrentFile.info.name)")
            } catch {
                logger.error("❌ Failed to start session: \(error)")
            }
        }
        
        // Monitor all sessions
        await monitorMultipleSessions(sessions: sessions)
    }
    
    /// Monitor multiple torrent sessions
    private static func monitorMultipleSessions(sessions: [TorrentSession]) async {
        let logger = Logger(label: "MultiSessionMonitor")
        
        logger.info("📊 Monitoring \(sessions.count) torrent sessions...")
        
        while sessions.contains(where: { $0.getStatus().isRunning }) {
            print("\n" + String(repeating: "=", count: 80))
            
            for (index, session) in sessions.enumerated() {
                let status = session.getStatus()
                let progressBar = createProgressBar(progress: status.progress)
                
                print("📦 [\(index + 1)] \(status.name)")
                print("   Progress: \(progressBar) \(Int(status.progress * 100))%")
                print("   Speed: ↓ \(formatSpeed(Double(status.downloadSpeed))) ↑ \(formatSpeed(Double(status.uploadSpeed)))")
                print("   Peers: \(status.peerCount)")
                
                if status.progress >= 1.0 {
                    print("   ✅ COMPLETED")
                }
            }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
        
        logger.info("🏁 All downloads completed!")
    }
} 