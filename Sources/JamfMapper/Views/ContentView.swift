import JamfMapperCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("jamfMapperDarkMode") private var darkMode = true

    var body: some View {
        Group {
            if state.connections.isEmpty {
                OnboardingView()
            } else {
                NavigationSplitView {
                    SidebarView()
                } content: {
                    if state.showingAuditReports {
                        CleanupView()
                    } else {
                        GraphScreen()
                    }
                } detail: {
                    InspectorView()
                }
            }
        }
        .preferredColorScheme(darkMode ? .dark : .light)
        .toolbar {
            if !state.connections.isEmpty {
                ToolbarItemGroup {
                    Picker("Connection", selection: Binding(
                        get: { state.selectedConnectionID },
                        set: { id in
                            state.selectConnection(state.connections.first { $0.id == id })
                        }
                    )) {
                        ForEach(state.connections) { connection in
                            Text(connection.name).tag(Optional(connection.id))
                        }
                    }
                    .frame(width: 220)

                    Button {
                        state.exportJSON()
                    } label: {
                        Label("Export JSON", systemImage: "doc.badge.arrow.up")
                    }
                    .disabled(state.graph.nodes.isEmpty)

                    Button {
                        state.exportCSV()
                    } label: {
                        Label("Export CSV", systemImage: "tablecells")
                    }
                    .disabled(state.graph.nodes.isEmpty)

                    Button(role: .destructive) {
                        state.signOutSelectedConnection()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(state.selectedConnection == nil || state.isCrawling)
                }
            }
        }
        .alert("JamfMapper", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}
