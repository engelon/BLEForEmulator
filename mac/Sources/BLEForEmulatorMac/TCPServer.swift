import Foundation
import Network
import Combine

// MARK: - Client connection

final class BridgeConnection {
    let id:         UUID = UUID()
    private let connection: NWConnection
    private var buffer: Data = Data()
    var onCommand: ((BridgeCommand) -> Void)?
    var onDisconnect: (() -> Void)?

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.onDisconnect?()
            default:
                break
            }
        }
        connection.start(queue: .main)
        receive()
    }

    func send(_ event: BridgeEvent) {
        guard let data = event.encode() else { return }
        connection.send(content: data, completion: .idempotent)
        // TODO: handle send backpressure for slow clients
    }

    func cancel() {
        connection.cancel()
    }

    // MARK: - Private

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let data = content, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }

            if isComplete || error != nil {
                self.onDisconnect?()
                return
            }

            self.receive()  // read loop
        }
    }

    private func processBuffer() {
        // Split buffer on newlines and dispatch each complete line
        while let range = buffer.range(of: Data([UInt8(ascii: "\n")])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)

            if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespaces),
               !line.isEmpty,
               let command = parseLine(line) {
                onCommand?(command)
            }
            // TODO: log unparseable lines for debug builds
        }
    }
}

// MARK: - TCP Server

final class TCPServer: ObservableObject {
    static let port: NWEndpoint.Port = 7877

    @Published var isListening: Bool = false
    @Published var clientCount: Int  = 0

    var onClientConnected:    ((BridgeConnection) -> Void)?
    var onClientDisconnected: ((BridgeConnection) -> Void)?

    private var listener:    NWListener?
    private var connections: [UUID: BridgeConnection] = [:]

    func start() {
        do {
            listener = try NWListener(using: .tcp, on: Self.port)
        } catch {
            // TODO: surface error in menu bar UI
            return
        }

        listener?.newConnectionHandler = { [weak self] nwConn in
            guard let self else { return }
            let conn = BridgeConnection(nwConn)

            conn.onDisconnect = { [weak self, weak conn] in
                guard let self, let conn else { return }
                self.connections.removeValue(forKey: conn.id)
                self.clientCount = self.connections.count
                self.onClientDisconnected?(conn)
            }

            self.connections[conn.id] = conn
            self.clientCount = self.connections.count
            conn.start()
            self.onClientConnected?(conn)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.isListening = (state == .ready)
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        isListening = false
        clientCount = 0
    }
}
