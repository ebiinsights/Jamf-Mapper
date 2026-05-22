import Foundation
import GRDB

public final class DatabaseStore: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: databaseURL.path)
        try Self.migrator.migrate(dbQueue)
    }

    public static func defaultDatabaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("JamfMapper", isDirectory: true).appendingPathComponent("JamfMapper.sqlite")
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "connections", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("base_url", .text).notNull()
                table.column("client_id", .text).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "snapshots", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("connection_id", .text).notNull().indexed()
                table.column("started_at", .datetime).notNull()
                table.column("completed_at", .datetime)
                table.column("status", .text).notNull()
                table.column("jamf_version", .text)
                table.column("error_summary", .text)
                table.foreignKey(["connection_id"], references: "connections", onDelete: .cascade)
            }

            try db.create(table: "crawl_tasks", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("snapshot_id", .text).notNull().indexed()
                table.column("object_type", .text).notNull()
                table.column("object_id", .text)
                table.column("endpoint", .text).notNull()
                table.column("status", .text).notNull()
                table.column("attempt_count", .integer).notNull().defaults(to: 0)
                table.column("last_error", .text)
                table.column("updated_at", .datetime).notNull()
                table.foreignKey(["snapshot_id"], references: "snapshots", onDelete: .cascade)
            }

            try db.create(table: "raw_objects", ifNotExists: true) { table in
                table.column("snapshot_id", .text).notNull()
                table.column("object_type", .text).notNull()
                table.column("object_id", .text).notNull()
                table.column("name", .text).notNull()
                table.column("source_api", .text).notNull()
                table.column("endpoint", .text).notNull()
                table.column("payload", .blob).notNull()
                table.column("content_hash", .text).notNull()
                table.column("fetched_at", .datetime).notNull()
                table.primaryKey(["snapshot_id", "object_type", "object_id"])
                table.foreignKey(["snapshot_id"], references: "snapshots", onDelete: .cascade)
            }
            try db.create(index: "idx_raw_objects_snapshot_type", on: "raw_objects", columns: ["snapshot_id", "object_type"], ifNotExists: true)

            try db.create(table: "nodes", ifNotExists: true) { table in
                table.column("snapshot_id", .text).notNull()
                table.column("key", .text).notNull()
                table.column("object_type", .text).notNull()
                table.column("object_id", .text).notNull()
                table.column("name", .text).notNull()
                table.column("category", .text)
                table.column("enabled", .boolean)
                table.column("scope_count", .integer)
                table.column("last_modified", .datetime)
                table.column("raw_hash", .text)
                table.column("source_api", .text).notNull()
                table.column("metadata_json", .text).notNull().defaults(to: "{}")
                table.primaryKey(["snapshot_id", "key"])
                table.foreignKey(["snapshot_id"], references: "snapshots", onDelete: .cascade)
            }
            try db.create(index: "idx_nodes_snapshot_type", on: "nodes", columns: ["snapshot_id", "object_type"], ifNotExists: true)
            try db.create(index: "idx_nodes_snapshot_object", on: "nodes", columns: ["snapshot_id", "object_type", "object_id"], unique: true, ifNotExists: true)

            try db.create(table: "edges", ifNotExists: true) { table in
                table.column("snapshot_id", .text).notNull()
                table.column("key", .text).notNull()
                table.column("from_key", .text).notNull()
                table.column("to_key", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("label", .text).notNull()
                table.column("evidence_json", .text).notNull().defaults(to: "{}")
                table.primaryKey(["snapshot_id", "key"])
                table.foreignKey(["snapshot_id"], references: "snapshots", onDelete: .cascade)
            }
            try db.create(index: "idx_edges_from", on: "edges", columns: ["snapshot_id", "from_key"], ifNotExists: true)
            try db.create(index: "idx_edges_to", on: "edges", columns: ["snapshot_id", "to_key"], ifNotExists: true)

            try db.create(table: "analysis_findings", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("snapshot_id", .text).notNull().indexed()
                table.column("finding_type", .text).notNull()
                table.column("severity", .text).notNull()
                table.column("node_key", .text)
                table.column("title", .text).notNull()
                table.column("detail", .text).notNull()
                table.column("metadata_json", .text).notNull().defaults(to: "{}")
                table.foreignKey(["snapshot_id"], references: "snapshots", onDelete: .cascade)
            }
        }
        return migrator
    }
}

public extension DatabaseStore {
    func upsertConnection(_ connection: ConnectionProfile) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO connections (id, name, base_url, client_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    base_url = excluded.base_url,
                    client_id = excluded.client_id,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    connection.id.uuidString,
                    connection.name,
                    connection.baseURL.absoluteString,
                    connection.clientID,
                    connection.createdAt,
                    connection.updatedAt
                ]
            )
        }
    }

    func connections() throws -> [ConnectionProfile] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM connections ORDER BY name COLLATE NOCASE").compactMap { row in
                guard
                    let id = UUID(uuidString: row["id"]),
                    let url = URL(string: row["base_url"])
                else { return nil }
                return ConnectionProfile(
                    id: id,
                    name: row["name"],
                    baseURL: url,
                    clientID: row["client_id"],
                    createdAt: row["created_at"],
                    updatedAt: row["updated_at"]
                )
            }
        }
    }

    func deleteConnection(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "DELETE FROM connections WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func insertSnapshot(_ snapshot: CrawlSnapshotRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO snapshots
                (id, connection_id, started_at, completed_at, status, jamf_version, error_summary)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    snapshot.id.uuidString,
                    snapshot.connectionID.uuidString,
                    snapshot.startedAt,
                    snapshot.completedAt,
                    snapshot.status.rawValue,
                    snapshot.jamfVersion,
                    snapshot.errorSummary
                ]
            )
        }
    }

    func updateSnapshotStatus(_ snapshotID: UUID, status: CrawlStatus, completedAt: Date? = nil, jamfVersion: String? = nil, errorSummary: String? = nil) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE snapshots SET status = ?, completed_at = ?, jamf_version = COALESCE(?, jamf_version), error_summary = ? WHERE id = ?",
                arguments: [status.rawValue, completedAt, jamfVersion, errorSummary, snapshotID.uuidString]
            )
        }
    }

    func latestSnapshotID(for connectionID: UUID) throws -> UUID? {
        try dbQueue.read { db in
            let value = try String.fetchOne(
                db,
                sql: "SELECT id FROM snapshots WHERE connection_id = ? ORDER BY started_at DESC LIMIT 1",
                arguments: [connectionID.uuidString]
            )
            return value.flatMap(UUID.init(uuidString:))
        }
    }

    func insertRawObjects(_ rawObjects: [RawJamfObject]) throws {
        guard !rawObjects.isEmpty else { return }
        try dbQueue.write { db in
            for object in rawObjects {
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO raw_objects
                    (snapshot_id, object_type, object_id, name, source_api, endpoint, payload, content_hash, fetched_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        object.snapshotID.uuidString,
                        object.objectType.rawValue,
                        object.objectID,
                        object.name,
                        object.source.rawValue,
                        object.endpoint,
                        object.payload,
                        object.contentHash,
                        object.fetchedAt
                    ]
                )
            }
        }
    }

    func rawObjects(snapshotID: UUID) throws -> [RawJamfObject] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM raw_objects WHERE snapshot_id = ?", arguments: [snapshotID.uuidString]).compactMap { row in
                guard let type = JamfObjectKind(rawValue: row["object_type"]), let source = APISource(rawValue: row["source_api"]) else {
                    return nil
                }
                return RawJamfObject(
                    snapshotID: snapshotID,
                    objectType: type,
                    objectID: row["object_id"],
                    name: row["name"],
                    source: source,
                    endpoint: row["endpoint"],
                    payload: row["payload"],
                    fetchedAt: row["fetched_at"]
                )
            }
        }
    }

    func replaceGraph(snapshotID: UUID, graph: GraphSnapshot) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM edges WHERE snapshot_id = ?", arguments: [snapshotID.uuidString])
            try db.execute(sql: "DELETE FROM nodes WHERE snapshot_id = ?", arguments: [snapshotID.uuidString])

            let encoder = JSONEncoder()
            for node in graph.nodes {
                let metadataData = try encoder.encode(node.metadata)
                let metadata = String(data: metadataData, encoding: .utf8) ?? "{}"
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO nodes
                    (snapshot_id, key, object_type, object_id, name, category, enabled, scope_count, last_modified, raw_hash, source_api, metadata_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        snapshotID.uuidString,
                        node.key,
                        node.objectType.rawValue,
                        node.objectId,
                        node.name,
                        node.category,
                        node.isEnabled,
                        node.scopeCount,
                        node.lastModified,
                        node.rawHash,
                        node.source.rawValue,
                        metadata
                    ]
                )
            }

            for edge in graph.edges {
                let evidenceData = try encoder.encode(edge.evidence)
                let evidence = String(data: evidenceData, encoding: .utf8) ?? "{}"
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO edges
                    (snapshot_id, key, from_key, to_key, kind, label, evidence_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        snapshotID.uuidString,
                        edge.key,
                        edge.fromKey,
                        edge.toKey,
                        edge.kind.rawValue,
                        edge.label,
                        evidence
                    ]
                )
            }
        }
    }

    func graph(snapshotID: UUID) throws -> GraphSnapshot {
        try dbQueue.read { db in
            let decoder = JSONDecoder()
            let nodes = try Row.fetchAll(db, sql: "SELECT * FROM nodes WHERE snapshot_id = ?", arguments: [snapshotID.uuidString]).compactMap { row -> GraphNode? in
                guard let type = JamfObjectKind(rawValue: row["object_type"]), let source = APISource(rawValue: row["source_api"]) else {
                    return nil
                }
                let metadataString: String = row["metadata_json"]
                let metadata = (try? decoder.decode([String: String].self, from: Data(metadataString.utf8))) ?? [:]
                return GraphNode(
                    key: row["key"],
                    objectType: type,
                    objectId: row["object_id"],
                    name: row["name"],
                    category: row["category"],
                    isEnabled: row["enabled"],
                    scopeCount: row["scope_count"],
                    lastModified: row["last_modified"],
                    rawHash: row["raw_hash"],
                    source: source,
                    metadata: metadata
                )
            }

            let edges = try Row.fetchAll(db, sql: "SELECT * FROM edges WHERE snapshot_id = ?", arguments: [snapshotID.uuidString]).compactMap { row -> GraphEdge? in
                guard let kind = GraphEdgeKind(rawValue: row["kind"]) else { return nil }
                let evidenceString: String = row["evidence_json"]
                let evidence = (try? decoder.decode([String: String].self, from: Data(evidenceString.utf8))) ?? [:]
                return GraphEdge(
                    fromKey: row["from_key"],
                    toKey: row["to_key"],
                    kind: kind,
                    label: row["label"],
                    evidence: evidence
                )
            }
            return GraphSnapshot(nodes: nodes, edges: edges)
        }
    }
}
