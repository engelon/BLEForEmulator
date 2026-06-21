package com.bleforemulator

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.Socket
import java.net.InetSocketAddress

// Connects to the Mac bridge on 10.0.2.2:7788 (emulator host IP).
// Runs send/receive on background threads — all callbacks arrive on those threads;
// callers are responsible for dispatching to the main thread if needed.

internal class BridgeTCPClient(
    private val host: String = "10.0.2.2",
    private val port: Int    = 7877
) {
    var onEvent:      ((BridgeEvent) -> Unit)? = null
    var onDisconnect: (() -> Unit)?            = null

    private var socket: Socket?      = null
    private var writer: PrintWriter? = null
    private var running = false

    fun connect() {
        if (running) return
        running = true

        Thread {
            try {
                val s = Socket()
                s.connect(InetSocketAddress(host, port), 5_000)
                socket = s
                writer = PrintWriter(s.getOutputStream(), true)

                val reader = BufferedReader(InputStreamReader(s.getInputStream()))
                while (running) {
                    val line = reader.readLine() ?: break  // null = EOF
                    val event = BridgeEvent.parse(line) ?: continue
                    onEvent?.invoke(event)
                }
            } catch (_: Exception) {
                // TODO: expose connection errors as a BridgeEvent
            } finally {
                running = false
                socket = null
                writer = null
                onDisconnect?.invoke()
            }
        }.apply { isDaemon = true; start() }
    }

    fun send(command: BridgeCommand) {
        Thread {
            try {
                writer?.println(command.toJson())
                // println flushes automatically (autoFlush = true)
            } catch (_: Exception) {
                // TODO: queue and retry on reconnect
            }
        }.apply { isDaemon = true; start() }
    }

    fun disconnect() {
        running = false
        runCatching { socket?.close() }
    }
}
