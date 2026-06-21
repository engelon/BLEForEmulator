import Foundation
import Combine

// MARK: - BridgeController
// Top-level object owned by the App. Manages the TCP server and spawns
// a SessionManager for each connected emulator client.

final class BridgeController: ObservableObject {

    @Published var isListening:   Bool     = false
    @Published var clientCount:   Int      = 0
    @Published var log:           [String] = []

    private let server: TCPServer = TCPServer()
    private var sessions: [UUID: SessionManager] = [:]

    init() {
        server.onClientConnected = { [weak self] conn in
            guard let self else { return }
            let session = SessionManager(connection: conn)
            session.onLog = { [weak self] msg in
                DispatchQueue.main.async { self?.append(msg) }
            }
            sessions[conn.id] = session
            DispatchQueue.main.async {
                self.clientCount = self.server.clientCount
                self.append("✅ emulator connected")
            }
        }

        server.onClientDisconnected = { [weak self] conn in
            guard let self else { return }
            sessions.removeValue(forKey: conn.id)
            DispatchQueue.main.async {
                self.clientCount = self.server.clientCount
                self.append("⚠️ emulator disconnected")
            }
        }
    }

    func start() {
        server.start()
        append("Bridge listening on :\(TCPServer.port)")
        isListening = true
    }

    func stop() {
        server.stop()
        sessions.removeAll()
        append("Bridge stopped")
        isListening = false
        clientCount = 0
    }

    private func append(_ message: String) {
        log.append(message)
        if log.count > 200 { log.removeFirst() }   // keep log bounded
    }
}
