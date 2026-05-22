import Foundation

public enum JamfObjectKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case policy
    case smartGroup
    case staticGroup
    case extensionAttribute
    case script
    case category
    case advancedSearch
    case restrictedSoftware
    case package
    case printer
    case dockItem
    case directoryBinding
    case networkSegment
    case computerConfigurationProfile
    case mobileConfigurationProfile
    case macApplication
    case patchPolicy
    case patchTitle
    case patchSoftwareTitleConfiguration
    case jamfConnectProfile
    case computerPrestage
    case appInstaller
    case ddmDeclaration
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .policy: "Policies"
        case .smartGroup: "Smart Groups"
        case .staticGroup: "Static Groups"
        case .extensionAttribute: "Extension Attributes"
        case .script: "Scripts"
        case .category: "Categories"
        case .advancedSearch: "Advanced Searches"
        case .restrictedSoftware: "Restricted Software"
        case .package: "Packages"
        case .printer: "Printers"
        case .dockItem: "Dock Items"
        case .directoryBinding: "Directory Bindings"
        case .networkSegment: "Network Segments"
        case .computerConfigurationProfile: "Computer Config Profiles"
        case .mobileConfigurationProfile: "Mobile Config Profiles"
        case .macApplication: "Mac Apps"
        case .patchPolicy: "Patch Policies"
        case .patchTitle: "Patch Titles"
        case .patchSoftwareTitleConfiguration: "Patch Title Configs"
        case .jamfConnectProfile: "Jamf Connect"
        case .computerPrestage: "Computer Prestages"
        case .appInstaller: "App Installers"
        case .ddmDeclaration: "DDM Declarations"
        case .unknown: "Unknown"
        }
    }

    public var symbolName: String {
        switch self {
        case .policy: "checklist"
        case .smartGroup, .staticGroup: "person.3"
        case .extensionAttribute: "tag"
        case .script: "terminal"
        case .category: "folder"
        case .package: "shippingbox"
        case .printer: "printer"
        case .computerConfigurationProfile, .mobileConfigurationProfile: "slider.horizontal.3"
        case .macApplication, .appInstaller: "app"
        case .patchPolicy, .patchTitle, .patchSoftwareTitleConfiguration: "hammer"
        case .computerPrestage: "macbook"
        case .networkSegment: "network"
        case .ddmDeclaration: "doc.badge.gearshape"
        default: "circle.hexagongrid"
        }
    }

    public var supportsEnabledState: Bool {
        switch self {
        case .policy, .computerConfigurationProfile, .mobileConfigurationProfile, .macApplication, .patchPolicy, .appInstaller, .restrictedSoftware:
            true
        default:
            false
        }
    }

    public var supportsScopeCount: Bool {
        switch self {
        case .policy, .smartGroup, .staticGroup, .computerConfigurationProfile, .mobileConfigurationProfile, .macApplication, .patchPolicy, .appInstaller, .restrictedSoftware, .computerPrestage:
            true
        default:
            false
        }
    }
}

public enum GraphEdgeKind: String, CaseIterable, Codable, Sendable {
    case usesScript = "USES_SCRIPT"
    case installsPackage = "INSTALLS_PACKAGE"
    case scopedToGroup = "SCOPED_TO_GROUP"
    case excludesGroup = "EXCLUDES_GROUP"
    case evaluatesEA = "EVALUATES_EA"
    case nestedSmartGroup = "NESTED_SMART_GROUP"
    case basedOnAdvancedSearch = "BASED_ON_ADVANCED_SEARCH"
    case inCategory = "IN_CATEGORY"
    case referencesNetworkSegment = "REFERENCES_NETWORK_SEGMENT"
    case usesPrinter = "USES_PRINTER"
    case usesDockItem = "USES_DOCK_ITEM"
    case usesDirectoryBinding = "USES_DIRECTORY_BINDING"
    case deploysMacApp = "DEPLOYS_MAC_APP"
    case dependsOnPatchTitle = "DEPENDS_ON_PATCH_TITLE"
    case dependsOnPatchConfiguration = "DEPENDS_ON_PATCH_CONFIGURATION"
    case hasDeclaration = "HAS_DECLARATION"
    case referencesObject = "REFERENCES_OBJECT"
}

public enum APISource: String, Codable, Sendable {
    case classic
    case pro
    case derived
}

public struct GraphNode: Identifiable, Codable, Hashable, Sendable {
    public var id: String { key }

    public let key: String
    public let objectType: JamfObjectKind
    public let objectId: String
    public var name: String
    public var category: String?
    public var isEnabled: Bool?
    public var scopeCount: Int?
    public var lastModified: Date?
    public var rawHash: String?
    public var source: APISource
    public var metadata: [String: String]

    public init(
        key: String,
        objectType: JamfObjectKind,
        objectId: String,
        name: String,
        category: String? = nil,
        isEnabled: Bool? = nil,
        scopeCount: Int? = nil,
        lastModified: Date? = nil,
        rawHash: String? = nil,
        source: APISource,
        metadata: [String: String] = [:]
    ) {
        self.key = key
        self.objectType = objectType
        self.objectId = objectId
        self.name = name
        self.category = category
        self.isEnabled = isEnabled
        self.scopeCount = scopeCount
        self.lastModified = lastModified
        self.rawHash = rawHash
        self.source = source
        self.metadata = metadata
    }
}

public struct GraphEdge: Identifiable, Codable, Hashable, Sendable {
    public var id: String { key }

    public let key: String
    public let fromKey: String
    public let toKey: String
    public let kind: GraphEdgeKind
    public var label: String
    public var evidence: [String: String]

    public init(
        fromKey: String,
        toKey: String,
        kind: GraphEdgeKind,
        label: String? = nil,
        evidence: [String: String] = [:]
    ) {
        self.fromKey = fromKey
        self.toKey = toKey
        self.kind = kind
        self.label = label ?? kind.rawValue
        self.evidence = evidence
        self.key = "\(fromKey)|\(kind.rawValue)|\(toKey)"
    }
}

public struct GraphSnapshot: Codable, Sendable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]

    public init(nodes: [GraphNode] = [], edges: [GraphEdge] = []) {
        self.nodes = nodes
        self.edges = edges
    }
}

public extension GraphNode {
    static func key(for type: JamfObjectKind, id: CustomStringConvertible) -> String {
        "\(type.rawValue):\(id.description)"
    }

    static func unresolvedKey(for type: JamfObjectKind, name: String) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(type.rawValue):name:\(normalized.stableIdentifier)"
    }
}
