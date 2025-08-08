import Foundation

enum MagnetError: Error, LocalizedError {
    case invalidMagnetURL(String)
    case missingInfoHash(String)
    case invalidInfoHash(String)
    case invalidTrackerURL(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidMagnetURL(let message):
            return "Invalid magnet URL: \(message)"
        case .missingInfoHash(let message):
            return "Missing info hash: \(message)"
        case .invalidInfoHash(let message):
            return "Invalid info hash: \(message)"
        case .invalidTrackerURL(let message):
            return "Invalid tracker URL: \(message)"
        }
    }
}
