import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("jamfMapperDarkMode") private var darkMode = true

    @State private var url = ""
    @State private var clientID = ""
    @State private var clientSecret = ""

    var body: some View {
        ZStack {
            LoginBackground()

            HStack(spacing: 0) {
                brandPanel
                    .frame(maxWidth: 470)

                Divider()
                    .opacity(0.35)

                formPanel
                    .frame(maxWidth: 520)
            }
            .frame(maxWidth: 1040, maxHeight: 650)
            .padding(28)
        }
    }

    private var brandPanel: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 12) {
                AppBrandIcon()
                    .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Jamf Mapper")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Powered by Ebi Insights")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome to Jamf Mapper")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text("Audit Jamf Pro dependencies with local snapshots, clear object mappings, and relationship-aware cleanup signals.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                TrustRow(symbol: "lock.shield", title: "Keychain protected", detail: "Client secrets are stored in macOS Keychain.")
                TrustRow(symbol: "externaldrive.badge.timemachine", title: "Local snapshots", detail: "Crawl results stay in local SQLite storage.")
                TrustRow(symbol: "point.3.connected.trianglepath.dotted", title: "Readable dependencies", detail: "Policies, groups, packages, scripts, EAs, and profiles are mapped by name and ID.")
            }

            Spacer(minLength: 20)
        }
        .padding(34)
    }

    private var formPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Spacer()
                Toggle(isOn: $darkMode) {
                    Label(darkMode ? "Dark" : "Light", systemImage: darkMode ? "moon.fill" : "sun.max.fill")
                }
                .toggleStyle(.switch)
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Connect Jamf Pro")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Use an API Client ID and Client Secret with read access to the objects you want to map.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 14) {
                LoginField(
                    title: "Jamf Server URL",
                    placeholder: "https://yourtenant.jamfcloud.com",
                    systemImage: "globe",
                    text: $url
                )

                LoginField(
                    title: "API Client ID",
                    placeholder: "Client ID from Jamf Pro API Roles and Clients",
                    systemImage: "person.text.rectangle",
                    text: $clientID
                )

                SecureLoginField(
                    title: "Client Secret",
                    placeholder: "Client Secret stored securely in Keychain",
                    systemImage: "key",
                    text: $clientSecret
                )
            }

            Button {
                Task {
                    await state.saveConnection(name: "", urlString: url, clientID: clientID, clientSecret: clientSecret)
                }
            } label: {
                HStack {
                    if state.isCrawling {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(state.isCrawling ? "Validating Connection" : "Connect Securely")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || clientID.isEmpty || clientSecret.isEmpty || state.isCrawling)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.green)
                Text("Read-only dependency mapping. No Jamf objects are modified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(34)
    }
}

private struct LoginBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.05, green: 0.07, blue: 0.10), Color(red: 0.07, green: 0.11, blue: 0.14)]
                : [Color(red: 0.96, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.95, blue: 0.97)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct TrustRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.teal)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LoginField: View {
    let title: String
    let placeholder: String
    let systemImage: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.secondary))
                    .textFieldStyle(.plain)
                    .font(.body)
            }
            .padding(12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
    }
}

private struct SecureLoginField: View {
    let title: String
    let placeholder: String
    let systemImage: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(.secondary))
                    .textFieldStyle(.plain)
                    .font(.body)
            }
            .padding(12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
    }
}
