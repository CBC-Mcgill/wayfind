//
//  AliasTable.swift
//  wayfind
//
//  Alias table schema (checklist B2). McGill rooms have three naming systems:
//  the IMDF unit, the registrar code in schedules (.ics), and the text printed
//  on door plates (read by OCR). One table per building maps them together, and
//  both the schedule parser and the sign reader resolve rooms through it.
//

import Foundation

/// Room-code crosswalk for one building. Serialized as JSON with snake_case keys.
///
/// ## Matching rules
/// Lookups never compare raw strings. Both the query and every stored code are
/// first normalized (see `AliasTable.normalize(_:)`):
/// - Uppercase, diacritics removed (so "Salle É-12" matches "SALLE E-12").
/// - Whitespace, hyphens, dots and underscores removed ("ENGMC 304" == "ENGMC-304").
/// - Leading zeros dropped from digit runs ("MD 0021" == "MD21").
///
/// Because of that, `sign_variants` only needs to list *genuinely different*
/// spellings, not formatting differences.
///
/// ## Ranges
/// Do not store ranges ("304-306"). A sign that covers several rooms gets one
/// entry per room, each listing the shared sign text in `sign_variants`. A
/// lookup that matches more than one entry is *ambiguous*; the caller must
/// resolve it (e.g. ask the user to confirm) rather than guess.
///
/// ## Variants
/// - `registrar_code`: exactly one per unit; unique within the table.
/// - `sign_variants`: any number of strings; may overlap between units (ambiguous).
/// - `label_fr`: French display name, spoken and shown in FR mode. Optional.
///
/// ## Example 1: one-to-one room
/// ```json
/// {
///   "imdf_unit_id": "6f1c1c1e-2d0b-4a53-9a43-0c5b7f3f9a10",
///   "registrar_code": "ENGMC 304",
///   "sign_variants": ["MC 304", "304"],
///   "label_fr": "Salle 304, pavillon McConnell"
/// }
/// ```
/// The schedule says "ENGMC 304", the door plate says "304" or "MC 304";
/// all three resolve to the same unit.
///
/// ## Example 2: shared sign (range)
/// A single plate reads "MD 21-22" and covers two lab rooms:
/// ```json
/// [
///   { "imdf_unit_id": "a1b2…01", "registrar_code": "MD 21",
///     "sign_variants": ["MD 21-22", "MD 21/22"], "label_fr": null },
///   { "imdf_unit_id": "a1b2…02", "registrar_code": "MD 22",
///     "sign_variants": ["MD 21-22", "MD 21/22"], "label_fr": null }
/// ]
/// ```
/// Searching "MD 21-22" matches both entries, so it is ambiguous. Searching
/// "MD 21" from a schedule matches only the first (registrar codes are unique).
nonisolated struct AliasTable: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    /// IMDF building ID this table covers.
    var buildingID: UUID
    var entries: [Entry]

    init(
        schemaVersion: Int = AliasTable.currentSchemaVersion,
        buildingID: UUID,
        entries: [Entry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.buildingID = buildingID
        self.entries = entries
    }

    nonisolated struct Entry: Codable, Equatable, Sendable {
        var imdfUnitID: UUID
        var registrarCode: String
        var signVariants: [String]
        var labelFR: String?

        nonisolated enum CodingKeys: String, CodingKey {
            case imdfUnitID = "imdf_unit_id"
            case registrarCode = "registrar_code"
            case signVariants = "sign_variants"
            case labelFR = "label_fr"
        }
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case buildingID = "building_id"
        case entries
    }
}

// MARK: - Lookup

nonisolated extension AliasTable {
    /// Result of resolving a room string.
    nonisolated enum Resolution: Equatable, Sendable {
        case unique(Entry)
        /// More than one unit matched; the caller must disambiguate.
        case ambiguous([Entry])
        case notFound
    }

    /// Resolves text from a schedule or a sign to a unit.
    /// An exact registrar-code match always wins over sign variants.
    func resolve(_ text: String) -> Resolution {
        let key = Self.normalize(text)
        guard !key.isEmpty else { return .notFound }

        if let entry = entries.first(where: { Self.normalize($0.registrarCode) == key }) {
            return .unique(entry)
        }

        let matches = entries.filter { entry in
            entry.signVariants.contains { Self.normalize($0) == key }
        }
        switch matches.count {
        case 0: return .notFound
        case 1: return .unique(matches[0])
        default: return .ambiguous(matches)
        }
    }

    /// Canonical form used for all comparisons (see the type documentation).
    static func normalize(_ text: String) -> String {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_CA"))
            .uppercased()
        let stripped = folded.filter { !$0.isWhitespace && !"-._".contains($0) }
        return dropLeadingZeros(in: stripped)
    }

    /// Removes leading zeros from every run of digits ("MD0021" -> "MD21").
    private static func dropLeadingZeros(in text: String) -> String {
        var result = ""
        var digitRun = ""
        func flush() {
            let trimmed = digitRun.drop(while: { $0 == "0" })
            result += trimmed.isEmpty && !digitRun.isEmpty ? "0" : String(trimmed)
            digitRun = ""
        }
        for character in text {
            if character.isASCII && character.isNumber {
                digitRun.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }
}
