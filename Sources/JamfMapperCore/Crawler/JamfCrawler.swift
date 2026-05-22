import Foundation

public final class JamfCrawler: Sendable {
    public typealias ProgressHandler = @Sendable (CrawlProgress) async -> Void

    private let apiClient: JamfAPIClient
    private let store: DatabaseStore
    private let limiter: JamfRateLimiter

    public init(apiClient: JamfAPIClient, store: DatabaseStore, limiter: JamfRateLimiter = JamfRateLimiter()) {
        self.apiClient = apiClient
        self.store = store
        self.limiter = limiter
    }

    public func crawl(connectionID: UUID, progress: ProgressHandler? = nil) async throws -> UUID {
        let info = try await apiClient.validateConnection()
        let snapshot = CrawlSnapshotRecord(connectionID: connectionID, status: .running, jamfVersion: info.version)
        try store.insertSnapshot(snapshot)
        await progress?(CrawlProgress(currentStage: "Starting crawl", completedObjects: 0, totalObjects: 1))

        var rawObjects: [RawJamfObject] = []
        var errors: [String] = []
        var completed = 0

        for endpoint in JamfEndpointCatalog.classicCore {
            await progress?(CrawlProgress(currentStage: "Classic \(endpoint.collectionPath)", completedObjects: completed, totalObjects: completed + 1, errors: errors))
            do {
                let objects = try await crawlClassicEndpoint(endpoint, snapshotID: snapshot.id)
                rawObjects.append(contentsOf: objects)
                completed += objects.count
                await progress?(CrawlProgress(currentStage: "Fetched \(endpoint.kind.displayName)", completedObjects: completed, totalObjects: max(completed, rawObjects.count), errors: errors))
            } catch {
                errors.append("\(endpoint.collectionPath): \(error.localizedDescription)")
            }
        }

        for collection in JamfEndpointCatalog.proCollections {
            await progress?(CrawlProgress(currentStage: "Pro \(collection.path)", completedObjects: completed, totalObjects: max(completed + 1, rawObjects.count), errors: errors))
            do {
                let objects = try await crawlProCollection(kind: collection.kind, path: collection.path, snapshotID: snapshot.id)
                rawObjects.append(contentsOf: objects)
                completed += objects.count
                await progress?(CrawlProgress(currentStage: "Fetched \(collection.kind.displayName)", completedObjects: completed, totalObjects: max(completed, rawObjects.count), errors: errors))
            } catch {
                errors.append("\(collection.path): \(error.localizedDescription)")
            }
        }

        try store.insertRawObjects(rawObjects)
        let graph = GraphExtractor().extract(rawObjects: rawObjects)
        try store.replaceGraph(snapshotID: snapshot.id, graph: graph)
        try store.updateSnapshotStatus(
            snapshot.id,
            status: errors.isEmpty ? .complete : .failed,
            completedAt: Date(),
            jamfVersion: info.version,
            errorSummary: errors.isEmpty ? nil : errors.joined(separator: "\n")
        )
        await progress?(CrawlProgress(currentStage: errors.isEmpty ? "Crawl complete" : "Crawl completed with errors", completedObjects: completed, totalObjects: max(completed, rawObjects.count), errors: errors))
        return snapshot.id
    }

    private func crawlClassicEndpoint(_ endpoint: ClassicEndpoint, snapshotID: UUID) async throws -> [RawJamfObject] {
        let listData = try await rateLimitedRequest { try await self.apiClient.getClassic(path: endpoint.collectionPath) }
        let listDictionary = listData.decodedDictionary() ?? [:]
        let listRoot = listDictionary[endpoint.rootKey] ?? listDictionary
        let items = JSONValueReader.array(listRoot, keys: [endpoint.itemKey, endpoint.itemKey + "s", endpoint.rootKey])
        guard !items.isEmpty else {
            return [RawJamfObject(snapshotID: snapshotID, objectType: endpoint.kind, objectID: "list", name: endpoint.kind.displayName, source: .classic, endpoint: endpoint.collectionPath, payload: listData)]
        }

        var rawObjects: [RawJamfObject] = []
        for item in items {
            guard let id = JSONValueReader.string(item, keys: ["id"]) else { continue }
            let detailPath = "\(endpoint.collectionPath)/id/\(id)"
            do {
                let detailData = try await rateLimitedRequest { try await self.apiClient.getClassic(path: detailPath) }
                let name = nameForPayload(detailData, fallback: JSONValueReader.string(item, keys: ["name", "packageName", "fileName"]) ?? "\(endpoint.kind.rawValue) \(id)", rootKey: endpoint.itemKey)
                rawObjects.append(RawJamfObject(snapshotID: snapshotID, objectType: endpoint.kind, objectID: id, name: name, source: .classic, endpoint: detailPath, payload: detailData))
            } catch {
                rawObjects.append(RawJamfObject(snapshotID: snapshotID, objectType: endpoint.kind, objectID: id, name: JSONValueReader.string(item, keys: ["name", "packageName", "fileName"]) ?? "\(endpoint.kind.rawValue) \(id)", source: .classic, endpoint: detailPath, payload: Data("{\"crawl_error\":\"\(error.localizedDescription)\"}".utf8)))
            }
        }
        return rawObjects
    }

    private func crawlProCollection(kind: JamfObjectKind, path: String, snapshotID: UUID) async throws -> [RawJamfObject] {
        let pages = try await rateLimitedRequest { try await self.apiClient.getPaginatedPro(path: path) }
        var rawObjects: [RawJamfObject] = []
        for pageData in pages {
            guard let dictionary = pageData.decodedDictionary() else {
                rawObjects.append(RawJamfObject(snapshotID: snapshotID, objectType: kind, objectID: "page-\(rawObjects.count)", name: kind.displayName, source: .pro, endpoint: path, payload: pageData))
                continue
            }
            let results = (dictionary["results"] as? [Any]) ?? []
            for result in results {
                guard let objectData = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) else { continue }
                let id = JSONValueReader.string(result, keys: ["id", "definitionId", "uuid", "groupJamfProId", "packageId"]) ?? "unresolved-\(objectData.sha256Hex.prefix(12))"
                let name = JSONValueReader.string(result, keys: ["name", "displayName", "groupName", "profileName", "title", "packageName", "fileName"]) ?? "\(kind.rawValue) \(id)"
                rawObjects.append(RawJamfObject(snapshotID: snapshotID, objectType: kind, objectID: id, name: name, source: .pro, endpoint: path, payload: objectData))
            }
        }
        return rawObjects
    }

    private func rateLimitedRequest<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await self.limiter.acquire()
                let start = ContinuousClock.now
                defer {
                    let duration = start.duration(to: .now)
                    Task { await self.limiter.release(responseDuration: duration) }
                }
                return try await Self.retrying(operation)
            }
            guard let value = try await group.next() else {
                throw JamfMapperError.invalidResponse
            }
            return value
        }
    }

    private static func retrying<T>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        var delay: UInt64 = 300_000_000
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                return try await operation()
            } catch let JamfMapperError.httpStatus(status, _) where status == 401 || status == 403 || status == 404 {
                throw JamfMapperError.httpStatus(status, HTTPURLResponse.localizedString(forStatusCode: status))
            } catch {
                lastError = error
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: delay)
                    delay *= 2
                }
            }
        }
        throw lastError ?? JamfMapperError.invalidResponse
    }

    private func nameForPayload(_ data: Data, fallback: String, rootKey: String) -> String {
        guard let dictionary = data.decodedDictionary() else { return fallback }
        let root = JSONValueReader.unwrapJamfRoot(dictionary, expected: rootKey)
        return JSONValueReader.string(root, keys: ["general.name", "name", "displayName", "packageName", "fileName"]) ?? fallback
    }
}
