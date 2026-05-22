import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var name = ""
    @State private var url = "https://"
    @State private var clientID = ""
    @State private var clientSecret = ""

    var body: some View {
        Form {
            Section("Add Connection") {
                TextField("Connection name", text: $name)
                TextField("Jamf URL", text: $url)
                TextField("API Client ID", text: $clientID)
                SecureField("Client Secret", text: $clientSecret)

                Button {
                    Task {
                        await state.saveConnection(name: name, urlString: url, clientID: clientID, clientSecret: clientSecret)
                        name = ""
                        url = "https://"
                        clientID = ""
                        clientSecret = ""
                    }
                } label: {
                    Label("Validate and Save", systemImage: "checkmark.seal")
                }
                .disabled(url.count < 9 || clientID.isEmpty || clientSecret.isEmpty)
            }

            Section("Saved Connections") {
                ForEach(state.connections) { connection in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.name)
                            Text(connection.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if connection.id == state.selectedConnectionID {
                            Button(role: .destructive) {
                                state.signOutSelectedConnection()
                            } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            .disabled(state.isCrawling)
                        }
                    }
                }
            }
        }
        .padding()
    }
}
