import Foundation
@preconcurrency import SwiftyBT
import Logging

@main
struct CLTSwiftyBT {
    static func main() async {
        // Configure logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .warning // Reduce log noise
            return handler
        }
        print("🌊 SwiftyBT CLI Tool v1.0")
        print("==========================")
        
        // Debug info hash
        // debugInfoHash() // Commented out for now
        
        // Parse command line arguments
        let arguments = CommandLine.arguments.dropFirst()
        
        guard !arguments.isEmpty else {
            printUsage()
            exit(1)
        }
        
        // Create downloads directory
        let downloadsDir = createDownloadsDirectory()
        
        // Process torrent files
        let torrentFiles = arguments.filter { $0.hasSuffix(".torrent") }
        
        guard !torrentFiles.isEmpty else {
            print("❌ Error: No .torrent files provided")
            print("Usage: clt-swiftybt <torrent-file1.torrent> [torrent-file2.torrent] ...")
            exit(1)
        }
        
        print("📁 Downloads directory: \(downloadsDir.path)")
        print("📦 Found \(torrentFiles.count) torrent file(s)")
        print()
        
        // Create torrent client
        let client = TorrentClient()
        var sessions: [TorrentSession] = []
        
        // Load all torrent files
        for torrentPath in torrentFiles {
            do {
                let url = URL(fileURLWithPath: torrentPath)
                let session = try client.loadTorrent(from: url)
                sessions.append(session)
                
                print("✅ Loaded: \(session.torrentFile.info.name)")
                print("   Size: \(formatBytes(session.torrentFile.getTotalSize()))")
                print("   Pieces: \(session.torrentFile.info.pieces.count)")
                print()
                
            } catch {
                print("❌ Failed to load \(torrentPath): \(error)")
            }
        }
        
        guard !sessions.isEmpty else {
            print("❌ No valid torrent files loaded")
            exit(1)
        }
        
        // Start downloading all torrents
        print("🚀 Starting downloads...")
        print()
        
        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                let sessionCopy = session
                let downloadsDirCopy = downloadsDir
                group.addTask {
                    await downloadTorrent(sessionCopy, to: downloadsDirCopy)
                }
            }
        }
        
        print("✅ All downloads completed!")
    }
    
    private static func createDownloadsDirectory() -> URL {
        let currentDir = FileManager.default.currentDirectoryPath
        let downloadsDir = URL(fileURLWithPath: currentDir).appendingPathComponent("torrent_downloads")
        
        do {
            try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create downloads directory: \(error)")
            exit(1)
        }
        
        return downloadsDir
    }
    
    private static func downloadTorrent(_ session: TorrentSession, to downloadsDir: URL) async {
        let torrentName = session.torrentFile.info.name
        let downloadPath = downloadsDir.appendingPathComponent(torrentName)
        
        print("📥 Starting: \(torrentName)")
        
        do {
            // Start the torrent
            try await session.start(downloadPath: downloadPath.path)
            
            // Monitor progress
            while session.getStatus().isRunning {
                let status = session.getStatus()
                displayProgress(torrentName, status: status)
                
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            // Final status
            let finalStatus = session.getStatus()
            displayProgress(torrentName, status: finalStatus)
            print() // Add newline after final progress
            
            if finalStatus.progress >= 1.0 {
                print("✅ Completed: \(torrentName)")
            } else {
                print("⚠️  Stopped: \(torrentName) (Progress: \(Int(finalStatus.progress * 100))%)")
            }
            
        } catch {
            print("❌ Error downloading \(torrentName): \(error)")
        }
    }
    
    private static var lastProgress = -1
    
    private static func displayProgress(_ name: String, status: TorrentStatus) {
        let progress = Int(status.progress * 100)
        
        // Only update if progress changed
        if progress != lastProgress {
            print("\(name) -> \(progress)%")
            lastProgress = progress
        }
    }
    
    private static func createProgressBar(_ percentage: Int) -> String {
        let width = 30
        let filled = Int(Double(width) * Double(percentage) / 100.0)
        let empty = width - filled
        
        let filledBar = String(repeating: "█", count: filled)
        let emptyBar = String(repeating: "░", count: empty)
        
        return "[\(filledBar)\(emptyBar)]"
    }
    
    private static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024.0 && unitIndex < units.count - 1 {
            size /= 1024.0
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", size, units[unitIndex])
    }
    
    private static func formatBytes(_ bytes: Int) -> String {
        return formatBytes(Int64(bytes))
    }
    
    private static func printUsage() {
        print("""
        Usage: clt-swiftybt <torrent-file1.torrent> [torrent-file2.torrent] ...
        
        Downloads torrent files to the 'torrent_downloads' directory.
        
        Examples:
          clt-swiftybt movie.torrent
          clt-swiftybt file1.torrent file2.torrent file3.torrent
        """)
    }
} 