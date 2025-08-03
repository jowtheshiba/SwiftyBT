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

/// Actor to manage peer state in a thread-safe manner
private actor PeerState {
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

/// NIO channel handler for peer wire protocol
private final class PeerWireHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    private let infoHash: Data
    private let peerId: Data
    private let logger: Logger
    let peerState: PeerState
    private var pieceCallback: ((UInt32, UInt32, Data) -> Void)?
    
    init(infoHash: Data, peerId: Data) {
        self.infoHash = infoHash
        self.peerId = peerId
        self.logger = Logger(label: "SwiftyBT.PeerWireHandler")
        self.peerState = PeerState()
    }
    
    func setPieceCallback(_ callback: @escaping (UInt32, UInt32, Data) -> Void) {
        pieceCallback = callback
    }
    
    func channelActive(context: ChannelHandlerContext) {
        logger.info("Channel active, sending handshake to \(context.channel.remoteAddress?.description ?? "unknown")")
        sendHandshake(context: context)
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        
        // Handle handshake first
        if buffer.readableBytes >= 68 {
            let handshakeData = Data(buffer.readableBytesView.prefix(68))
            if handleHandshake(handshakeData) {
                logger.info("Handshake successful")
                return
            }
        }
        
        // Handle regular messages
        while buffer.readableBytes >= 4 {
            let length = buffer.getInteger(at: buffer.readerIndex, as: UInt32.self)!
            let messageLength = Int(length.bigEndian)
            
            if buffer.readableBytes < messageLength + 4 {
                break
            }
            
            buffer.moveReaderIndex(forwardBy: 4)
            
            if messageLength == 0 {
                // Keep-alive message
                continue
            }
            
            let messageId = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self)!
            buffer.moveReaderIndex(forwardBy: 1)
            
            let payload = Data(buffer.readableBytesView.prefix(messageLength - 1))
            handleMessage(id: messageId, payload: payload)
        }
    }
    
    private func sendHandshake(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: 68)
        
        // Protocol string (19 bytes)
        buffer.writeString("BitTorrent protocol")
        
        // Reserved bytes (8 bytes)
        buffer.writeBytes([0, 0, 0, 0, 0, 0, 0, 0])
        
        // Info hash (20 bytes)
        buffer.writeBytes(infoHash)
        
        // Peer ID (20 bytes)
        buffer.writeBytes(peerId)
        
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }
    
    private func handleHandshake(_ data: Data) -> Bool {
        guard data.count == 68 else { 
            logger.error("Handshake failed: invalid data length \(data.count)")
            return false 
        }
        
        // Check protocol string
        let protocolString = String(data: data[0..<19], encoding: .ascii)
        guard protocolString == "BitTorrent protocol" else { 
            logger.error("Handshake failed: invalid protocol string '\(protocolString ?? "nil")'")
            return false 
        }
        
        // Extract info hash and peer ID
        let receivedInfoHash = data[28..<48]
        let receivedPeerId = data[48..<68]
        
        // Verify info hash
        guard receivedInfoHash == infoHash else {
            logger.error("Handshake failed: info hash mismatch")
            logger.error("Expected: \(infoHash.map { String(format: "%02x", $0) }.joined())")
            logger.error("Received: \(receivedInfoHash.map { String(format: "%02x", $0) }.joined())")
            return false
        }
        
        logger.info("Handshake successful with peer: \(receivedPeerId.map { String(format: "%02x", $0) }.joined())")
        return true
    }
    
    private func handleMessage(id: UInt8, payload: Data) {
        Task {
            switch id {
            case 0: // choke
                await peerState.setChoked(true)
                logger.debug("Peer choked")
                
            case 1: // unchoke
                await peerState.setChoked(false)
                logger.info("🎉 Peer unchoked!")
                
            case 2: // interested
                await peerState.setInterested(true)
                logger.debug("Peer interested")
                
            case 3: // not interested
                await peerState.setInterested(false)
                logger.debug("Peer not interested")
                
            case 4: // have
                if payload.count == 4 {
                    let pieceIndex = payload.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                    logger.debug("Peer has piece: \(pieceIndex)")
                }
                
            case 5: // bitfield
                let bitfield = bytesToBitfield(payload)
                await peerState.updateBitfield(bitfield)
                logger.info("📋 Received bitfield with \(bitfield.count) pieces")
            
        case 6: // request
            if payload.count == 12 {
                let pieceIndex = payload[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let offset = payload[4..<8].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let length = payload[8..<12].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                logger.debug("Peer requested piece: \(pieceIndex), offset: \(offset), length: \(length)")
            }
            
        case 7: // piece
            if payload.count >= 8 {
                let pieceIndex = payload[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let offset = payload[4..<8].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let data = payload[8...]
                logger.info("📦 Received piece: \(pieceIndex), offset: \(offset), data size: \(data.count)")
                
                // Call piece callback if set
                if let callback = pieceCallback {
                    logger.info("🎯 Calling piece callback")
                    callback(pieceIndex, offset, data)
                } else {
                    logger.warning("⚠️ No piece callback set")
                }
            }
            
        case 8: // cancel
            if payload.count == 12 {
                let pieceIndex = payload[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let offset = payload[4..<8].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let length = payload[8..<12].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                logger.debug("Peer cancelled piece: \(pieceIndex), offset: \(offset), length: \(length)")
            }
            
        case 9: // port
            if payload.count == 2 {
                let port = payload.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
                logger.debug("Peer port: \(port)")
            }
            
        default:
            logger.warning("Unknown message ID: \(id)")
        }
        }
    }
    
    private func bytesToBitfield(_ bytes: Data) -> [Bool] {
        var bitfield: [Bool] = []
        
        for byte in bytes {
            for i in 0..<8 {
                bitfield.append((byte & (1 << (7 - i))) != 0)
            }
        }
        
        return bitfield
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("Channel error: \(error)")
        context.close(promise: nil)
    }
} 
