import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var bridge: BridgeController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Status row
            HStack {
                Circle()
                    .fill(bridge.isListening ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(bridge.isListening
                     ? "Listening on :7788"
                     : "Stopped")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text("\(bridge.clientCount) client\(bridge.clientCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Divider()

            // Log
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(bridge.log.indices, id: \.self) { i in
                            Text(bridge.log[i])
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .id(i)
                        }
                    }
                }
                .frame(height: 200)
                .onChange(of: bridge.log.count) { _ in
                    if let last = bridge.log.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Controls
            HStack {
                if bridge.isListening {
                    Button("Stop") { bridge.stop() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                } else {
                    Button("Start Bridge") { bridge.start() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { bridge.start() }
    }
}
