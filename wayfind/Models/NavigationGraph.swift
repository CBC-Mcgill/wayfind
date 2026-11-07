//
//  NavigationGraph.swift
//  wayfind
//
//  Navigation graph schema (checklist B1). The router, localization and
//  bundle pipeline all depend on this file, so changes must bump
//  `NavigationGraph.currentSchemaVersion`.
//

import Foundation

// MARK: - Graph

/// The full navigation graph for one building (or the outdoor campus layer).
///
/// Serialized as JSON with snake_case keys. Node IDs are UUIDs that are never
/// reused; a removed node moves to `retiredNodes` so old references still resolve.
nonisolated struct NavigationGraph: Codable, Equatable, Sendable {
    /// Bump when the JSON shape changes in a way old readers can't handle.
    static let currentSchemaVersion = 1

    /// Version of this schema the file was written against.
    var schemaVersion: Int
    /// Version of the map data itself (changes every published bundle).
    var dataVersion: String
    var levels: [Level]
    var nodes: [Node]
    var edges: [Edge]
    /// Retired node IDs. IDs here must never appear in `nodes` again.
    var retiredNodes: [RetiredNode]

    init(
        schemaVersion: Int = NavigationGraph.currentSchemaVersion,
        dataVersion: String,
        levels: [Level] = [],
        nodes: [Node] = [],
        edges: [Edge] = [],
        retiredNodes: [RetiredNode] = []
    ) {
        self.schemaVersion = schemaVersion
        self.dataVersion = dataVersion
        self.levels = levels
        self.nodes = nodes
        self.edges = edges
        self.retiredNodes = retiredNodes
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case dataVersion = "data_version"
        case levels, nodes, edges
        case retiredNodes = "retired_nodes"
    }
}

// MARK: - Levels

/// A floor. `campusElevationM` is a shared vertical reference, so levels in
/// different buildings (and tunnels between them) line up on one scale.
nonisolated struct Level: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Building this level belongs to. `nil` for outdoor/campus-wide levels.
    var buildingID: UUID?
    /// Human-visible floor number (0 = ground, negatives = below grade).
    var ordinal: Int
    var name: String
    /// Floor height above the campus datum, in meters.
    var campusElevationM: Double

    nonisolated enum CodingKeys: String, CodingKey {
        case id
        case buildingID = "building_id"
        case ordinal, name
        case campusElevationM = "campus_elev_m"
    }
}

// MARK: - Nodes

nonisolated struct Node: Codable, Equatable, Identifiable, Sendable {
    /// Stable, never-reused identifier.
    let id: UUID
    var kind: Kind
    /// `true` for nodes inside a building or tunnel, `false` for outdoor nodes.
    var indoor: Bool
    /// Required for indoor nodes; `nil` for outdoor nodes.
    var levelID: UUID?
    var coordinate: Coordinate
    /// Link to the IMDF unit this node represents (rooms, entrances, etc.).
    var imdfUnitID: UUID?
    /// Overrides the level's elevation, e.g. a mid-flight stair landing.
    var campusElevationM: Double?

    nonisolated enum Kind: String, Codable, Sendable {
        case room
        case junction
        case entrance
        case stairLanding = "stair_landing"
        case elevatorLanding = "elevator_landing"
        case rampLanding = "ramp_landing"
        case waypoint
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, kind, indoor
        case levelID = "level_id"
        case coordinate
        case imdfUnitID = "imdf_unit_id"
        case campusElevationM = "campus_elev_m"
    }
}

nonisolated struct Coordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// Record of a node that was removed from the graph.
nonisolated struct RetiredNode: Codable, Equatable, Sendable {
    let id: UUID
    /// Node(s) that replace it, if any (e.g. a room that was split or renumbered).
    var replacedBy: [UUID]
    /// Data version in which the node was retired.
    var retiredInVersion: String

    nonisolated enum CodingKeys: String, CodingKey {
        case id
        case replacedBy = "replaced_by"
        case retiredInVersion = "retired_in_version"
    }
}

// MARK: - Edges

nonisolated struct Edge: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var from: UUID
    var to: UUID
    var type: EdgeType
    /// Walking distance in meters.
    var lengthM: Double
    /// Step-free passable (no stairs, usable by wheelchairs).
    var accessible: Bool
    var access: Access
    /// When the edge is passable. `nil` means always.
    var hours: Hours?
    /// `true` if the edge is inside a building or tunnel.
    var indoor: Bool
    /// `false` for one-way edges (from → to only).
    var bidirectional: Bool

    nonisolated enum CodingKeys: String, CodingKey {
        case id, from, to, type
        case lengthM = "length_m"
        case accessible, access, hours, indoor, bidirectional
    }
}

nonisolated enum EdgeType: String, Codable, Sendable {
    case corridor
    case stair
    case elevator
    case ramp
    case outdoor
    case tunnel
}

/// Who may use an edge.
nonisolated enum Access: String, Codable, Sendable {
    case `public`
    /// Needs a McGill ID card.
    case card
    case staff
}

/// Weekly opening hours. An edge is open if any rule matches the time and
/// no exception closes it.
nonisolated struct Hours: Codable, Equatable, Sendable {
    var rules: [Rule]
    /// Local time zone for all times, e.g. "America/Toronto".
    var timeZone: String

    nonisolated struct Rule: Codable, Equatable, Sendable {
        /// 1 = Monday ... 7 = Sunday (ISO 8601).
        var days: [Int]
        /// "HH:mm", 24-hour. `close` may be "24:00" for end of day.
        var open: String
        var close: String
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case rules
        case timeZone = "time_zone"
    }
}

// MARK: - Coding helpers

nonisolated extension NavigationGraph {
    static func decoder() -> JSONDecoder { JSONDecoder() }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
