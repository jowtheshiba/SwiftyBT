import Foundation

/// Provider for UDP tracker servers
public class UDPTrackersProvider {
    
    /// Get all available UDP trackers
    /// - Returns: Array of UDP tracker URLs
    public static func getAllUDPTrackers() -> [String] {
        return [
            // Most reliable trackers (mix of HTTP and UDP)
            "http://tracker.opentrackr.org:1337/announce",
            "http://open.demonii.com:1337/announce",
            "http://open.tracker.cl:1337/announce",
            "http://open.stealth.si:80/announce",
            
            // Popular working trackers
            "http://explodie.org:6969/announce",
            "http://exodus.desync.com:6969/announce",
            "http://opentracker.io:6969/announce",
            "http://tracker.qu.ax:6969/announce",
            "http://tracker2.dler.org:80/announce",
            "http://tracker.dler.org:6969/announce",
            "http://tracker.bittor.pw:1337/announce",
            "http://public.tracker.vraphim.com:6969/announce",
            "http://p4p.arenabg.com:1337/announce",
            
            // Additional reliable trackers
            "http://tracker.tryhackx.org:6969/announce",
            "http://tracker.theoks.net:6969/announce",
            "http://tracker.srv00.com:6969/announce",
            "http://tracker.gmi.gd:6969/announce",
            "http://tracker.fnix.net:6969/announce",
            "http://tracker.filemail.com:6969/announce",
            "http://retracker01-msk-virt.corbina.net:80/announce",
            "http://open.free-tracker.ga:6969/announce",
            "http://open.dstud.io:6969/announce",
            "http://ns-1.x-fins.com:6969/announce",
            "http://leet-tracker.moe:1337/announce",
            "http://isk.richardsw.club:6969/announce",
            "http://ipv4announce.sktorrent.eu:6969/announce",
            "http://hificode.in:6969/announce",
            "http://glotorrents.pw:6969/announce",
            "http://evan.im:6969/announce",
            "http://discord.heihachi.pw:6969/announce",
            "http://bittorrent-tracker.e-n-c-r-y-p-t.net:1337/announce",
            "http://bandito.byterunner.io:6969/announce",
            
            // UDP trackers (fewer, more reliable ones)
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
    
    /// Get primary UDP trackers (most reliable)
    /// - Returns: Array of primary UDP tracker URLs
    public static func getPrimaryUDPTrackers() -> [String] {
        return [
            "http://tracker.opentrackr.org:1337/announce",
            "http://open.demonii.com:1337/announce",
            "http://open.tracker.cl:1337/announce",
            "http://explodie.org:6969/announce",
            "http://exodus.desync.com:6969/announce",
            "http://opentracker.io:6969/announce",
            "http://tracker.qu.ax:6969/announce",
            "http://tracker2.dler.org:80/announce",
            "http://tracker.dler.org:6969/announce",
            "http://tracker.bittor.pw:1337/announce",
            "http://public.tracker.vraphim.com:6969/announce",
            "http://p4p.arenabg.com:1337/announce"
        ]
    }
    
    /// Get backup UDP trackers (secondary reliable)
    /// - Returns: Array of backup UDP tracker URLs
    public static func getBackupUDPTrackers() -> [String] {
        return [
            "http://tracker.tryhackx.org:6969/announce",
            "http://tracker.theoks.net:6969/announce",
            "http://tracker.srv00.com:6969/announce",
            "http://tracker.gmi.gd:6969/announce",
            "http://tracker.fnix.net:6969/announce",
            "http://tracker.filemail.com:6969/announce",
            "http://retracker01-msk-virt.corbina.net:80/announce",
            "http://open.free-tracker.ga:6969/announce",
            "http://open.dstud.io:6969/announce",
            "http://ns-1.x-fins.com:6969/announce",
            "http://leet-tracker.moe:1337/announce",
            "http://isk.richardsw.club:6969/announce",
            "http://ipv4announce.sktorrent.eu:6969/announce",
            "http://hificode.in:6969/announce",
            "http://glotorrents.pw:6969/announce",
            "http://evan.im:6969/announce",
            "http://discord.heihachi.pw:6969/announce",
            "http://bittorrent-tracker.e-n-c-r-y-p-t.net:1337/announce",
            "http://bandito.byterunner.io:6969/announce"
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