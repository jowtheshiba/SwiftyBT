import Foundation

/// Provider for UDP tracker servers
public class UDPTrackersProvider {
    
    /// Get all available UDP trackers
    /// - Returns: Array of UDP tracker URLs
    public static func getAllUDPTrackers() -> [String] {
        // Merge primary, backup, and extended lists; deduplicate while preserving order
        let combined = getPrimaryUDPTrackers() + getBackupUDPTrackers() + getExtendedUDPTrackers()
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(combined.count)
        for tracker in combined {
            guard tracker.hasPrefix("udp://"), tracker.hasSuffix("/announce") else { continue }
            if !seen.contains(tracker) {
                seen.insert(tracker)
                result.append(tracker)
            }
        }
        return result
    }
    
    /// Get primary UDP trackers (most reliable)
    /// - Returns: Array of primary UDP tracker URLs
    public static func getPrimaryUDPTrackers() -> [String] {
        return [
            "udp://tracker.opentrackr.org:1337/announce",
            "udp://open.demonii.com:1337/announce",
            "udp://open.tracker.cl:1337/announce",
            "udp://explodie.org:6969/announce",
            "udp://exodus.desync.com:6969/announce",
            "udp://opentracker.io:6969/announce",
            "udp://tracker.qu.ax:6969/announce",
            "udp://tracker2.dler.org:80/announce",
            "udp://tracker.dler.org:6969/announce",
            "udp://tracker.bittor.pw:1337/announce",
            "udp://public.tracker.vraphim.com:6969/announce",
            "udp://p4p.arenabg.com:1337/announce"
        ]
    }
    
    /// Get backup UDP trackers (secondary reliable)
    /// - Returns: Array of backup UDP tracker URLs
    public static func getBackupUDPTrackers() -> [String] {
        return [
            "udp://tracker.tryhackx.org:6969/announce",
            "udp://tracker.theoks.net:6969/announce",
            "udp://tracker.srv00.com:6969/announce",
            "udp://tracker.gmi.gd:6969/announce",
            "udp://tracker.fnix.net:6969/announce",
            "udp://tracker.filemail.com:6969/announce",
            "udp://retracker01-msk-virt.corbina.net:80/announce",
            "udp://open.free-tracker.ga:6969/announce",
            "udp://open.dstud.io:6969/announce",
            "udp://ns-1.x-fins.com:6969/announce",
            "udp://leet-tracker.moe:1337/announce",
            "udp://isk.richardsw.club:6969/announce",
            "udp://ipv4announce.sktorrent.eu:6969/announce",
            "udp://hificode.in:6969/announce",
            "udp://glotorrents.pw:6969/announce",
            "udp://evan.im:6969/announce",
            "udp://discord.heihachi.pw:6969/announce",
            "udp://bittorrent-tracker.e-n-c-r-y-p-t.net:1337/announce",
            "udp://bandito.byterunner.io:6969/announce"
        ]
    }
    
    /// Get extended UDP trackers (additional options)
    /// - Returns: Array of extended UDP tracker URLs
    public static func getExtendedUDPTrackers() -> [String] {
        return [
            "udp://tracker.opentrackr.org:1337/announce",
            "udp://open.demonii.com:1337/announce",
            "udp://open.tracker.cl:1337/announce",
            "udp://explodie.org:6969/announce",
            "udp://exodus.desync.com:6969/announce",
            "udp://opentracker.io:6969/announce",
            "udp://tracker.qu.ax:6969/announce",
            "udp://tracker2.dler.org:80/announce",
            "udp://tracker.dler.org:6969/announce",
            "udp://tracker.bittor.pw:1337/announce",
            "udp://public.tracker.vraphim.com:6969/announce",
            "udp://p4p.arenabg.com:1337/announce"
        ]
    }
    
    /// Get trackers by category
    /// - Parameter category: Tracker category
    /// - Returns: Array of tracker URLs for the specified category
    public static func getTrackers(category: TrackerCategory) -> [String] {
        switch category {
        case .all:
            return getAllUDPTrackers()
        case .primary:
            return getPrimaryUDPTrackers()
        case .backup:
            return getBackupUDPTrackers()
        case .extended:
            return getExtendedUDPTrackers()
        }
    }
    
    /// Tracker categories
    public enum TrackerCategory {
        case all
        case primary
        case backup
        case extended
    }
}

// MARK: - Legacy Support
extension UDPTrackersProvider {
    /// Legacy method for backward compatibility
    /// - Returns: Array of UDP tracker URLs (same as getAllUDPTrackers)
    @available(*, deprecated, message: "Use getAllUDPTrackers() instead")
    public static func getUDPTrackers() -> [String] {
        return getAllUDPTrackers()
    }
} 