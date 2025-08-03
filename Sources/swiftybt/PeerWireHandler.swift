import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOPosix
import Logging

/// NIO channel handler for peer wire protocol
final class PeerWireHandler: ChannelInboundHandler, Sendable {
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
