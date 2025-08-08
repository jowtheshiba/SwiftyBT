import Foundation

enum TrackerType {
    case udp
    case http
    case https
}

struct TorrentURLTracker: Hashable {
    let trackerURL: String
    let trackerType: TrackerType
}
