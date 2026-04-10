import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Meeting Bot Native Control")
                .font(.title2)
                .bold()

            GroupBox("Project") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("/absolute/path/to/meeting-bot-local", text: $vm.projectPath)
                    HStack {
                        Button("Choose Folder") {
                            vm.pickProjectFolder()
                        }
                        .disabled(vm.busy)
                        Button("Reload .env") {
                            Task { await vm.loadEnv() }
                        }
                        .disabled(vm.busy)
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Recording Configuration") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Quality", selection: $vm.quality) {
                        Text("720p").tag("720p")
                        Text("1080p").tag("1080p")
                    }
                    .pickerStyle(.segmented)

                    TextField("Host recordings directory", text: $vm.hostDir)
                    TextField("Container recordings directory", text: $vm.containerDir)
                    TextField("Bearer token", text: $vm.bearerToken)

                    HStack {
                        Button("Save Config + Restart Bot") {
                            Task { await vm.saveConfigAndRestart() }
                        }
                        .disabled(vm.busy)

                        Button("Refresh Logs") {
                            Task { await vm.refreshLogs() }
                        }
                        .disabled(vm.busy)
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Join Meeting") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("https://meet.google.com/...", text: $vm.meetingLink)
                    Button("Join Link") {
                        Task { await vm.joinMeeting() }
                    }
                    .disabled(vm.busy)
                }
                .padding(.top, 4)
            }

            Text(vm.status)
                .font(.callout)
                .foregroundStyle(vm.busy ? .orange : .secondary)

            GroupBox("Logs") {
                ScrollView {
                    Text(vm.logs.isEmpty ? "No logs yet." : vm.logs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
    }
}
