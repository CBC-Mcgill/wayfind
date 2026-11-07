//
//  wayfindTests.swift
//  wayfindTests
//
//  Created by Parsa Rahimnia on 2026-11-04.
//

import Foundation
import Testing
@testable import wayfind

// MARK: - Alias table

struct AliasTableTests {
    private let mc304 = UUID()
    private let md21 = UUID()
    private let md22 = UUID()

    private func makeTable() -> AliasTable {
        AliasTable(buildingID: UUID(), entries: [
            .init(imdfUnitID: mc304, registrarCode: "ENGMC 304", signVariants: ["MC 304", "304"], labelFR: "Salle 304"),
            .init(imdfUnitID: md21, registrarCode: "MD 21", signVariants: ["MD 21-22"], labelFR: nil),
            .init(imdfUnitID: md22, registrarCode: "MD 22", signVariants: ["MD 21-22"], labelFR: nil),
        ])
    }

    @Test func normalizationIgnoresFormatting() {
        #expect(AliasTable.normalize("engmc-304") == AliasTable.normalize("ENGMC 304"))
        #expect(AliasTable.normalize("MD 0021") == AliasTable.normalize("MD21"))
        #expect(AliasTable.normalize("Salle É-12") == AliasTable.normalize("SALLE E12"))
        #expect(AliasTable.normalize("MD 0") == "MD0")
    }

    @Test func registrarCodeResolvesUniquely() {
        guard case .unique(let entry) = makeTable().resolve("engmc304") else {
            Issue.record("expected a unique match")
            return
        }
        #expect(entry.imdfUnitID == mc304)
    }

    @Test func signVariantResolvesToSameUnit() {
        guard case .unique(let entry) = makeTable().resolve("MC 304") else {
            Issue.record("expected a unique match")
            return
        }
        #expect(entry.imdfUnitID == mc304)
    }

    @Test func sharedSignIsAmbiguous() {
        guard case .ambiguous(let entries) = makeTable().resolve("MD 21-22") else {
            Issue.record("expected an ambiguous match")
            return
        }
        #expect(Set(entries.map(\.imdfUnitID)) == [md21, md22])
    }

    @Test func registrarCodeBeatsSharedSign() {
        guard case .unique(let entry) = makeTable().resolve("MD 21") else {
            Issue.record("expected a unique match")
            return
        }
        #expect(entry.imdfUnitID == md21)
    }

    @Test func unknownAndEmptyInputAreNotFound() {
        #expect(makeTable().resolve("XYZ 999") == .notFound)
        #expect(makeTable().resolve("  ") == .notFound)
    }

    @Test func jsonRoundTripUsesSnakeCaseKeys() throws {
        let table = makeTable()
        let data = try JSONEncoder().encode(table)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("registrar_code"))
        #expect(json.contains("sign_variants"))
        #expect(try JSONDecoder().decode(AliasTable.self, from: data) == table)
    }
}

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
