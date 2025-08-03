import Foundation

/// Actor to manage peer state in a thread-safe manner
actor PeerState {
    var peerBitfield: [Bool]?
    var peerChoked = true
    var peerInterested = false
    
    func updateBitfield(_ bitfield: [Bool]?) {
        peerBitfield = bitfield
    }
    
    func setChoked(_ choked: Bool) {
        peerChoked = choked
    }
    
    func setInterested(_ interested: Bool) {
        peerInterested = interested
    }
    
    func getBitfield() -> [Bool]? {
        return peerBitfield
    }
    
    func isChoked() -> Bool {
        return peerChoked
    }
    
    func isInterested() -> Bool {
        return peerInterested
    }
}
