import Foundation
import SwiftyBT

/// Example demonstrating UDPTrackersProvider usage
struct UDPTrackersExample {
    
    static func main() async {
        print("🔍 UDP Trackers Provider Example")
        print("=================================")
        
        // Get all UDP trackers
        let allTrackers = UDPTrackersProvider.getAllUDPTrackers()
        print("📊 Total UDP trackers: \(allTrackers.count)")
        
        // Get primary trackers
        let primaryTrackers = UDPTrackersProvider.getPrimaryUDPTrackers()
        print("⭐ Primary UDP trackers: \(primaryTrackers.count)")
        
        // Get backup trackers
        let backupTrackers = UDPTrackersProvider.getBackupUDPTrackers()
        print("🔄 Backup UDP trackers: \(backupTrackers.count)")
        
        // Get extended trackers
        let extendedTrackers = UDPTrackersProvider.getExtendedUDPTrackers()
        print("🔗 Extended UDP trackers: \(extendedTrackers.count)")
        
        // Get trackers by category
        let categoryTrackers = UDPTrackersProvider.getTrackers(category: .primary)
        print("📋 Primary trackers by category: \(categoryTrackers.count)")
        
        print("\n📝 Sample trackers:")
        print("===================")
        
        // Show first 5 primary trackers
        for (index, tracker) in primaryTrackers.prefix(5).enumerated() {
            print("\(index + 1). \(tracker)")
        }
        
        print("\n✅ UDPTrackersProvider is ready to use!")
    }
} 