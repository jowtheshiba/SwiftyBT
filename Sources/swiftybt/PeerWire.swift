import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOPosix
import Logging

/// BitTorrent peer wire protocol client
public class PeerWireClient {
    private let eventLoopGroup: EventLoopGroup
    private let logger: Logger
    
    public init(eventLoopGroup: EventLoopGroup? = nil) {
        self.eventLoopGroup = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.logger = Logger(label: "SwiftyBT.PeerWire")
    }
    
    deinit {
        if eventLoopGroup is MultiThreadedEventLoopGroup {
            try? eventLoopGroup.syncShutdownGracefully()
        }
    }
    
    /// Connect to a peer and perform handshake
    /// - Parameters:
    ///   - address: Peer address
    ///   - port: Peer port
    ///   - infoHash: Torrent info hash
    ///   - peerId: Our peer ID
    /// - Returns: Peer connection if handshake successful
    /// - Throws: PeerWireError if connection or handshake fails
    public func connect(
        to address: String,
        port: UInt16,
        infoHash: Data,
        peerId: Data
    ) async throws -> PeerConnection {
        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(PeerWireHandler(infoHash: infoHash, peerId: peerId))
            }
        
        let channel = try await bootstrap.connect(host: address, port: Int(port)).get()
        let handler = try await channel.pipeline.handler(type: PeerWireHandler.self).get()
        
        return PeerConnection(channel: channel, handler: handler)
    }
}

/// Peer connection for wire protocol communication
public class PeerConnection {
    private let channel: Channel
    private let handler: PeerWireHandler
    private let logger: Logger
    private var pieceCallback: ((UInt32, UInt32, Data) -> Void)?
    
    fileprivate init(channel: Channel, handler: PeerWireHandler) {
        self.channel = channel
        self.handler = handler
        self.logger = Logger(label: "SwiftyBT.PeerConnection")
    }
    
    /// Set callback for piece messages
    public func setPieceCallback(_ callback: @escaping (UInt32, UInt32, Data) -> Void) {
        pieceCallback = callback
        handler.setPieceCallback(callback)
    }
    
    /// Get piece callback
    public func getPieceCallback() -> ((UInt32, UInt32, Data) -> Void)? {
        return pieceCallback
    }
    
    /// Send interested message
    public func sendInterested() async throws {
        try await sendMessage(.interested)
    }
    
    /// Send not interested message
    public func sendNotInterested() async throws {
        try await sendMessage(.notInterested)
    }
    
    /// Send choke message
    public func sendChoke() async throws {
        try await sendMessage(.choke)
    }
    
    /// Send unchoke message
    public func sendUnchoke() async throws {
        try await sendMessage(.unchoke)
    }
    
    /// Send have message
    /// - Parameter pieceIndex: Index of the piece we have
    public func sendHave(pieceIndex: UInt32) async throws {
        try await sendMessage(.have(pieceIndex))
    }
    
    /// Send bitfield message
    /// - Parameter bitfield: Bitfield representing pieces we have
    public func sendBitfield(_ bitfield: [Bool]) async throws {
        try await sendMessage(.bitfield(bitfield))
    }
    
    /// Send request message
    /// - Parameters:
    ///   - pieceIndex: Index of the piece to request
    ///   - offset: Offset within the piece
    ///   - length: Length of the block to request
    public func sendRequest(pieceIndex: UInt32, offset: UInt32, length: UInt32) async throws {
        try await sendMessage(.request(pieceIndex, offset, length))
    }
    
    /// Send piece message
    /// - Parameters:
    ///   - pieceIndex: Index of the piece
    ///   - offset: Offset within the piece
    ///   - data: Piece data
    public func sendPiece(pieceIndex: UInt32, offset: UInt32, data: Data) async throws {
        try await sendMessage(.piece(pieceIndex, offset, data))
    }
    
    /// Send cancel message
    /// - Parameters:
    ///   - pieceIndex: Index of the piece to cancel
    ///   - offset: Offset within the piece
    ///   - length: Length of the block to cancel
    public func sendCancel(pieceIndex: UInt32, offset: UInt32, length: UInt32) async throws {
        try await sendMessage(.cancel(pieceIndex, offset, length))
    }
    
    /// Send port message (for DHT)
    /// - Parameter port: Port number
    public func sendPort(port: UInt16) async throws {
        try await sendMessage(.port(port))
    }
    
    /// Close the connection
    public func close() async throws {
        try await channel.close()
    }
    
    /// Get peer's bitfield
    /// - Returns: Bitfield representing pieces the peer has
    public func getPeerBitfield() async -> [Bool]? {
        return await handler.peerState.getBitfield()
    }
    
    /// Check if peer is choked
    /// - Returns: True if peer is choked
    public func isPeerChoked() async -> Bool {
        return await handler.peerState.isChoked()
    }
    
    /// Check if peer is interested
    /// - Returns: True if peer is interested
    public func isPeerInterested() async -> Bool {
        return await handler.peerState.isInterested()
    }
    
    private func sendMessage(_ message: PeerWireMessage) async throws {
        let data = message.encode()
        let buffer = channel.allocator.buffer(bytes: data)
        try await channel.writeAndFlush(buffer)
    }
}

/// Peer wire protocol message types
public enum PeerWireMessage {
    case choke
    case unchoke
    case interested
    case notInterested
    case have(UInt32)
    case bitfield([Bool])
    case request(UInt32, UInt32, UInt32) // piece index, offset, length
    case piece(UInt32, UInt32, Data) // piece index, offset, data
    case cancel(UInt32, UInt32, UInt32) // piece index, offset, length
    case port(UInt16)
    
    /// Message ID
    var id: UInt8 {
        switch self {
        case .choke: return 0
        case .unchoke: return 1
        case .interested: return 2
        case .notInterested: return 3
        case .have: return 4
        case .bitfield: return 5
        case .request: return 6
        case .piece: return 7
        case .cancel: return 8
        case .port: return 9
        }
    }
    
    /// Encode message to data
    func encode() -> Data {
        var data = Data()
        
        switch self {
        case .choke, .unchoke, .interested, .notInterested:
            // Message with no payload
            data.append(contentsOf: [0, 0, 0, 1, id])
            
        case .have(let pieceIndex):
            // 4-byte piece index
            data.append(contentsOf: [0, 0, 0, 5, id])
            data.append(contentsOf: withUnsafeBytes(of: pieceIndex.bigEndian) { Data($0) })
            
        case .bitfield(let bitfield):
            // Variable length bitfield
            let bytes = bitfieldToBytes(bitfield)
            let length = UInt32(bytes.count + 1).bigEndian
            data.append(contentsOf: withUnsafeBytes(of: length) { Data($0) })
            data.append(id)
            data.append(contentsOf: bytes)
            
        case .request(let pieceIndex, let offset, let length):
            // 12-byte payload: piece index, offset, length
            data.append(contentsOf: [0, 0, 0, 13, id])
            data.append(contentsOf: withUnsafeBytes(of: pieceIndex.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: offset.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Data($0) })
            
        case .piece(let pieceIndex, let offset, let pieceData):
            // Variable length: piece index, offset, data
            let payloadLength = 8 + pieceData.count
            let length = UInt32(payloadLength + 1).bigEndian
            data.append(contentsOf: withUnsafeBytes(of: length) { Data($0) })
            data.append(id)
            data.append(contentsOf: withUnsafeBytes(of: pieceIndex.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: offset.bigEndian) { Data($0) })
            data.append(contentsOf: pieceData)
            
        case .cancel(let pieceIndex, let offset, let length):
            // 12-byte payload: piece index, offset, length
            data.append(contentsOf: [0, 0, 0, 13, id])
            data.append(contentsOf: withUnsafeBytes(of: pieceIndex.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: offset.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Data($0) })
            
        case .port(let port):
            // 2-byte port
            data.append(contentsOf: [0, 0, 0, 3, id])
            data.append(contentsOf: withUnsafeBytes(of: port.bigEndian) { Data($0) })
        }
        
        return data
    }
    
    private func bitfieldToBytes(_ bitfield: [Bool]) -> Data {
        var bytes = Data()
        var currentByte: UInt8 = 0
        var bitCount = 0
        
        for bit in bitfield {
            if bit {
                currentByte |= (1 << (7 - bitCount))
            }
            
            bitCount += 1
            
            if bitCount == 8 {
                bytes.append(currentByte)
                currentByte = 0
                bitCount = 0
            }
        }
        
        // Add remaining bits if any
        if bitCount > 0 {
            bytes.append(currentByte)
        }
        
        return bytes
    }
}

/// Peer wire protocol errors
public enum PeerWireError: Error {
    case handshakeFailed
    case invalidMessage
    case connectionClosed
    case timeout
    case invalidPeerId
    case invalidInfoHash
}
