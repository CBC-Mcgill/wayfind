//
//  wayfindTests.swift
//  wayfindTests
//
//  Created by Parsa Rahimnia on 2026-11-04.
//

import Foundation
import Testing
@testable import wayfind

// MARK: - Navigation graph

struct NavigationGraphTests {
    @Test func jsonRoundTrip() throws {
        let levelID = UUID()
        let a = Node(id: UUID(), kind: .room, indoor: true, levelID: levelID,
                     coordinate: .init(latitude: 45.5048, longitude: -73.5772),
                     imdfUnitID: UUID(), campusElevationM: nil)
        let b = Node(id: UUID(), kind: .elevatorLanding, indoor: true, levelID: levelID,
                     coordinate: .init(latitude: 45.5049, longitude: -73.5773),
                     imdfUnitID: nil, campusElevationM: 62.5)
        let edge = Edge(
            id: UUID(), from: a.id, to: b.id, type: .elevator, lengthM: 12.5,
            accessible: true, access: .card,
            hours: Hours(rules: [.init(days: [1, 2, 3, 4, 5], open: "07:00", close: "22:00")],
                         timeZone: "America/Toronto"),
            indoor: true, bidirectional: true)
        let graph = NavigationGraph(
            dataVersion: "2026.11.04",
            levels: [Level(id: levelID, buildingID: UUID(), ordinal: 0, name: "Ground", campusElevationM: 60)],
            nodes: [a, b],
            edges: [edge],
            retiredNodes: [RetiredNode(id: UUID(), replacedBy: [a.id], retiredInVersion: "2026.10.01")])

        let data = try NavigationGraph.encoder().encode(graph)
        #expect(try NavigationGraph.decoder().decode(NavigationGraph.self, from: data) == graph)
    }

    @Test func jsonKeysMatchTheSchema() throws {
        let graph = NavigationGraph(dataVersion: "1")
        let json = String(decoding: try NavigationGraph.encoder().encode(graph), as: UTF8.self)
        #expect(json.contains("\"schema_version\" : \(NavigationGraph.currentSchemaVersion)"))
        #expect(json.contains("\"retired_nodes\""))
    }

    @Test func edgeAndAccessRawValuesAreStable() {
        // These strings are persisted in published bundles; changing them breaks old data.
        #expect(EdgeType.tunnel.rawValue == "tunnel")
        #expect(Access.public.rawValue == "public")
        #expect(Node.Kind.stairLanding.rawValue == "stair_landing")
    }
}
