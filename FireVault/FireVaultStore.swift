//
//  FireVaultStore.swift
//  FireVault
//
//  Native application and demo-data authority for Build 1.05.05.
//

import Foundation
import Combine
import CoreLocation
import MapKit
import UIKit

struct FireVaultCSVImportResult: Equatable {
    let added: Int
    let updated: Int
    let skipped: Int
    let totalRows: Int
    let messages: [String]
}

@MainActor
final class FireVaultStore: ObservableObject {
    @Published var accounts: [FireVaultWorkspaceAccount]
    @Published var selectedAccountID: String?
    @Published var selectedTab: FireVaultShellTab = .nearby
    @Published var locationStatus: String
    @Published private(set) var demoMode: Bool

    private let defaults: UserDefaults
    private let demoCoordinate = CLLocationCoordinate2D(latitude: 43.6150, longitude: -116.2023)

    private enum Key {
        static let demoMode = "firevault.native.demo-mode.v1"
        static let demoAccounts = "firevault.native.demo-accounts.v1"
        static let productionAccounts = "firevault.native.production-accounts.v1"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let activeDemoMode = defaults.object(forKey: Key.demoMode) as? Bool ?? true
        demoMode = activeDemoMode
        locationStatus = activeDemoMode ? "Demo location ready" : "Location ready"

        if activeDemoMode {
            accounts = Self.savedAccounts(defaults: defaults, key: Key.demoAccounts) ?? Self.demoAccounts
        } else {
            accounts = Self.savedAccounts(defaults: defaults, key: Key.productionAccounts) ?? []
        }
    }

    var selectedAccount: FireVaultWorkspaceAccount? {
        guard let selectedAccountID else { return nil }
        return accounts.first { $0.id == selectedAccountID }
    }

    var appPayload: FireVaultAppPayload {
        let nativeAccounts = accounts.map(Self.nativeAccount)
        let userLocation = CLLocation(latitude: demoCoordinate.latitude, longitude: demoCoordinate.longitude)
        let nearby = accounts.compactMap { account -> FireVaultNativeNearbyAccount? in
            guard let coordinate = account.coordinate else { return nil }
            let meters = userLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            return .init(
                id: account.id,
                account: Self.nativeAccount(account),
                distanceMeters: meters,
                distanceLabel: Self.distanceLabel(meters)
            )
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }

        return .init(
            build: FireVaultVersionInfo().version,
            initialTab: selectedTab.rawValue,
            demoMode: demoMode,
            today: Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
            technicianName: demoMode ? "Demo Technician" : "Field Technician",
            locationStatus: locationStatus,
            accounts: nativeAccounts,
            nearby: nearby,
            settingsGroups: []
        )
    }

    func openAccount(_ id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        selectedAccountID = id
    }

    func closeAccount(to tab: FireVaultShellTab? = nil) {
        selectedAccountID = nil
        if let tab { selectedTab = tab }
    }

    func refreshNearby() {
        locationStatus = "Updated \(Date().formatted(date: .omitted, time: .shortened))"
    }

    func toggleFavorite(_ id: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].favorite.toggle()
        persist()
    }

    func addAccount() {
        let number = accounts.count + 1
        accounts.append(
            .init(
                id: UUID().uuidString,
                name: demoMode ? "Demo Account \(number)" : "New Account \(number)",
                address: "\(100 + number) Native Way, Boise, ID 83702",
                category: "Commercial",
                accountId: "\(demoMode ? "DEMO" : "NEW")-\(number.formatted(.number.precision(.integerLength(2))))",
                phone: "20855501\(number.formatted(.number.precision(.integerLength(2))))",
                favorite: false,
                latitude: 43.615 + Double(number) * 0.002,
                longitude: -116.202 + Double(number) * 0.002,
                tags: [demoMode ? "Native Demo" : "Native"],
                notes: [],
                documents: [],
                equipment: [],
                locations: [],
                recent: []
            )
        )
        persist()
    }

    func addNote(to accountID: String) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let note = FireVaultWorkspaceNote(
            id: UUID().uuidString,
            title: "Native field note",
            text: "Demo note created in the native iOS application.",
            date: Date().formatted(date: .abbreviated, time: .shortened)
        )
        accounts[index].notes.insert(note, at: 0)
        accounts[index].recent.insert(
            .init(id: UUID().uuidString, title: note.title, subtitle: note.text, kind: "note", date: "Now"),
            at: 0
        )
        persist()
    }

    func addDocument(to accountID: String, scan: Bool) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let document = FireVaultWorkspaceDocument(
            id: UUID().uuidString,
            title: scan ? "Native document scan" : "Native file",
            subtitle: scan ? "Scan placeholder" : "File placeholder",
            kind: scan ? "scan" : "file",
            date: "Today"
        )
        accounts[index].documents.insert(document, at: 0)
        persist()
    }

    func addEquipment(to accountID: String) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].equipment.append(
            .init(id: UUID().uuidString, title: "New native equipment", subtitle: "Demo equipment record", status: "Draft")
        )
        persist()
    }

    func addLocation(to accountID: String) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let account = accounts[index]
        accounts[index].locations.append(
            .init(
                id: UUID().uuidString,
                label: "New field location",
                subtitle: "Native demo pin",
                type: "Other",
                plusCode: "",
                latitude: account.latitude,
                longitude: account.longitude
            )
        )
        persist()
    }

    func openRoute(for account: FireVaultWorkspaceAccount) {
        guard let coordinate = account.coordinate else { return }
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = account.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel:\(digits)") else { return }
        UIApplication.shared.open(url)
    }

    func resetDemo() {
        guard demoMode else { return }
        accounts = Self.demoAccounts
        selectedAccountID = nil
        defaults.removeObject(forKey: Key.demoAccounts)
    }

    func exitDemoMode() {
        guard demoMode else { return }
        selectedAccountID = nil
        demoMode = false
        defaults.set(false, forKey: Key.demoMode)
        accounts = Self.savedAccounts(defaults: defaults, key: Key.productionAccounts) ?? []
        locationStatus = "Location ready"
    }

    func enterDemoMode() {
        guard !demoMode else { return }
        selectedAccountID = nil
        demoMode = true
        defaults.set(true, forKey: Key.demoMode)
        accounts = Self.savedAccounts(defaults: defaults, key: Key.demoAccounts) ?? Self.demoAccounts
        locationStatus = "Demo location ready"
    }

    func importAccountsCSV(_ data: Data) throws -> FireVaultCSVImportResult {
        guard var source = Self.decodeCSV(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        source = Self.normalizedLineEndings(source)

        var explicitDelimiter: Character?
        if let firstBreak = source.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let firstLine = source[..<firstBreak]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
            if firstLine.lowercased().hasPrefix("sep="),
               let separator = firstLine.dropFirst(4).first {
                explicitDelimiter = separator
                var contentStart = source.index(after: firstBreak)
                if source[firstBreak] == "\r",
                   contentStart < source.endIndex,
                   source[contentStart] == "\n" {
                    contentStart = source.index(after: contentStart)
                }
                source = String(source[contentStart...])
            }
        }

        let rows = Self.parseCSV(source, delimiter: explicitDelimiter)
        guard let rawHeaders = rows.first, rawHeaders.count > 0 else {
            return .init(added: 0, updated: 0, skipped: 0, totalRows: 0, messages: ["The CSV file is empty."])
        }

        let headers = rawHeaders.map(Self.normalizedHeader)
        let nameAliases = [
            "name", "account name", "site name", "site", "customer name", "customer",
            "company name", "company", "business name", "business", "client name", "client",
            "property name", "property", "premise name", "premise", "location name", "location",
            "display name", "description"
        ]
        let records = rows.dropFirst().filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        var added = 0
        var updated = 0
        var skipped = 0
        var messages: [String] = []
        var seenAccountIDs: Set<String> = []

        let normalizedNameAliases = nameAliases.map(Self.normalizedHeader)
        let nameColumn = headers.firstIndex(where: normalizedNameAliases.contains)
            ?? headers.firstIndex(where: Self.isLikelyNameHeader)
            ?? 0
        if !headers.indices.contains(nameColumn) {
            return .init(added: 0, updated: 0, skipped: records.count, totalRows: records.count, messages: ["The CSV has no usable columns."])
        }
        if !normalizedNameAliases.contains(headers[nameColumn]) {
            let label = rawHeaders[nameColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            messages.append("Used “\(label.isEmpty ? "Column 1" : label)” as the account-name column.")
        }

        func value(_ aliases: [String], from row: [String]) -> String {
            for alias in aliases {
                if let index = headers.firstIndex(of: Self.normalizedHeader(alias)), index < row.count {
                    let result = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !result.isEmpty { return result }
                }
            }
            return ""
        }

        for (offset, row) in records.enumerated() {
            let rowNumber = offset + 2
            let name = nameColumn < row.count
                ? row[nameColumn].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            guard !name.isEmpty else {
                skipped += 1
                messages.append("Row \(rowNumber): missing account name.")
                continue
            }

            let accountID = Self.canonicalAccountID(value([
                "account id", "account number", "account no", "customer id", "customer number",
                "site id", "site number", "client id", "client number"
            ], from: row))
            if !accountID.isEmpty, !seenAccountIDs.insert(accountID).inserted {
                skipped += 1
                messages.append("Row \(rowNumber): duplicate Account Id \(accountID) appears more than once in this file.")
                continue
            }
            let street = value([
                "address", "address 1", "address line 1", "street", "street address",
                "site address", "service address", "location address", "property address"
            ], from: row)
            let city = value(["city"], from: row)
            let state = value(["state", "province"], from: row)
            let zip = value(["zip", "zip code", "postal code", "postcode"], from: row)
            let address = [street, city, state, zip].filter { !$0.isEmpty }.joined(separator: ", ")
            let category = value(["category", "type", "site group num", "sitegroupnum"], from: row)
            let phone = value([
                "phone", "phone number", "telephone", "site phone", "customer phone", "device phone"
            ], from: row)
            let latitude = Double(value(["latitude", "lat"], from: row))
            let longitude = Double(value(["longitude", "lng", "lon"], from: row))

            let existingIndex = accounts.firstIndex {
                if !accountID.isEmpty {
                    return Self.canonicalAccountID($0.accountId) == accountID
                }
                return $0.name.caseInsensitiveCompare(name) == .orderedSame &&
                    $0.address.caseInsensitiveCompare(address) == .orderedSame
            }
            if let existingIndex {
                accounts[existingIndex].name = name
                accounts[existingIndex].address = address.isEmpty ? accounts[existingIndex].address : address
                accounts[existingIndex].category = category.isEmpty ? accounts[existingIndex].category : category
                accounts[existingIndex].accountId = accountID.isEmpty ? accounts[existingIndex].accountId : accountID
                accounts[existingIndex].phone = phone.isEmpty ? accounts[existingIndex].phone : phone
                if let latitude { accounts[existingIndex].latitude = latitude }
                if let longitude { accounts[existingIndex].longitude = longitude }
                if !accounts[existingIndex].tags.contains("CSV Import") {
                    accounts[existingIndex].tags.append("CSV Import")
                }
                updated += 1
                continue
            }

            accounts.append(
                .init(
                    id: UUID().uuidString,
                    name: name,
                    address: address.isEmpty ? "No address supplied" : address,
                    category: category,
                    accountId: accountID,
                    phone: phone,
                    favorite: false,
                    latitude: latitude,
                    longitude: longitude,
                    tags: ["CSV Import"],
                    notes: [], documents: [], equipment: [], locations: [], recent: []
                )
            )
            added += 1
        }

        persist()
        if updated > 0 {
            messages.insert("\(updated) existing account\(updated == 1 ? "" : "s") updated by Account Id.", at: 0)
        }
        return .init(
            added: added,
            updated: updated,
            skipped: skipped,
            totalRows: records.count,
            messages: Array(messages.prefix(12))
        )
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: demoMode ? Key.demoAccounts : Key.productionAccounts)
    }

    private static func savedAccounts(defaults: UserDefaults, key: String) -> [FireVaultWorkspaceAccount]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([FireVaultWorkspaceAccount].self, from: data)
    }

    private static func decodeCSV(_ data: Data) -> String? {
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252, .macOSRoman] {
            if let value = String(data: data, encoding: encoding) {
                return value
            }
        }
        return nil
    }

    private static func nativeAccount(_ account: FireVaultWorkspaceAccount) -> FireVaultNativeAccount {
        .init(
            id: account.id,
            name: account.name,
            address: account.address,
            accountId: account.accountId,
            category: account.category,
            phone: account.phone,
            favorite: account.favorite,
            latitude: account.latitude,
            longitude: account.longitude,
            recentText: account.recent.first?.date ?? ""
        )
    }

    private static func distanceLabel(_ meters: Double) -> String {
        let miles = meters / 1_609.344
        return miles < 0.1 ? "\(Int(meters.rounded())) m" : "\(miles.formatted(.number.precision(.fractionLength(1)))) mi"
    }

    private static func normalizedHeader(_ value: String) -> String {
        let lowered = value
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
            .lowercased()
        return String(lowered.filter { $0.isLetter || $0.isNumber })
    }

    private static func isLikelyNameHeader(_ header: String) -> Bool {
        ["name", "customer", "site", "company", "business", "client", "property", "premise", "location"]
            .contains { header.contains($0) }
    }

    private static func canonicalAccountID(_ value: String) -> String {
        let hyphens = Set("‐‑‒–—―−﹘﹣－")
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "'" })
            .map { character in
                hyphens.contains(character) ? "-" : String(character).uppercased()
            }
            .joined()
            .filter { !$0.isWhitespace }
    }

    static func parseCSV(_ source: String, delimiter explicitDelimiter: Character? = nil) -> [[String]] {
        let source = normalizedLineEndings(source)
        let delimiter = explicitDelimiter ?? detectedDelimiter(in: source)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            if character == "\"" {
                if quoted, next < source.endIndex, source[next] == "\"" {
                    field.append("\"")
                    index = source.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == delimiter, !quoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !quoted {
                if character == "\r", next < source.endIndex, source[next] == "\n" {
                    index = source.index(after: next)
                } else {
                    index = next
                }
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
                continue
            } else {
                field.append(character)
            }
            index = next
        }

        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }

    private static func normalizedLineEndings(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func detectedDelimiter(in source: String) -> Character {
        let candidates: [Character] = [",", ";", "\t", "|"]
        var counts = Dictionary(uniqueKeysWithValues: candidates.map { ($0, 0) })
        var quoted = false

        for character in source {
            if character == "\"" {
                quoted.toggle()
            } else if !quoted, (character == "\n" || character == "\r") {
                break
            } else if !quoted, counts[character] != nil {
                counts[character, default: 0] += 1
            }
        }

        return candidates.max { lhs, rhs in
            counts[lhs, default: 0] < counts[rhs, default: 0]
        }.flatMap { counts[$0, default: 0] > 0 ? $0 : nil } ?? ","
    }

    static let demoAccounts: [FireVaultWorkspaceAccount] = [
        .init(
            id: "demo-medical", name: "Boise River Medical Center", address: "1550 River Street, Boise, ID 83702",
            category: "Healthcare", accountId: "G7CB01-01", phone: "2085550101", favorite: true,
            latitude: 43.6178, longitude: -116.1970, tags: ["Healthcare", "Multi-Building"],
            notes: [.init(id: "n1", title: "Panel access", text: "Check in with facilities before entering the main electrical room.", date: "Today")],
            documents: [.init(id: "d1", title: "Fire alarm riser diagram", subtitle: "3-page scan", kind: "scan", date: "Jul 21")],
            equipment: [.init(id: "e1", title: "Notifier NFS2-3030", subtitle: "Main electrical room", status: "Active")],
            locations: [.init(id: "l1", label: "Main Entrance", subtitle: "South doors", type: "Entrance", plusCode: "85M5JR93+4C", latitude: 43.6177, longitude: -116.1968)],
            recent: [.init(id: "r1", title: "Riser diagram", subtitle: "Document scan added", kind: "document", date: "Today")]
        ),
        .init(
            id: "demo-school", name: "North End Elementary", address: "1900 Harrison Boulevard, Boise, ID 83702",
            category: "Education", accountId: "EDU-204", phone: "2085550102", favorite: false,
            latitude: 43.6351, longitude: -116.2034, tags: ["School"],
            notes: [.init(id: "n2", title: "Summer access", text: "Use the east service entrance during summer break.", date: "Yesterday")],
            documents: [], equipment: [.init(id: "e2", title: "Silent Knight 6820", subtitle: "Office hallway", status: "Active")],
            locations: [], recent: []
        ),
        .init(
            id: "demo-library", name: "Boise Central Library", address: "715 South Capitol Boulevard, Boise, ID 83702",
            category: "Government", accountId: "CITY-118", phone: "2085550103", favorite: true,
            latitude: 43.6102, longitude: -116.2077, tags: ["Public Building"], notes: [], documents: [], equipment: [], locations: [], recent: []
        ),
        .init(
            id: "demo-warehouse", name: "Treasure Valley Distribution", address: "9800 West Emerald Street, Boise, ID 83704",
            category: "Commercial", accountId: "COM-441", phone: "2085550104", favorite: false,
            latitude: 43.6107, longitude: -116.2981, tags: ["Warehouse"], notes: [], documents: [], equipment: [], locations: [], recent: []
        )
    ]
}
