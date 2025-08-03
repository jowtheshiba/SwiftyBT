import Foundation
import Darwin
import Logging

/// UDP socket implementation using low-level BSD sockets
public class UDPSocket {
    private let logger: Logger
    private var socket: Int32 = -1
    private let timeout: TimeInterval
    
    public init(timeout: TimeInterval = 10.0) {
        self.timeout = timeout
        self.logger = Logger(label: "SwiftyBT.UDPSocket")
    }
    
    deinit {
        close()
    }
    
    /// Create UDP socket
    private func createSocket() throws {
        socket = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        if socket == -1 {
            throw UDPSocketError.socketCreationFailed
        }
        
        // Set socket options
        var timeoutValue = timeval(tv_sec: Int(timeout), tv_usec: 0)
        let result = setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
        if result == -1 {
            throw UDPSocketError.socketOptionFailed
        }
        
        // Set send timeout
        let sendResult = setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
        if sendResult == -1 {
            throw UDPSocketError.socketOptionFailed
        }
    }
    
    /// Send data to specified host and port
    /// - Parameters:
    ///   - data: Data to send
    ///   - host: Target host
    ///   - port: Target port
    /// - Throws: UDPSocketError if send fails
    public func send(_ data: Data, to host: String, port: UInt16) async throws {
        try createSocket()
        defer { close() }
        
        // Resolve host address
        let address = try resolveAddress(host: host, port: port)
        
        // Send data
        let result = data.withUnsafeBytes { buffer in
            withUnsafePointer(to: address) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                    Darwin.sendto(socket, buffer.baseAddress, buffer.count, 0, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        
        if result == -1 {
            throw UDPSocketError.sendFailed
        }
        
        logger.debug("Sent \(result) bytes to \(host):\(port)")
    }
    
    /// Send data and receive response
    /// - Parameters:
    ///   - data: Data to send
    ///   - host: Target host
    ///   - port: Target port
    /// - Returns: Received data
    /// - Throws: UDPSocketError if operation fails
    public func sendAndReceive(_ data: Data, to host: String, port: UInt16) async throws -> Data {
        try createSocket()
        defer { close() }
        
        // Resolve host address
        let address = try resolveAddress(host: host, port: port)
        
        // Send data
        let sendResult = data.withUnsafeBytes { buffer in
            withUnsafePointer(to: address) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                    Darwin.sendto(socket, buffer.baseAddress, buffer.count, 0, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        
        if sendResult == -1 {
            throw UDPSocketError.sendFailed
        }
        
        logger.debug("Sent \(sendResult) bytes to \(host):\(port)")
        
        // Receive response
        var buffer = [UInt8](repeating: 0, count: 4096)
        var fromAddr = sockaddr_in()
        var fromAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        // Use a simpler approach without complex pointer manipulation
        let receiveResult = buffer.withUnsafeMutableBytes { buffer in
            Darwin.recvfrom(socket, buffer.baseAddress, buffer.count, 0, nil, nil)
        }
        
        if receiveResult == -1 {
            throw UDPSocketError.receiveFailed
        }
        
        let responseData = Data(buffer.prefix(receiveResult))
        logger.debug("Received \(receiveResult) bytes from \(host):\(port)")
        
        return responseData
    }
    
    /// Resolve host address
    /// - Parameters:
    ///   - host: Host name or IP address
    ///   - port: Port number
    /// - Returns: sockaddr_in structure
    /// - Throws: UDPSocketError if resolution fails
    private func resolveAddress(host: String, port: UInt16) throws -> sockaddr_in {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP
        
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        
        defer {
            if let result = result {
                freeaddrinfo(result)
            }
        }
        
        guard status == 0, let addrInfo = result else {
            throw UDPSocketError.addressResolutionFailed
        }
        
        guard addrInfo.pointee.ai_family == AF_INET else {
            throw UDPSocketError.addressResolutionFailed
        }
        
        let sockAddr = addrInfo.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        return sockAddr
    }
    
    /// Close socket
    private func close() {
        if socket != -1 {
            Darwin.close(socket)
            socket = -1
        }
    }
}

/// UDP socket errors
public enum UDPSocketError: Error {
    case socketCreationFailed
    case socketOptionFailed
    case addressResolutionFailed
    case sendFailed
    case receiveFailed
    case timeout
} 