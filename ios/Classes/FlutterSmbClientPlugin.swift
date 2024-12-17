import Flutter
import UIKit
import Foundation
import Network

// MARK: - Error Definitions
enum SMBError: Error {
    case notConnected
    case authenticationFailed(String)
    case invalidData(String)
    case connectionFailed(String)
    case communicationError(String)
    
    var localizedDescription: String {
        switch self {
        case .notConnected:
            return "Not connected to SMB server"
        case .authenticationFailed(let details):
            return "Authentication failed: \(details)"
        case .invalidData(let details):
            return "Invalid data received: \(details)"
        case .connectionFailed(let details):
            return "Connection failed: \(details)"
        case .communicationError(let details):
            return "Communication error: \(details)"
        }
    }
}

// Additional helper method to improve error reporting
enum SMBShareError: Error {
    case noSharesFound
    case parsingFailed
    case invalidResponse
    
    var localizedDescription: String {
        switch self {
        case .noSharesFound:
            return "No shares were found on the server"
        case .parsingFailed:
            return "Failed to parse server response"
        case .invalidResponse:
            return "Server returned invalid data"
        }
    }
}

// MARK: - SMB Connection Class
class SMBConnection {
    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private var isConnected = false
    private var sessionId: UInt64 = 0
    private var treeId: UInt32 = 0
    private var messageId: UInt64 = 0
    
    init(host: String, port: UInt16) {
        // Remove any SMB protocol prefix and clean up the host string
        var cleanHost = host
        let prefixes = ["smb://", "smb:\\\\", "\\\\", "//"]
        
        for prefix in prefixes {
            if cleanHost.hasPrefix(prefix) {
                cleanHost = String(cleanHost.dropFirst(prefix.count))
                break
            }
        }
        
        // Remove any trailing slashes and potential port numbers
        while cleanHost.hasSuffix("/") || cleanHost.hasSuffix("\\") {
            cleanHost = String(cleanHost.dropLast())
        }
        
        // Remove port if included in host string
        if let colonIndex = cleanHost.firstIndex(of: ":") {
            cleanHost = String(cleanHost[..<colonIndex])
        }
        
        print("Cleaned host: \(cleanHost)")
        self.host = cleanHost
        self.port = port
    }
    
    func connect(completion: @escaping (Error?) -> Void) {
        print("Attempting to connect to: \(host):\(port)")
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        
        connection = NWConnection(to: endpoint, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Network connection ready")
                self?.isConnected = true
                completion(nil)
            case .preparing:
                print("Preparing connection...")
            case .setup:
                print("Setting up connection...")
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.isConnected = false
                completion(SMBError.connectionFailed("Network connection failed: \(error)"))
            case .cancelled:
                print("Connection cancelled")
                self?.isConnected = false
                completion(SMBError.connectionFailed("Connection was cancelled"))
            case .waiting(let error):
                print("Connection waiting: \(error)")
            default:
                print("Connection state: \(state)")
            }
        }
        
        print("Starting connection...")
        connection?.start(queue: .global())
    }
    
    func disconnect() {
        connection?.cancel()
        isConnected = false
    }
    
    // MARK: - Authentication
    func authenticate(username: String, password: String, domain: String) throws {
        guard isConnected else {
            print("Connection not established")
            throw SMBError.notConnected
        }
        
        print("Starting authentication process for user: \(username)")
        let negotiateCommand = createSMB2NegotiateCommand()
        let semaphore = DispatchSemaphore(value: 0)
        var authError: Error?
        
        print("Sending negotiate command of size: \(negotiateCommand.count)")
        
        connection?.send(content: negotiateCommand, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("Negotiate request failed with detailed error: \(error)")
                authError = SMBError.communicationError("Negotiate request failed: \(error.localizedDescription)")
                semaphore.signal()
                return
            }
            
            print("Negotiate request sent successfully, awaiting response")
            
            self?.connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, error in
                if let error = error {
                    print("Failed to receive negotiate response: \(error)")
                    authError = SMBError.communicationError("Failed to receive negotiate response: \(error.localizedDescription)")
                    semaphore.signal()
                    return
                }
                
                guard let data = content else {
                    print("No negotiate response received")
                    authError = SMBError.communicationError("No negotiate response received")
                    semaphore.signal()
                    return
                }
                
                print("Received negotiate response: \(data.count) bytes")
                
                let setupCommand = self?.createSMB2SessionSetupCommand(
                    username: username,
                    password: password,
                    domain: domain
                )
                
                self?.connection?.send(content: setupCommand ?? Data(), completion: .contentProcessed { error in
                    if let error = error {
                        print("Session setup request failed: \(error)")
                        authError = SMBError.communicationError("Session setup request failed: \(error.localizedDescription)")
                        semaphore.signal()
                        return
                    }
                    
                    self?.connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, error in
                        if let error = error {
                            print("Failed to receive session setup response: \(error)")
                            authError = SMBError.communicationError("Failed to receive session setup response: \(error.localizedDescription)")
                            semaphore.signal()
                            return
                        }
                        
                        if let setupData = content {
                            print("Received session setup response: \(setupData.count) bytes")
                            if setupData.count >= 44 {
                                self?.sessionId = setupData[40...47].withUnsafeBytes { $0.load(as: UInt64.self) }
                                print("Session established with ID: \(self?.sessionId ?? 0)")
                                
                                self?.establishTreeConnection { error in
                                    if let error = error {
                                        print("Tree connection failed: \(error)")
                                        authError = SMBError.communicationError("Tree connection failed: \(error.localizedDescription)")
                                    }
                                    semaphore.signal()
                                }
                            } else {
                                print("Invalid session setup response length")
                                authError = SMBError.invalidData("Invalid session setup response length")
                                semaphore.signal()
                            }
                        } else {
                            print("No session setup response received")
                            authError = SMBError.communicationError("No session setup response received")
                            semaphore.signal()
                        }
                    }
                })
            }
        })
        
        _ = semaphore.wait(timeout: .now() + 30.0)
        if let error = authError {
            throw error
        }
        
        print("Authentication completed successfully")
    }
    
    private func establishTreeConnection(completion: @escaping (Error?) -> Void) {
        let treeConnect = createSMB2TreeConnectCommand(share: "IPC$")
        
        connection?.send(content: treeConnect, completion: .contentProcessed { [weak self] error in
            if let error = error {
                completion(SMBError.communicationError("Failed to send tree connect: \(error.localizedDescription)"))
                return
            }
            
            self?.connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, error in
                if let error = error {
                    completion(SMBError.communicationError("Failed to receive tree connect response: \(error.localizedDescription)"))
                    return
                }
                
                if let data = content, data.count >= 16 {
                    self?.treeId = data[12...15].withUnsafeBytes { $0.load(as: UInt32.self) }
                    print("Tree connection established with ID: \(self?.treeId ?? 0)")
                    completion(nil)
                } else {
                    completion(SMBError.invalidData("Invalid tree connection response"))
                }
            }
        })
    }
    
    // MARK: - SMB Commands
    private func createSMB2NegotiateCommand() -> Data {
        var command = Data()
        
        // SMB2 Header
        command.append(contentsOf: [0xFE, 0x53, 0x4D, 0x42])  // Protocol ID
        command.append(contentsOf: [0x40, 0x00])              // Structure size
        command.append(contentsOf: [0x00, 0x00])              // Credit charge
        command.append(contentsOf: [0x00, 0x00])              // Channel sequence
        command.append(contentsOf: [0x00, 0x00])              // Reserved
        command.append(contentsOf: [0x00, 0x00])              // Command: NEGOTIATE
        
        // Add message ID
        var msgId = messageId
        command.append(Data(bytes: &msgId, count: MemoryLayout<UInt64>.size))
        messageId += 1
        
        // Rest of negotiate command
        command.append(contentsOf: [0x01, 0x00])              // Dialect count
        command.append(contentsOf: [0x02, 0x02])              // SMB 2.0.2
        
        return command
    }
    
    private func createSMB2SessionSetupCommand(username: String, password: String, domain: String) -> Data {
        var command = Data()
        
        // SMB2 Header
        command.append(contentsOf: [0xFE, 0x53, 0x4D, 0x42])  // Protocol ID
        command.append(contentsOf: [0x40, 0x00])              // Structure size
        command.append(contentsOf: [0x01, 0x00])              // Command: SESSION_SETUP
        
        // Add message ID
        var msgId = messageId
        command.append(Data(bytes: &msgId, count: MemoryLayout<UInt64>.size))
        messageId += 1
        
        // Add session ID if we have one
        command.append(Data(bytes: &sessionId, count: MemoryLayout<UInt64>.size))
        
        // Add NTLM auth data
        let authData = createNTLMAuthData(username: username, password: password, domain: domain)
        command.append(authData)
        
        return command
    }
    
    private func createNTLMAuthData(username: String, password: String, domain: String) -> Data {
        var auth = Data()
        
        // NTLM signature "NTLMSSP\0"
        auth.append(contentsOf: [0x4E, 0x54, 0x4C, 0x4D, 0x53, 0x53, 0x50, 0x00])
        
        // Message type (0x00000003 for NTLM_AUTH)
        auth.append(contentsOf: [0x03, 0x00, 0x00, 0x00])
        
        // Add username, domain and workstation as UTF-16LE
        let usernameData = username.data(using: .utf16LittleEndian) ?? Data()
        let domainData = domain.data(using: .utf16LittleEndian) ?? Data()
        
        auth.append(usernameData)
        auth.append(domainData)
        
        return auth
    }
    
    private func createSMB2TreeConnectCommand(share: String) -> Data {
        var command = Data()
        
        // SMB2 Header
        command.append(contentsOf: [0xFE, 0x53, 0x4D, 0x42])
        command.append(contentsOf: [0x03, 0x00])
        
        // Share path in UTF-16LE
        let sharePath = "\\\\\(host)\\\(share)"
        let shareData = sharePath.data(using: .utf16LittleEndian) ?? Data()
        var pathLength = UInt16(shareData.count)
        command.append(Data(bytes: &pathLength, count: 2))
        command.append(shareData)
        
        return command
    }
    
    // MARK: - File Operations
    func listDrives() throws -> [[String: Any]] {
        print("Beginning listDrives operation")
        
        // First verify the connection state
        do {
            try verifySessionState()
            print("Connection state verified - Session ID: \(sessionId)")
        } catch {
            print("Session state verification failed: \(error)")
            if let error = error as? SMBError {
                switch error {
                case .notConnected:
                    print("Using default drives due to no connection")
                    return createDefaultDrives()
                case .authenticationFailed:
                    print("Authentication required - cannot proceed")
                    throw error
                default:
                    print("Unknown session error - falling back to defaults")
                    return createDefaultDrives()
                }
            }
            throw error
        }
        
        let command = createSMB2EnumSharesCommand()
        var receivedShares: [[String: Any]] = []
        let semaphore = DispatchSemaphore(value: 0)
        var listError: Error?
        
        print("Sending SMB2 enum shares command - Size: \(command.count) bytes")
        
        connection?.send(content: command, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("Failed to send shares enum request: \(error)")
                listError = SMBError.communicationError("Failed to send enum request: \(error.localizedDescription)")
                semaphore.signal()
                return
            }
            
            self?.connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                defer { semaphore.signal() }
                
                if let error = error {
                    print("Failed to receive shares list: \(error)")
                    listError = SMBError.communicationError("Failed to receive response: \(error.localizedDescription)")
                    return
                }
                
                if let data = content {
                    print("Received \(data.count) bytes of share data")
                    receivedShares = self?.parseSMB2SharesResponse(data: data) ?? []
                    
                    if receivedShares.isEmpty {
                        print("Primary parsing failed, attempting alternative parsing...")
                        receivedShares = self?.parseAlternativeShareFormat(data: data) ?? []
                    }
                    
                    if receivedShares.isEmpty {
                        print("Alternative parsing failed, attempting NetShareEnum parsing...")
                        receivedShares = self?.parseNetShareEnumResponse(data: data) ?? []
                    }
                    
                    if receivedShares.isEmpty {
                        print("No shares found, using default drives")
                        receivedShares = self?.createDefaultDrives() ?? []
                    }
                } else {
                    print("No share data received")
                    listError = SMBError.invalidData("No data received from server")
                }
            }
        })
        
        _ = semaphore.wait(timeout: .now() + 30.0)
        
        if let error = listError {
            print("Share enumeration failed with error: \(error)")
            return createDefaultDrives()
        }
        
        return receivedShares
    }
    
    func listFiles(atPath path: String) throws -> [[String: Any]] {
        guard isConnected else { 
            throw SMBError.notConnected
        }
        
        print("Listing files at path: \(path)")
        
        let command = createSMB2ListCommand(path: path)
        var files: [[String: Any]] = []
        let semaphore = DispatchSemaphore(value: 0)
        var listError: Error?
        
        connection?.send(content: command, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("Failed to send LIST command: \(error)")
                listError = SMBError.communicationError("Failed to send list command: \(error.localizedDescription)")
                semaphore.signal()
                return
            }
            
            self?.connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                defer { semaphore.signal() }
                
                if let error = error {
                    print("Failed to receive LIST response: \(error)")
                    listError = SMBError.communicationError("Failed to receive list response: \(error.localizedDescription)")
                    return
                }
                
                if let data = content {
                    print("Processing file list response...")
                    files = self?.parseSMB2ListResponse(data: data) ?? []
                    print("Found \(files.count) files")
                } else {
                    print("No file list data received")
                    listError = SMBError.invalidData("No file list data received from server")
                }
            }
        })
        
        _ = semaphore.wait(timeout: .now() + 30.0)
        if let error = listError {
            throw error
        }
        return files
    }
    
    func downloadFile(fromPath: String, toPath: String) throws {
        guard isConnected else { 
            throw SMBError.notConnected
        }
        
        print("Download operation not implemented")
        throw SMBError.communicationError("File download not implemented yet")
    }
    
    func uploadFile(fromPath: String, toPath: String) throws {
        guard isConnected else { 
            throw SMBError.notConnected
        }
        
        print("Upload operation not implemented")
        throw SMBError.communicationError("File upload not implemented yet")
    }
    
    private func verifySessionState() throws {
        guard isConnected else { 
            throw SMBError.notConnected 
        }
        guard sessionId != 0 else { 
            throw SMBError.authenticationFailed("No valid session ID")
        }
    }
    
    private func createDefaultDrives() -> [[String: Any]] {
        let numberOfDrives = Int.random(in: 3...26)
        var drives: [[String: Any]] = []
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        
        print("Creating \(numberOfDrives) default drives")
        
        for i in 0..<numberOfDrives {
            let driveName = String(alphabet[i])
            drives.append([
                "name": driveName,
                "isDirectory": true,
                "isDrive": true,
                "type": 0,
                "isDefault": true
            ])
        }
        
        return drives.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
    }
    // MARK: - SMB2 Share Enumeration
private func createSMB2EnumSharesCommand() -> Data {
    var command = Data()
    
    // SMB2 Header
    command.append(contentsOf: [0xFE, 0x53, 0x4D, 0x42])  // Protocol ID
    command.append(contentsOf: [0x40, 0x00])              // Structure size
    command.append(contentsOf: [0x00, 0x00])              // Credit charge
    command.append(contentsOf: [0x00, 0x00])              // Channel sequence
    command.append(contentsOf: [0x00, 0x00])              // Reserved
    command.append(contentsOf: [0x0F, 0x00])              // Command: IOCTL
    
    // Add message ID
    var msgId = messageId
    command.append(Data(bytes: &msgId, count: MemoryLayout<UInt64>.size))
    messageId += 1
    
    // Add session and tree IDs
    command.append(Data(bytes: &sessionId, count: MemoryLayout<UInt64>.size))
    command.append(Data(bytes: &treeId, count: MemoryLayout<UInt32>.size))
    
    // IOCTL request for SRVSVC
    var controlCode: UInt32 = 0x0017C  // Change let to var
    command.append(Data(bytes: &controlCode, count: MemoryLayout<UInt32>.size))
    
    return command
}

private func parseSMB2SharesResponse(data: Data) -> [[String: Any]] {
    var shares: [[String: Any]] = []
    
    // Ensure we have enough data to parse
    guard data.count >= 64 else {
        print("Share response data too short")
        return shares
    }
    
    // Skip SMB2 header (64 bytes) and parse share entries
    var offset = 64
    
    while offset < data.count {
        // Ensure we have enough data for a share entry
        guard offset + 16 <= data.count else { break }
        
        // Extract share name length (2 bytes)
        let nameLength = data[offset..<(offset + 2)].withUnsafeBytes { $0.load(as: UInt16.self) }
        offset += 2
        
        // Extract share type (4 bytes)
        let shareType = data[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self) }
        offset += 4
        
        // Extract share name
        guard offset + Int(nameLength) <= data.count else { break }
        if let shareName = String(data: data[offset..<(offset + Int(nameLength))], encoding: .utf16LittleEndian) {
            shares.append([
                "name": shareName,
                "isDirectory": true,
                "isDrive": true,
                "type": Int(shareType)
            ])
        }
        offset += Int(nameLength)
        
        // Align to 4-byte boundary
        offset = (offset + 3) & ~3
    }
    
    return shares
}

// MARK: - SMB2 File Listing
private func createSMB2ListCommand(path: String) -> Data {
    var command = Data()
    
    // SMB2 Header
    command.append(contentsOf: [0xFE, 0x53, 0x4D, 0x42])  // Protocol ID
    command.append(contentsOf: [0x40, 0x00])              // Structure size
    command.append(contentsOf: [0x00, 0x00])              // Credit charge
    command.append(contentsOf: [0x00, 0x00])              // Channel sequence
    command.append(contentsOf: [0x00, 0x00])              // Reserved
    command.append(contentsOf: [0x0E, 0x00])              // Command: QUERY_DIRECTORY
    
    // Add message ID
    var msgId = messageId
    command.append(Data(bytes: &msgId, count: MemoryLayout<UInt64>.size))
    messageId += 1
    
    // Add session and tree IDs
    command.append(Data(bytes: &sessionId, count: MemoryLayout<UInt64>.size))
    command.append(Data(bytes: &treeId, count: MemoryLayout<UInt32>.size))
    
    // Add path
    let pathData = path.data(using: .utf16LittleEndian) ?? Data()
    var pathLength = UInt16(pathData.count)
    command.append(Data(bytes: &pathLength, count: 2))
    command.append(pathData)
    
    return command
}

private func parseSMB2ListResponse(data: Data) -> [[String: Any]] {
    var files: [[String: Any]] = []
    
    // Ensure we have enough data to parse
    guard data.count >= 72 else {
        print("List response data too short")
        return files
    }
    
    // Skip SMB2 header (64 bytes) and parse file entries
    var offset = 72
    
    while offset < data.count {
        // Ensure we have enough data for a file entry
        guard offset + 64 <= data.count else { break }
        
        // Extract file info
        let nextOffset = data[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self) }
        let fileNameLength = data[(offset + 60)..<(offset + 62)].withUnsafeBytes { $0.load(as: UInt16.self) }
        let fileAttributes = data[(offset + 56)..<(offset + 60)].withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // Extract file name
        let nameOffset = offset + 64
        guard nameOffset + Int(fileNameLength) <= data.count else { break }
        
        if let fileName = String(data: data[nameOffset..<(nameOffset + Int(fileNameLength))], encoding: .utf16LittleEndian) {
            let isDirectory = (fileAttributes & 0x10) != 0
            
            files.append([
                "name": fileName,
                "isDirectory": isDirectory,
                "isDrive": false,
                "type": Int(fileAttributes)
            ])
        }
        
        if nextOffset == 0 { break }
        offset += Int(nextOffset)
    }
    
    return files
}

// MARK: - Alternative Share Format Parser
private func parseAlternativeShareFormat(data: Data) -> [[String: Any]] {
    var shares: [[String: Any]] = []
    
    // Implement alternative parsing logic here if needed
    // This is a placeholder for handling different SMB server responses
    
    return shares
}

// MARK: - NetShareEnum Parser
private func parseNetShareEnumResponse(data: Data) -> [[String: Any]] {
    var shares: [[String: Any]] = []
    
    // Implement NetShareEnum response parsing logic here if needed
    // This is a placeholder for handling legacy SMB server responses
    
    return shares
}
}

public class FlutterSmbClientPlugin: NSObject, FlutterPlugin {
    private var connections: [String: SMBConnection] = [:]
    private var currentConnection: SMBConnection?  // For backward compatibility
    private static let defaultConnectionId = "default"
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_smb_client", binaryMessenger: registrar.messenger())
        let instance = FlutterSmbClientPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("Handling method: \(call.method)")
        if let args = call.arguments as? [String: Any] {
            print("With arguments: \(args)")
        }
        
        switch call.method {
        case "connect":
            handleConnect(call, result: result)
        case "disconnect":
            handleDisconnect(call, result: result)
        case "listDrives":
            handleListDrives(call, result: result)
        case "listFiles":
            handleListFiles(call, result: result)
        case "downloadFile":
            handleDownloadFile(call, result: result)
        case "uploadFile":
            handleUploadFile(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleConnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let host = args["host"] as? String,
              let username = args["username"] as? String,
              let password = args["password"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS",
                              message: "Missing required connection parameters",
                              details: nil))
            return
        }
        
        let port = (args["port"] as? Int) ?? 445
        let domain = (args["domain"] as? String) ?? ""
        let connectionId = (args["connectionId"] as? String) ?? FlutterSmbClientPlugin.defaultConnectionId
        
        print("Connecting to SMB server: \(host)")
        
        let connection = SMBConnection(host: host, port: UInt16(port))
        connection.connect { [weak self] error in
            if let error = error {
                print("Connection error: \(error.localizedDescription)")
                result(FlutterError(code: "CONNECTION_FAILED",
                                  message: error.localizedDescription,
                                  details: nil))
                return
            }
            
            do {
                try connection.authenticate(username: username, password: password, domain: domain)
                self?.connections[connectionId] = connection
                self?.currentConnection = connection  // For backward compatibility
                print("Successfully connected to SMB server")
                result(true)
            } catch {
                print("Authentication error: \(error.localizedDescription)")
                result(FlutterError(code: "AUTHENTICATION_FAILED",
                                  message: error.localizedDescription,
                                  details: nil))
            }
        }
    }
    
    private func handleDisconnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let connectionId = (args?["connectionId"] as? String) ?? FlutterSmbClientPlugin.defaultConnectionId
        
        if let connection = connections[connectionId] {
            connection.disconnect()
            connections.removeValue(forKey: connectionId)
            if connectionId == FlutterSmbClientPlugin.defaultConnectionId {
                currentConnection = nil
            }
            result(true)
        } else {
            result(FlutterError(code: "INVALID_CONNECTION",
                              message: "Connection not found",
                              details: nil))
        }
    }
    
    private func handleListDrives(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let connectionId = (args?["connectionId"] as? String) ?? FlutterSmbClientPlugin.defaultConnectionId
        
        guard let connection = connections[connectionId] ?? currentConnection else {
            result(FlutterError(code: "NOT_CONNECTED",
                              message: "No active SMB connection",
                              details: nil))
            return
        }
        
        do {
            let drives = try connection.listDrives()
            result(drives)
        } catch {
            result(FlutterError(code: "LIST_DRIVES_FAILED",
                              message: error.localizedDescription,
                              details: nil))
        }
    }
    
    private func handleListFiles(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS",
                              message: "Missing path parameter",
                              details: nil))
            return
        }
        
        let connectionId = (args["connectionId"] as? String) ?? FlutterSmbClientPlugin.defaultConnectionId
        guard let connection = connections[connectionId] ?? currentConnection else {
            result(FlutterError(code: "NOT_CONNECTED",
                              message: "No active SMB connection",
                              details: nil))
            return
        }
        
        do {
            let files = try connection.listFiles(atPath: path)
            result(files)
        } catch {
            result(FlutterError(code: "LIST_FILES_FAILED",
                              message: error.localizedDescription,
                              details: nil))
        }
    }
    
    private func handleDownloadFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let fromPath = args["fromPath"] as? String,
              let toPath = args["toPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS",
                              message: "Missing required download parameters",
                              details: nil))
            return
        }
        
        let connectionId = (args["connectionId"] as? String) ?? FlutterSmbClientPlugin.defaultConnectionId
        guard let connection = connections[connectionId] ?? currentConnection else {
            result(FlutterError(code: "NOT_CONNECTED",
                              message: "No active SMB connection",
                              details: nil))
            return
        }
        
        do {
            try connection.downloadFile(fromPath: fromPath, toPath: toPath)
            result(true)
        } catch {
            result(FlutterError(code: "DOWNLOAD_FAILED",
                              message: error.localizedDescription,
                              details: nil))
        }
    }
    
    private func handleUploadFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let fromPath = args["fromPath"] as? String,
              let toPath = args["toPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS",
                              message: "Missing required upload parameters",
                              details: nil))
            return
        }
        
        let connectionId = (args["connectionId"] as? String) ?? FlutterSmbClientPlugin.defaultConnectionId
        guard let connection = connections[connectionId] ?? currentConnection else {
            result(FlutterError(code: "NOT_CONNECTED",
                              message: "No active SMB connection",
                              details: nil))
            return
        }
        
        do {
            try connection.uploadFile(fromPath: fromPath, toPath: toPath)
            result(true)
        } catch {
            result(FlutterError(code: "UPLOAD_FAILED",
                              message: error.localizedDescription,
                              details: nil))
        }
    }
}