import Foundation

public struct ConnectionProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var baseURL: URL
    public var clientID: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, baseURL: URL, clientID: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.clientID = clientID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum CrawlStatus: String, Codable, Sendable {
    case pending
    case running
    case complete
    case failed
    case skipped
}

public struct CrawlSnapshotRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var connectionID: UUID
    public var startedAt: Date
    public var completedAt: Date?
    public var status: CrawlStatus
    public var jamfVersion: String?
    public var errorSummary: String?

    public init(
        id: UUID = UUID(),
        connectionID: UUID,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        status: CrawlStatus = .pending,
        jamfVersion: String? = nil,
        errorSummary: String? = nil
    ) {
        self.id = id
        self.connectionID = connectionID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.jamfVersion = jamfVersion
        self.errorSummary = errorSummary
    }
}

public struct RawJamfObject: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(snapshotID.uuidString):\(objectType.rawValue):\(objectID)" }

    public let snapshotID: UUID
    public let objectType: JamfObjectKind
    public let objectID: String
    public let name: String
    public let source: APISource
    public let endpoint: String
    public let payload: Data
    public let contentHash: String
    public let fetchedAt: Date

    public init(snapshotID: UUID, objectType: JamfObjectKind, objectID: String, name: String, source: APISource, endpoint: String, payload: Data, fetchedAt: Date = Date()) {
        self.snapshotID = snapshotID
        self.objectType = objectType
        self.objectID = objectID
        self.name = name
        self.source = source
        self.endpoint = endpoint
        self.payload = payload
        self.contentHash = payload.sha256Hex
        self.fetchedAt = fetchedAt
    }
}

public struct CrawlProgress: Equatable, Sendable {
    public var currentStage: String
    public var completedObjects: Int
    public var totalObjects: Int
    public var errors: [String]

    public var fraction: Double {
        guard totalObjects > 0 else { return 0 }
        return min(1, Double(completedObjects) / Double(totalObjects))
    }

    public init(currentStage: String = "Idle", completedObjects: Int = 0, totalObjects: Int = 0, errors: [String] = []) {
        self.currentStage = currentStage
        self.completedObjects = completedObjects
        self.totalObjects = totalObjects
        self.errors = errors
    }
}
