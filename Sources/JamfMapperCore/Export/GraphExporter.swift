import Foundation
import ZIPFoundation

public struct GraphExporter: Sendable {
    public init() {}

    public func exportJSON(graph: GraphSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(graph)
        try data.write(to: url, options: .atomic)
    }

    public func exportCSV(graph: GraphSnapshot, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try nodesCSV(graph.nodes).write(to: directory.appendingPathComponent("nodes.csv"), atomically: true, encoding: .utf8)
        try edgesCSV(graph.edges).write(to: directory.appendingPathComponent("edges.csv"), atomically: true, encoding: .utf8)
    }

    public func exportBundle(graph: GraphSnapshot, metadata: [String: String], to url: URL) throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("JamfMapper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let graphURL = tempDirectory.appendingPathComponent("graph.json")
        try exportJSON(graph: graph, to: graphURL)
        let metadataURL = tempDirectory.appendingPathComponent("metadata.json")
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: metadataURL)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addEntry(with: "graph.json", fileURL: graphURL)
        try archive.addEntry(with: "metadata.json", fileURL: metadataURL)
    }

    private func nodesCSV(_ nodes: [GraphNode]) -> String {
        var rows = ["key,type,id,name,category,enabled,scope_count,raw_hash,source"]
        rows += nodes.map { node in
            [
                node.key,
                node.objectType.rawValue,
                node.objectId,
                node.name,
                node.category ?? "",
                node.isEnabled.map(String.init) ?? "",
                node.scopeCount.map(String.init) ?? "",
                node.rawHash ?? "",
                node.source.rawValue
            ].map(csvEscape).joined(separator: ",")
        }
        return rows.joined(separator: "\n")
    }

    private func edgesCSV(_ edges: [GraphEdge]) -> String {
        var rows = ["key,from_key,to_key,kind,label"]
        rows += edges.map { edge in
            [edge.key, edge.fromKey, edge.toKey, edge.kind.rawValue, edge.label].map(csvEscape).joined(separator: ",")
        }
        return rows.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
