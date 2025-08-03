import XCTest
@testable import SwiftyBT

final class UDPTrackersProviderTests: XCTestCase {
    
    func testGetAllUDPTrackers() {
        let trackers = UDPTrackersProvider.getAllUDPTrackers()
        
        XCTAssertFalse(trackers.isEmpty, "Should return non-empty list of trackers")
        XCTAssertGreaterThan(trackers.count, 10, "Should have more than 10 trackers")
        
        // Check that all trackers are UDP trackers
        for tracker in trackers {
            XCTAssertTrue(tracker.hasPrefix("udp://"), "All trackers should be UDP trackers")
            XCTAssertTrue(tracker.hasSuffix("/announce"), "All trackers should end with /announce")
        }
    }
    
    func testGetPrimaryUDPTrackers() {
        let trackers = UDPTrackersProvider.getPrimaryUDPTrackers()
        
        XCTAssertFalse(trackers.isEmpty, "Should return non-empty list of primary trackers")
        XCTAssertLessThanOrEqual(trackers.count, 20, "Primary trackers should be a reasonable number")
        
        // Check that all trackers are UDP trackers
        for tracker in trackers {
            XCTAssertTrue(tracker.hasPrefix("udp://"), "All primary trackers should be UDP trackers")
            XCTAssertTrue(tracker.hasSuffix("/announce"), "All primary trackers should end with /announce")
        }
    }
    
    func testGetBackupUDPTrackers() {
        let trackers = UDPTrackersProvider.getBackupUDPTrackers()
        
        XCTAssertFalse(trackers.isEmpty, "Should return non-empty list of backup trackers")
        
        // Check that all trackers are UDP trackers
        for tracker in trackers {
            XCTAssertTrue(tracker.hasPrefix("udp://"), "All backup trackers should be UDP trackers")
            XCTAssertTrue(tracker.hasSuffix("/announce"), "All backup trackers should end with /announce")
        }
    }
    
    func testGetExtendedUDPTrackers() {
        let trackers = UDPTrackersProvider.getExtendedUDPTrackers()
        
        XCTAssertFalse(trackers.isEmpty, "Should return non-empty list of extended trackers")
        
        // Check that all trackers are UDP trackers
        for tracker in trackers {
            XCTAssertTrue(tracker.hasPrefix("udp://"), "All extended trackers should be UDP trackers")
            XCTAssertTrue(tracker.hasSuffix("/announce"), "All extended trackers should end with /announce")
        }
    }
    
    func testGetTrackersByCategory() {
        let allTrackers = UDPTrackersProvider.getTrackers(category: .all)
        let primaryTrackers = UDPTrackersProvider.getTrackers(category: .primary)
        let backupTrackers = UDPTrackersProvider.getTrackers(category: .backup)
        let extendedTrackers = UDPTrackersProvider.getTrackers(category: .extended)
        
        XCTAssertEqual(allTrackers.count, UDPTrackersProvider.getAllUDPTrackers().count)
        XCTAssertEqual(primaryTrackers.count, UDPTrackersProvider.getPrimaryUDPTrackers().count)
        XCTAssertEqual(backupTrackers.count, UDPTrackersProvider.getBackupUDPTrackers().count)
        XCTAssertEqual(extendedTrackers.count, UDPTrackersProvider.getExtendedUDPTrackers().count)
    }
    
    func testNoDuplicateTrackers() {
        let allTrackers = UDPTrackersProvider.getAllUDPTrackers()
        let uniqueTrackers = Set(allTrackers)
        
        XCTAssertEqual(allTrackers.count, uniqueTrackers.count, "Should not have duplicate trackers")
    }
    
    func testTrackerURLFormat() {
        let trackers = UDPTrackersProvider.getAllUDPTrackers()
        
        for tracker in trackers {
            // Check URL format: udp://host:port/announce
            let components = tracker.components(separatedBy: "://")
            XCTAssertEqual(components.count, 2, "Tracker should have protocol and host:port/announce")
            XCTAssertEqual(components[0], "udp", "Protocol should be udp")
            
            let hostPortAnnounce = components[1]
            let hostPortComponents = hostPortAnnounce.components(separatedBy: "/")
            XCTAssertEqual(hostPortComponents.count, 2, "Should have host:port and announce")
            XCTAssertEqual(hostPortComponents[1], "announce", "Should end with /announce")
            
            let hostPort = hostPortComponents[0]
            let hostPortParts = hostPort.components(separatedBy: ":")
            XCTAssertEqual(hostPortParts.count, 2, "Should have host and port")
            
            let port = hostPortParts[1]
            XCTAssertNotNil(UInt16(port), "Port should be a valid number")
        }
    }
} 