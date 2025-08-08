import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOPosix
import Logging

/// NIO channel handler for peer wire protocol
final class PeerWireHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    private let infoHash: Data
    private let peerId: Data
    private let logger: Logger
    let peerState: PeerState
    private var pieceCallback: ((UInt32, UInt32, Data) -> Void)?
    private var handshakeCompleted = false
    private var messageBuffer = ByteBuffer() // Buffer for incomplete messages
    
    init(infoHash: Data, peerId: Data) {
        self.infoHash = infoHash
        self.peerId = peerId
        self.logger = Logger(label: "SwiftyBT.PeerWireHandler")
        self.peerState = PeerState()
        self.messageBuffer = ByteBuffer()
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
        logger.info("📥 Received data: \(buffer.readableBytes) bytes, handshake completed: \(handshakeCompleted)")

        // Add new data to our message buffer
        messageBuffer.writeBuffer(&buffer)
        
        // Handle handshake first (consume it and continue with remaining bytes)
        if !handshakeCompleted, messageBuffer.readableBytes >= 68 {
            let handshakeSlice = messageBuffer.readableBytesView.prefix(68)
            let handshakeData = Data(handshakeSlice)
            if handleHandshake(handshakeData) {
                handshakeCompleted = true
                logger.info("Handshake successful")
                messageBuffer.moveReaderIndex(forwardBy: 68)
            } else {
                context.close(promise: nil)
                return
            }
        }
        
        // Handle regular messages only after handshake
        if handshakeCompleted {
            processMessages()
        }
    }
    
    private func processMessages() {
        logger.info("📖 Processing messages from buffer: \(messageBuffer.readableBytes) bytes available")
        
        // Debug: show first few bytes of buffer
        if messageBuffer.readableBytes > 0 {
            let debugBytes = messageBuffer.getBytes(at: messageBuffer.readerIndex, length: min(16, messageBuffer.readableBytes)) ?? []
            let hexString = debugBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            logger.info("🔍 First bytes: \(hexString)")
        }
        
        while messageBuffer.readableBytes >= 4 {
            guard let length: UInt32 = messageBuffer.getInteger(at: messageBuffer.readerIndex, endianness: .big, as: UInt32.self) else { break }
            let messageLength = Int(length)

            logger.info("📏 Message length: \(messageLength), buffer has: \(messageBuffer.readableBytes) bytes")

            // Check if we have complete message
            if messageBuffer.readableBytes < messageLength + 4 {
                logger.info("⏳ Incomplete message (need \(messageLength + 4), have \(messageBuffer.readableBytes)), waiting for more data")
                break
            }

            // consume length (big endian)
            _ = messageBuffer.readInteger(endianness: .big, as: UInt32.self)

            if messageLength == 0 {
                logger.info("💓 Keep-alive message received")
                continue
            }

            guard let messageId: UInt8 = messageBuffer.readInteger(as: UInt8.self) else { 
                logger.error("❌ Failed to read message ID")
                break 
            }
            let payloadLen = messageLength - 1
            guard let payloadBytes = messageBuffer.readBytes(length: payloadLen) else { 
                logger.error("❌ Failed to read payload bytes")
                break 
            }
            let payload = Data(payloadBytes)
            logger.info("📨 Complete message: id=\(messageId), payload=\(payloadLen) bytes")
            handleMessage(id: messageId, payload: payload)
        }
    }
    
    private func sendHandshake(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: 68)
        // pstrlen
        buffer.writeInteger(UInt8(19))
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
        guard data.count >= 68 else {
            logger.error("Handshake failed: invalid data length \(data.count)")
            return false
        }
        // pstrlen
        let pstrlen = data[0]
        guard pstrlen == 19 else {
            logger.error("Handshake failed: invalid pstrlen \(pstrlen)")
            return false
        }
        // Check protocol string
        let protoStart = 1
        let protoEnd = protoStart + Int(pstrlen)
        let protocolString = String(data: data[protoStart..<protoEnd], encoding: .ascii)
        guard protocolString == "BitTorrent protocol" else {
            logger.error("Handshake failed: invalid protocol string '")
            return false
        }
        // Extract info hash and peer ID
        // Layout: 1 + 19 (proto) + 8 (reserved) + 20 (infohash) + 20 (peerid)
        let receivedInfoHash = data[28..<48]
        let receivedPeerId = data[48..<68]
        guard receivedInfoHash == infoHash else {
            logger.error("Handshake failed: info hash mismatch")
            return false
        }
        logger.debug("Peer ID: \(receivedPeerId.map { String(format: "%02x", $0) }.joined())")
        return true
    }
    
    private func handleMessage(id: UInt8, payload: Data) {
        logger.info("📨 Received message: id=\(id), payload size=\(payload.count)")
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
                // Immediately express interest if peer has anything we need
                // (actual piece selection is handled elsewhere)
                
            
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
                let data = payload.subdata(in: 8..<payload.count)
                logger.info("📦 Received piece: \(pieceIndex), offset: \(offset), data size: \(data.count)")
                
                if let callback = pieceCallback {
                    logger.debug("🔄 Calling piece callback for piece \(pieceIndex)")
                    callback(pieceIndex, offset, data)
                } else {
                    logger.warning("⚠️ No piece callback set!")
                }
            } else {
                logger.error("❌ Invalid piece message: payload too small (\(payload.count) bytes)")
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
