import Foundation

public struct OAuthToken: Codable, Sendable {
    public var accessToken: String
    public var tokenType: String?
    public var expiresIn: TimeInterval
    public var scope: String?
    public var acquiredAt: Date

    public var expiresAt: Date { acquiredAt.addingTimeInterval(expiresIn) }
    public var shouldRefresh: Bool { Date().addingTimeInterval(60) >= expiresAt }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        expiresIn = try container.decode(TimeInterval.self, forKey: .expiresIn)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        acquiredAt = Date()
    }
}

public struct JamfServerInformation: Codable, Sendable {
    public var version: String?
    public var instanceName: String?

    public init(version: String? = nil, instanceName: String? = nil) {
        self.version = version
        self.instanceName = instanceName
    }
}

public actor JamfAPIClient {
    public let baseURL: URL
    public let clientID: String
    private let clientSecret: String
    private let session: URLSession
    private var token: OAuthToken?

    public init(baseURL: URL, clientID: String, clientSecret: String, session: URLSession = .shared) {
        self.baseURL = baseURL.normalizedJamfBaseURL()
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.session = session
    }

    public func validateConnection() async throws -> JamfServerInformation {
        let data = try await request(path: "/api/v2/jamf-pro-information")
        let dictionary = data.decodedDictionary() ?? [:]
        return JamfServerInformation(
            version: JSONValueReader.string(dictionary, keys: ["version", "jamfProVersion", "jamfPro.version"]),
            instanceName: JSONValueReader.string(dictionary, keys: ["instanceName", "name"])
        )
    }

    public func getPro(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        try await request(path: path, queryItems: queryItems, accept: "application/json")
    }

    public func getClassic(path: String) async throws -> Data {
        try await request(path: "/JSSResource" + path, accept: "application/json")
    }

    public func getPaginatedPro(path: String, pageSize: Int = 100, extraQueryItems: [URLQueryItem] = []) async throws -> [Data] {
        var page = 0
        var pages: [Data] = []
        while true {
            let data = try await getPro(
                path: path,
                queryItems: extraQueryItems + [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(pageSize))
                ]
            )
            pages.append(data)
            guard let dictionary = data.decodedDictionary() else { break }
            let totalCount = JSONValueReader.int(dictionary, keys: ["totalCount"]) ?? 0
            let results = (dictionary["results"] as? [Any]) ?? []
            if results.isEmpty || pages.count * pageSize >= totalCount { break }
            page += 1
        }
        return pages
    }

    private func validToken() async throws -> String {
        if let token, !token.shouldRefresh {
            return token.accessToken
        }
        let refreshed = try await fetchToken()
        token = refreshed
        return refreshed.accessToken
    }

    private func fetchToken() async throws -> OAuthToken {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormURLEncoder.encode([
            ("client_id", clientID),
            ("grant_type", "client_credentials"),
            ("client_secret", clientSecret)
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        do {
            return try JSONDecoder().decode(OAuthToken.self, from: data)
        } catch {
            throw JamfMapperError.missingToken
        }
    }

    private func request(path: String, queryItems: [URLQueryItem] = [], accept: String = "application/json") async throws -> Data {
        let token = try await validToken()
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw JamfMapperError.invalidURL
        }
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw JamfMapperError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw JamfMapperError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw JamfMapperError.httpStatus(http.statusCode, body)
        }
    }
}

private extension URL {
    func normalizedJamfBaseURL() -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? self
    }
}
