//
//  FireVaultStore.swift
//  FireVault
//
//  Native application and demo-data authority for Build 1.06.02.
//

import Foundation
import Combine
import CoreLocation
import MapKit
import UIKit
import Supabase
import Auth

struct FireVaultCSVImportResult: Equatable {
    let added: Int
    let updated: Int
    let skipped: Int
    let totalRows: Int
    let messages: [String]
}

struct FireVaultBackupMergeResult: Equatable {
    let added: Int
    let preserved: Int
}

struct FireVaultMediaStorageReport: Equatable {
    var referencedFiles: Int
    var orphanedFiles: Int
    var totalBytes: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

enum FireVaultMediaError: LocalizedError {
    case accountUnavailable
    case emptyScan
    case encodingFailed
    case storageUnavailable
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            "The selected account is no longer available."
        case .emptyScan:
            "The scanner did not return any pages."
        case .encodingFailed:
            "The captured photo could not be encoded."
        case .storageUnavailable:
            "FireVault Pro media storage is unavailable on this iPhone."
        case .writeFailed(let detail):
            "The captured media could not be saved. \(detail)"
        }
    }
}

enum FireVaultCaptureQuickAction: Equatable {
    case photo
    case scan
}

enum FireVaultCloudVaultAccessError: LocalizedError, Equatable {
    case linkedToDifferentLogin

    var errorDescription: String? {
        switch self {
        case .linkedToDifferentLogin:
            "This iPhone's local vault is linked to another FireVault login. Sign out and use the original account. No local or cloud data was changed."
        }
    }
}

enum FireVaultCustomerAccountDeletionError: LocalizedError, Equatable {
    case accountUnavailable
    case syncInProgress

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            "This customer account is no longer available."
        case .syncInProgress:
            "Wait for the current cloud sync to finish, then try deleting this customer account again."
        }
    }
}

typealias FireVaultRemoteAccountDelete = (
    FireVaultWorkspaceAccount,
    UUID?
) async throws -> FireVaultRemoteAccountDeletionResult

@MainActor
final class FireVaultStore: ObservableObject {
    @Published var accounts: [FireVaultWorkspaceAccount]
    @Published var selectedAccountID: String?
    @Published private(set) var captureAccountID: String?
    @Published var selectedTab: FireVaultShellTab = .nearby
    @Published var locationStatus: String
    @Published private(set) var demoMode: Bool
    @Published private(set) var geocodingProgress: FireVaultGeocodingProgress?
    @Published private(set) var nearbyResetRequestID = UUID()
    @Published private(set) var pendingCaptureQuickAction: FireVaultCaptureQuickAction?
    @Published private(set) var cloudLastSyncedAt: Date?
    @Published private(set) var cloudLastCheckedAt: Date?
    @Published private(set) var cloudSyncErrorMessage: String? = nil
    @Published private(set) var isCloudSyncing = false
    @Published private(set) var cloudSyncCompleted = 0
    @Published private(set) var cloudSyncTotal = 0

    private let defaults: UserDefaults
    private let accountArchiveURLOverride: URL?
    private let usesFileArchive: Bool
    private let remoteAccountDelete: FireVaultRemoteAccountDelete
    private var accountPersistenceGeneration = 0
    private var accountArchiveURL: URL? {
        accountArchiveURLOverride
            ?? (usesFileArchive ? FireVaultAccountArchive.primaryURL(demoMode: demoMode) : nil)
    }
    private let demoCoordinate = CLLocationCoordinate2D(latitude: 43.6150, longitude: -116.2023)
    private var geocodingTask: Task<Void, Never>?
    private var categoryRules: [FireVaultCategoryRule] = []
    private var categoryRuleSuppressedAccountIDs: Set<String>

    private enum Key {
        static let demoMode = "firevault.native.demo-mode.v1"
        static let demoAccounts = "firevault.native.demo-accounts.v1"
        static let demoAccountsBackup = "firevault.native.demo-accounts.backup.v1"
        static let productionAccounts = "firevault.native.production-accounts.v1"
        static let productionAccountsBackup = "firevault.native.production-accounts.backup.v1"
        static let demoCategoryRuleSuppressions = "firevault.native.demo-category-rule-suppressions.v1"
        static let productionCategoryRuleSuppressions = "firevault.native.production-category-rule-suppressions.v1"
        static let cloudLastSyncedAt = "firevault.native.cloud-last-synced-at.v1"
        static let cloudLastCheckedAt = "firevault.native.cloud-last-checked-at.v1"
        static let cloudVaultOwnerUserID = "firevault.native.cloud-vault-owner-user-id.v1"
    }

    init(
        defaults: UserDefaults = .standard,
        accountArchiveURL: URL? = nil,
        remoteAccountDelete: @escaping FireVaultRemoteAccountDelete = FireVaultAccountSyncService.deleteCustomerAccount
    ) {
        self.defaults = defaults
        self.remoteAccountDelete = remoteAccountDelete
        cloudLastSyncedAt = defaults.object(forKey: Key.cloudLastSyncedAt) as? Date
        cloudLastCheckedAt = defaults.object(forKey: Key.cloudLastCheckedAt) as? Date
        let activeDemoMode = defaults.object(forKey: Key.demoMode) as? Bool ?? true
        demoMode = activeDemoMode
        usesFileArchive = defaults === UserDefaults.standard || accountArchiveURL != nil
        accountArchiveURLOverride = accountArchiveURL
        let initialArchiveURL = accountArchiveURL
            ?? (usesFileArchive ? FireVaultAccountArchive.primaryURL(demoMode: activeDemoMode) : nil)
        let suppressionKey = activeDemoMode
            ? Key.demoCategoryRuleSuppressions
            : Key.productionCategoryRuleSuppressions
        categoryRuleSuppressedAccountIDs = Set(defaults.stringArray(forKey: suppressionKey) ?? [])
        locationStatus = activeDemoMode ? "Demo location ready" : "Location ready"

        var migratedAccounts = activeDemoMode
            ? Self.savedAccounts(defaults: defaults, key: Key.demoAccounts) ?? Self.demoAccounts
            : Self.savedAccounts(defaults: defaults, key: Key.productionAccounts) ?? []
        let plusCodePreferences = FireVaultNativeSettingsStore().preferences.plusCodes
        let repairedLegacyPlusCodes = Self.repairPlusCodes(
            in: &migratedAccounts,
            preferences: plusCodePreferences
        )
        accounts = initialArchiveURL.flatMap(FireVaultAccountArchive.load(from:))
            ?? migratedAccounts
        let repairedArchivePlusCodes = Self.repairPlusCodes(
            in: &accounts,
            preferences: plusCodePreferences
        )
        if let archiveURL = initialArchiveURL,
           !FileManager.default.fileExists(atPath: archiveURL.path),
           let migrationData = try? JSONEncoder().encode(accounts) {
            Task {
                try? await FireVaultAccountArchiveWriter.shared.write(
                    migrationData,
                    to: archiveURL,
                    generation: 0,
                    immediate: true
                )
            }
        }
        if repairedLegacyPlusCodes || repairedArchivePlusCodes {
            persistAccounts()
        }
    }

    var selectedAccount: FireVaultWorkspaceAccount? {
        guard let selectedAccountID else { return nil }
        return accounts.first { $0.id == selectedAccountID }
    }

    var captureAccount: FireVaultWorkspaceAccount? {
        guard let captureAccountID else { return nil }
        return accounts.first { $0.id == captureAccountID }
    }

    var mappedAccountCount: Int {
        accounts.lazy.filter { $0.coordinate != nil }.count
    }

    var unmappedAccountCount: Int {
        accounts.count - mappedAccountCount
    }

    var geocodableAccountCount: Int {
        accounts.lazy.filter {
            $0.coordinate == nil && FireVaultPostalAddress(combinedAddress: $0.address) != nil
        }.count
    }

    func reloadAccounts() {
        let key = demoMode ? Key.demoAccounts : Key.productionAccounts
        guard let refreshed = accountArchiveURL.flatMap(FireVaultAccountArchive.load(from:))
            ?? Self.savedAccounts(defaults: defaults, key: key) else { return }
        var repairedAccounts = refreshed
        let didRepairPlusCodes = Self.repairPlusCodes(
            in: &repairedAccounts,
            preferences: FireVaultNativeSettingsStore().preferences.plusCodes
        )
        accounts = repairedAccounts
        if let selectedAccountID, !accounts.contains(where: { $0.id == selectedAccountID }) {
            self.selectedAccountID = nil
        }
        applyCategoryRules()
        if didRepairPlusCodes { persistAccounts() }
    }

    @discardableResult
    func configureCategoryRules(_ rules: [FireVaultCategoryRule]) -> Int {
        categoryRules = rules
        let additions = applyCategoryRules()
        persistAccounts()
        return additions
    }

    func renameCategory(from oldName: String, to newName: String) {
        let replacement = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return }
        for index in accounts.indices {
            if accounts[index].category.caseInsensitiveCompare(oldName) == .orderedSame {
                accounts[index].category = replacement
            }
            accounts[index].tags = accounts[index].tags.map {
                $0.caseInsensitiveCompare(oldName) == .orderedSame ? replacement : $0
            }
        }
        persist()
    }

    /// Removes retired category values from every account and prevents a
    /// deleted automatic rule from restoring them during the same save.
    @discardableResult
    func removeCategories(_ categoryNames: [String]) -> Int {
        let removedKeys = Set(categoryNames.compactMap { name -> String? in
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value.lowercased()
        })
        guard !removedKeys.isEmpty else { return 0 }

        categoryRules.removeAll {
            removedKeys.contains($0.categoryTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }

        var affectedAccounts = 0
        for index in accounts.indices {
            var changed = false
            let categoryKey = accounts[index].category
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if removedKeys.contains(categoryKey) {
                accounts[index].category = ""
                changed = true
            }

            let originalTagCount = accounts[index].tags.count
            accounts[index].tags.removeAll { tag in
                removedKeys.contains(tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
            if accounts[index].tags.count != originalTagCount {
                changed = true
            }
            if changed { affectedAccounts += 1 }
        }

        persistAccounts()
        return affectedAccounts
    }

    func appPayload(
        userCoordinate: CLLocationCoordinate2D?,
        liveLocationStatus: String
    ) -> FireVaultAppPayload {
        let today = Date()
        let dateComponents = Calendar.current.dateComponents([.day, .year], from: today)
        let monthName = today.formatted(.dateTime.month(.wide))
        let displayDate = "\(monthName) \(dateComponents.day ?? 0) \(dateComponents.year ?? 0)"
        let nativeAccounts = accounts.map(Self.nativeAccount)
        let distanceCoordinate = demoMode ? demoCoordinate : userCoordinate
        let userLocation = distanceCoordinate.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        let nearby = accounts.compactMap { account -> FireVaultNativeNearbyAccount? in
            guard let coordinate = account.coordinate, let userLocation else { return nil }
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
            todayWeekday: today.formatted(.dateTime.weekday(.wide)),
            todayDate: displayDate,
            technicianName: demoMode ? "Demo Technician" : "Field Technician",
            locationStatus: demoMode ? locationStatus : liveLocationStatus,
            accounts: nativeAccounts,
            nearby: nearby,
            settingsGroups: []
        )
    }

    func openAccount(_ id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        captureAccountID = id
        selectedAccountID = id
    }

    func selectCaptureAccount(_ id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        captureAccountID = id
    }

    func requestCapture(_ action: FireVaultCaptureQuickAction) {
        pendingCaptureQuickAction = action
    }

    func consumeCaptureQuickAction() -> FireVaultCaptureQuickAction? {
        defer { pendingCaptureQuickAction = nil }
        return pendingCaptureQuickAction
    }

    func closeAccount(to tab: FireVaultShellTab? = nil) {
        selectedAccountID = nil
        if let tab { selectedTab = tab }
    }

    /// Deletes one customer/site record, not the signed-in FireVault user.
    /// Production records are removed locally only after Supabase confirms the
    /// user-owned cloud row is gone (or that no matching cloud row exists).
    func deleteCustomerAccount(id: String) async throws {
        guard let account = accounts.first(where: { $0.id == id }) else {
            throw FireVaultCustomerAccountDeletionError.accountUnavailable
        }
        guard !isCloudSyncing else {
            throw FireVaultCustomerAccountDeletionError.syncInProgress
        }

        if !demoMode {
            isCloudSyncing = true
            defer { isCloudSyncing = false }
            do {
                _ = try await remoteAccountDelete(account, cloudVaultOwnerUserID)
                recordCloudCheck()
                recordSuccessfulCloudSync()
            } catch {
                recordCloudCheck()
                cloudSyncErrorMessage = error.localizedDescription.isEmpty
                    ? "The customer account could not be deleted from FireVault Cloud. Nothing was removed from this iPhone."
                    : error.localizedDescription
                throw error
            }
        }

        removeCustomerAccountFromDevice(id: id)
    }

    private func removeCustomerAccountFromDevice(id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        if let root = try? mediaRootURL() {
            let safeAccountID = id.replacingOccurrences(
                of: "[^A-Za-z0-9_-]",
                with: "_",
                options: .regularExpression
            )
            let directory = root.appendingPathComponent(safeAccountID, isDirectory: true)
            if FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        accounts.removeAll { $0.id == id }
        categoryRuleSuppressedAccountIDs.remove(id)
        if selectedAccountID == id { selectedAccountID = nil }
        if captureAccountID == id { captureAccountID = nil }
        persistAccounts()
    }

    func refreshNearby() {
        locationStatus = "Updated \(Date().formatted(date: .omitted, time: .shortened))"
    }

    func requestNearbyReset() {
        nearbyResetRequestID = UUID()
        if demoMode {
            refreshNearby()
        }
    }

    func startGeocodingMissingAccounts() {
        guard geocodingTask == nil else { return }

        let requests = accounts.enumerated().compactMap { index, account -> FireVaultGeocodingRequest? in
            guard account.coordinate == nil,
                  let address = FireVaultPostalAddress(combinedAddress: account.address) else {
                return nil
            }
            return .init(token: "fv-\(index)", accountID: account.id, address: address)
        }
        guard !requests.isEmpty else {
            geocodingProgress = .init(
                phase: .complete,
                completed: 0,
                total: 0,
                matched: 0,
                message: "All accounts with usable addresses are already mapped."
            )
            return
        }

        geocodingProgress = .init(
            phase: .preparing,
            completed: 0,
            total: requests.count,
            matched: 0,
            message: "Preparing \(requests.count) imported addresses…"
        )

        geocodingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                self.geocodingProgress = .init(
                    phase: .submitting,
                    completed: 0,
                    total: requests.count,
                    matched: 0,
                    message: "Calculating account coordinates…"
                )
                let censusMatches = try await FireVaultCensusGeocoder().geocode(requests)
                try Task.checkCancellation()

                let censusTokens = Set(censusMatches.map(\.token))
                let censusMisses = requests.filter { !censusTokens.contains($0.token) }
                var matches = censusMatches
                if !censusMisses.isEmpty {
                    let appleMatches = try await self.geocodeCensusMissesWithApple(
                        censusMisses,
                        alreadyMatched: censusMatches.count,
                        total: requests.count
                    )
                    matches.append(contentsOf: appleMatches)
                }
                try Task.checkCancellation()

                self.geocodingProgress = .init(
                    phase: .saving,
                    completed: requests.count,
                    total: requests.count,
                    matched: matches.count,
                    message: "Saving \(matches.count) mapped accounts…"
                )
                self.applyGeocodingMatches(matches, requests: requests)
                let unmatched = requests.count - matches.count
                let suffix = unmatched > 0 ? " \(unmatched) address\(unmatched == 1 ? "" : "es") could not be matched." : ""
                self.geocodingProgress = .init(
                    phase: .complete,
                    completed: requests.count,
                    total: requests.count,
                    matched: matches.count,
                    message: "Mapped \(matches.count) account\(matches.count == 1 ? "" : "s").\(suffix)"
                )
            } catch is CancellationError {
                self.geocodingProgress = .init(
                    phase: .cancelled,
                    completed: 0,
                    total: requests.count,
                    matched: 0,
                    message: "Address mapping stopped. You can retry at any time."
                )
            } catch {
                self.geocodingProgress = .init(
                    phase: .failed,
                    completed: 0,
                    total: requests.count,
                    matched: 0,
                    message: error.localizedDescription
                )
            }
            self.geocodingTask = nil
        }
    }

    private func geocodeCensusMissesWithApple(
        _ requests: [FireVaultGeocodingRequest],
        alreadyMatched: Int,
        total: Int
    ) async throws -> [FireVaultGeocodingMatch] {
        var matches: [FireVaultGeocodingMatch] = []

        for (offset, record) in requests.enumerated() {
            try Task.checkCancellation()
            geocodingProgress = .init(
                phase: .appleFallback,
                completed: min(total, alreadyMatched + offset),
                total: total,
                matched: alreadyMatched + matches.count,
                message: "Trying Apple Maps for \(requests.count) unmatched address\(requests.count == 1 ? "" : "es")…"
            )

            guard let request = MKGeocodingRequest(addressString: record.address.singleLine) else {
                continue
            }
            do {
                let mapItems = try await request.mapItems
                try Task.checkCancellation()
                if let coordinate = mapItems.first?.location.coordinate,
                   CLLocationCoordinate2DIsValid(coordinate) {
                    matches.append(
                        .init(
                            token: record.token,
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        )
                    )
                }
            } catch {
                // A single address failure must not discard other successful coordinates.
            }
        }
        return matches
    }

    func cancelGeocoding() {
        geocodingTask?.cancel()
    }

    func applyGeocodingMatches(
        _ matches: [FireVaultGeocodingMatch],
        requests: [FireVaultGeocodingRequest]
    ) {
        let accountIDByToken = Dictionary(uniqueKeysWithValues: requests.map { ($0.token, $0.accountID) })
        let matchByAccountID = Dictionary(uniqueKeysWithValues: matches.compactMap { match -> (String, FireVaultGeocodingMatch)? in
            guard let accountID = accountIDByToken[match.token] else { return nil }
            return (accountID, match)
        })

        for index in accounts.indices {
            guard let match = matchByAccountID[accounts[index].id] else { continue }
            accounts[index].latitude = match.latitude
            accounts[index].longitude = match.longitude
        }
        persist()
    }

    func toggleFavorite(_ id: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].favorite.toggle()
        persist()
    }

    @discardableResult
    func updateAccount(
        id: String,
        name: String,
        address: String,
        category: String,
        accountId: String,
        phone: String
    ) -> Bool {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return false }

        return updateAccount(
            id: id,
            name: name,
            address: address,
            category: category,
            accountId: accountId,
            phone: phone,
            latitude: accounts[index].latitude,
            longitude: accounts[index].longitude
        )
    }

    @discardableResult
    func updateAccount(
        id: String,
        name: String,
        address: String,
        category: String,
        accountId: String,
        phone: String,
        latitude: Double?,
        longitude: Double?
    ) -> Bool {
        guard let index = accounts.firstIndex(where: { $0.id == id }),
              Self.isValidCoordinatePair(latitude: latitude, longitude: longitude) else { return false }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return false }

        let previousCategory = accounts[index].category.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].name = normalizedName
        accounts[index].address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].category = normalizedCategory
        if normalizedCategory.isEmpty {
            categoryRuleSuppressedAccountIDs.insert(id)
            if !previousCategory.isEmpty {
                accounts[index].tags.removeAll {
                    $0.caseInsensitiveCompare(previousCategory) == .orderedSame
                }
            }
        } else {
            categoryRuleSuppressedAccountIDs.remove(id)
        }
        accounts[index].accountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].latitude = latitude
        accounts[index].longitude = longitude
        persist()
        return true
    }

    @discardableResult
    func addAccount() -> FireVaultWorkspaceAccount {
        let number = accounts.count + 1
        let account = FireVaultWorkspaceAccount(
            id: UUID().uuidString,
            name: demoMode ? "Demo Account \(number)" : "New Account \(number)",
            address: demoMode ? "\(100 + number) Demo Way, Boise, ID 83702" : "",
            category: demoMode ? "Commercial" : "Uncategorized",
            accountId: demoMode ? "DEMO-\(number.formatted(.number.precision(.integerLength(2))))" : "",
            phone: demoMode ? "20855501\(number.formatted(.number.precision(.integerLength(2))))" : "",
            favorite: false,
            latitude: demoMode ? 43.615 + Double(number) * 0.002 : nil,
            longitude: demoMode ? -116.202 + Double(number) * 0.002 : nil,
            tags: demoMode ? ["Demo"] : [],
            notes: [],
            documents: [],
            equipment: [],
            locations: [],
            recent: []
        )
        accounts.append(account)
        openAccount(account.id)
        persist()
        return account
    }

    @discardableResult
    func addAccount(
        from stop: FireVaultBreadcrumbStop,
        name: String,
        address: String = ""
    ) -> FireVaultWorkspaceAccount {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = FireVaultWorkspaceAccount(
            id: UUID().uuidString,
            name: normalizedName.isEmpty ? "New Account" : normalizedName,
            address: normalizedAddress.isEmpty ? "Location saved from Trip Log" : normalizedAddress,
            category: "Uncategorized",
            accountId: "",
            phone: "",
            favorite: false,
            latitude: stop.latitude,
            longitude: stop.longitude,
            tags: ["Trip Log"],
            notes: [],
            documents: [],
            equipment: [],
            locations: [
                .init(
                    id: UUID().uuidString,
                    label: "Trip Log location",
                    subtitle: "Created from a recorded stop",
                    type: "Site",
                    plusCode: "",
                    latitude: stop.latitude,
                    longitude: stop.longitude
                )
            ],
            recent: [
                .init(
                    id: UUID().uuidString,
                    title: "Account created",
                    subtitle: "Added from Trip Log stop",
                    kind: "location",
                    date: "Now"
                )
            ]
        )
        accounts.append(account)
        persist()
        return account
    }

    @discardableResult
    func addNote(
        to accountID: String,
        title: String = "Field note",
        text: String = "New note"
    ) -> FireVaultWorkspaceNote? {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return nil }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = FireVaultWorkspaceNote(
            id: UUID().uuidString,
            title: trimmedTitle.isEmpty ? "Field note" : trimmedTitle,
            text: trimmedText,
            date: Date().formatted(date: .abbreviated, time: .shortened)
        )
        accounts[index].notes.insert(note, at: 0)
        accounts[index].recent.insert(
            .init(id: UUID().uuidString, title: note.title, subtitle: note.text, kind: "note", date: "Now"),
            at: 0
        )
        persist()
        return note
    }

    @discardableResult
    func updateNote(accountID: String, noteID: String, title: String, text: String) -> Bool {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == accountID }),
              let noteIndex = accounts[accountIndex].notes.firstIndex(where: { $0.id == noteID }) else {
            return false
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[accountIndex].notes[noteIndex].title = trimmedTitle.isEmpty ? "Field note" : trimmedTitle
        accounts[accountIndex].notes[noteIndex].text = trimmedText
        accounts[accountIndex].notes[noteIndex].date = Date().formatted(date: .abbreviated, time: .shortened)
        persist()
        return true
    }

    @discardableResult
    func deleteNote(accountID: String, noteID: String) -> Bool {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == accountID }),
              let noteIndex = accounts[accountIndex].notes.firstIndex(where: { $0.id == noteID }) else {
            return false
        }
        accounts[accountIndex].notes.remove(at: noteIndex)
        persist()
        return true
    }

    func addDocument(to accountID: String, scan: Bool) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let document = FireVaultWorkspaceDocument(
            id: UUID().uuidString,
            title: scan ? "Document scan" : "File",
            subtitle: "Added \(Date().formatted(date: .abbreviated, time: .omitted))",
            kind: scan ? "scan" : "file",
            date: "Today"
        )
        accounts[index].documents.insert(document, at: 0)
        persist()
    }

    @discardableResult
    func attachCapturedPhoto(_ image: UIImage, to accountID: String) throws -> FireVaultWorkspaceDocument {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            throw FireVaultMediaError.accountUnavailable
        }
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw FireVaultMediaError.encodingFailed
        }

        let fileName = "\(UUID().uuidString).jpg"
        try data.write(to: try mediaURL(accountID: accountID, fileName: fileName), options: .atomic)

        let document = FireVaultWorkspaceDocument(
            id: UUID().uuidString,
            title: "Field photo",
            subtitle: "Photo with FireVault Pro overlay",
            kind: "photo",
            date: Date().formatted(date: .abbreviated, time: .shortened),
            mediaFileName: fileName
        )
        accounts[index].documents.insert(document, at: 0)
        accounts[index].recent.insert(
            .init(
                id: UUID().uuidString,
                title: document.title,
                subtitle: document.subtitle,
                kind: "photo",
                date: "Now"
            ),
            at: 0
        )
        persist()
        return document
    }

    @discardableResult
    func attachScannedDocument(_ pages: [UIImage], to accountID: String) throws -> FireVaultWorkspaceDocument {
        guard !pages.isEmpty else { throw FireVaultMediaError.emptyScan }
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            throw FireVaultMediaError.accountUnavailable
        }

        let fileName = "\(UUID().uuidString).pdf"
        let firstPage = pages[0]
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: firstPage.size)
        )
        let data = renderer.pdfData { context in
            for page in pages {
                let bounds = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                page.draw(in: bounds)
            }
        }
        try data.write(to: try mediaURL(accountID: accountID, fileName: fileName), options: .atomic)

        let pageLabel = "\(pages.count) page\(pages.count == 1 ? "" : "s")"
        let document = FireVaultWorkspaceDocument(
            id: UUID().uuidString,
            title: "Document scan",
            subtitle: pageLabel,
            kind: "scan",
            date: Date().formatted(date: .abbreviated, time: .shortened),
            mediaFileName: fileName
        )
        accounts[index].documents.insert(document, at: 0)
        accounts[index].recent.insert(
            .init(
                id: UUID().uuidString,
                title: document.title,
                subtitle: pageLabel,
                kind: "scan",
                date: "Now"
            ),
            at: 0
        )
        persist()
        return document
    }

    @discardableResult
    func addEquipment(
        to accountID: String,
        title: String = "Fire Alarm Control Panel (FACP)",
        subtitle: String = "",
        status: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        pinColor: String = "Green"
    ) -> FireVaultWorkspaceEquipment? {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }),
              Self.isValidCoordinatePair(latitude: latitude, longitude: longitude) else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let equipment = FireVaultWorkspaceEquipment(
            id: UUID().uuidString,
            title: trimmedTitle,
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude,
            pinColor: FireVaultMapPinColor(rawValue: pinColor)?.rawValue
                ?? FireVaultMapPinColor.green.rawValue
        )
        accounts[index].equipment.append(equipment)
        persist()
        return equipment
    }

    @discardableResult
    func updateEquipment(
        accountID: String,
        equipmentID: String,
        title: String,
        subtitle: String,
        status: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        pinColor: String = "Green"
    ) -> Bool {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == accountID }),
              let equipmentIndex = accounts[accountIndex].equipment.firstIndex(where: { $0.id == equipmentID }),
              Self.isValidCoordinatePair(latitude: latitude, longitude: longitude) else {
            return false
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        accounts[accountIndex].equipment[equipmentIndex].title = trimmedTitle
        accounts[accountIndex].equipment[equipmentIndex].subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[accountIndex].equipment[equipmentIndex].status = status.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[accountIndex].equipment[equipmentIndex].latitude = latitude
        accounts[accountIndex].equipment[equipmentIndex].longitude = longitude
        accounts[accountIndex].equipment[equipmentIndex].pinColor =
            FireVaultMapPinColor(rawValue: pinColor)?.rawValue
            ?? FireVaultMapPinColor.green.rawValue
        persist()
        return true
    }

    @discardableResult
    func deleteEquipment(accountID: String, equipmentID: String) -> Bool {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == accountID }),
              let equipmentIndex = accounts[accountIndex].equipment.firstIndex(where: { $0.id == equipmentID }) else {
            return false
        }
        accounts[accountIndex].equipment.remove(at: equipmentIndex)
        persist()
        return true
    }

    private func mediaURL(accountID: String, fileName: String) throws -> URL {
        let safeAccountID = accountID.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        let directory = try mediaRootURL()
            .appendingPathComponent(safeAccountID, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory.appendingPathComponent(fileName)
        } catch {
            throw FireVaultMediaError.writeFailed(error.localizedDescription)
        }
    }

    private func mediaRootURL() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw FireVaultMediaError.storageUnavailable
        }
        return applicationSupport
            .appendingPathComponent("FireVault", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
    }

    private var referencedMediaPaths: Set<String> {
        Set(accounts.flatMap { account in
            account.documents.compactMap { document in
                guard let fileName = document.mediaFileName,
                      fileName == URL(fileURLWithPath: fileName).lastPathComponent,
                      let url = try? mediaURL(accountID: account.id, fileName: fileName) else {
                    return nil
                }
                return url.standardizedFileURL.path
            }
        })
    }

    @discardableResult
    func addLocation(
        to accountID: String,
        label: String = "New location",
        subtitle: String = "",
        type: String = "Other",
        plusCode: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        pinColor: String = "Purple",
        directionsMode: String = FireVaultDirectionsMode.walking.rawValue
    ) -> FireVaultWorkspaceLocation? {
        let plusCodePreferences = FireVaultNativeSettingsStore().preferences.plusCodes
        guard let index = accounts.firstIndex(where: { $0.id == accountID }),
              Self.isValidCoordinatePair(latitude: latitude, longitude: longitude),
              let storedPlusCode = FireVaultPlusCode.codeForStorage(
                  enteredCode: plusCode,
                  latitude: latitude,
                  longitude: longitude,
                  length: plusCodePreferences.locationLength,
                  autoGenerate: plusCodePreferences.autoGenerate
              ) else { return nil }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return nil }
        let location = FireVaultWorkspaceLocation(
            id: UUID().uuidString,
            label: trimmedLabel,
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Other"
                : type.trimmingCharacters(in: .whitespacesAndNewlines),
            plusCode: storedPlusCode,
            latitude: latitude,
            longitude: longitude,
            pinColor: FireVaultMapPinColor(rawValue: pinColor)?.rawValue
                ?? FireVaultMapPinColor.purple.rawValue,
            directionsMode: FireVaultDirectionsMode(rawValue: directionsMode)?.rawValue
                ?? FireVaultDirectionsMode.walking.rawValue
        )
        accounts[index].locations.append(location)
        persist()
        return location
    }

    @discardableResult
    func updateLocation(
        accountID: String,
        locationID: String,
        label: String,
        subtitle: String,
        type: String,
        plusCode: String,
        latitude: Double?,
        longitude: Double?,
        pinColor: String = "Purple",
        directionsMode: String? = nil
    ) -> Bool {
        let plusCodePreferences = FireVaultNativeSettingsStore().preferences.plusCodes
        guard let accountIndex = accounts.firstIndex(where: { $0.id == accountID }),
              let locationIndex = accounts[accountIndex].locations.firstIndex(where: { $0.id == locationID }),
              Self.isValidCoordinatePair(latitude: latitude, longitude: longitude),
              let storedPlusCode = FireVaultPlusCode.codeForStorage(
                  enteredCode: plusCode,
                  latitude: latitude,
                  longitude: longitude,
                  length: plusCodePreferences.locationLength,
                  autoGenerate: plusCodePreferences.autoGenerate
              ) else { return false }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return false }
        accounts[accountIndex].locations[locationIndex].label = trimmedLabel
        accounts[accountIndex].locations[locationIndex].subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[accountIndex].locations[locationIndex].type = trimmedType.isEmpty ? "Other" : trimmedType
        accounts[accountIndex].locations[locationIndex].plusCode = storedPlusCode
        accounts[accountIndex].locations[locationIndex].latitude = latitude
        accounts[accountIndex].locations[locationIndex].longitude = longitude
        accounts[accountIndex].locations[locationIndex].pinColor =
            FireVaultMapPinColor(rawValue: pinColor)?.rawValue
            ?? FireVaultMapPinColor.purple.rawValue
        if let directionsMode {
            accounts[accountIndex].locations[locationIndex].directionsMode =
                FireVaultDirectionsMode(rawValue: directionsMode)?.rawValue
                ?? FireVaultDirectionsMode.walking.rawValue
        }
        persist()
        return true
    }

    @discardableResult
    func deleteLocation(accountID: String, locationID: String) -> Bool {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == accountID }),
              let locationIndex = accounts[accountIndex].locations.firstIndex(where: { $0.id == locationID }) else {
            return false
        }
        accounts[accountIndex].locations.remove(at: locationIndex)
        persist()
        return true
    }

    private static func isValidCoordinatePair(latitude: Double?, longitude: Double?) -> Bool {
        if latitude == nil && longitude == nil { return true }
        guard let latitude, let longitude else { return false }
        return CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude))
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
        categoryRuleSuppressedAccountIDs.removeAll()
        selectedAccountID = nil
        captureAccountID = nil
        defaults.removeObject(forKey: Key.demoAccounts)
        defaults.removeObject(forKey: Key.demoCategoryRuleSuppressions)
        persistAccounts()
    }

    func exitDemoMode() {
        guard demoMode else { return }
        selectedAccountID = nil
        captureAccountID = nil
        demoMode = false
        defaults.set(false, forKey: Key.demoMode)
        accounts = accountArchiveURL.flatMap(FireVaultAccountArchive.load(from:))
            ?? Self.savedAccounts(defaults: defaults, key: Key.productionAccounts)
            ?? []
        categoryRuleSuppressedAccountIDs = Set(
            defaults.stringArray(forKey: Key.productionCategoryRuleSuppressions) ?? []
        )
        locationStatus = "Location ready"
    }

    func enterDemoMode() {
        guard !demoMode else { return }
        selectedAccountID = nil
        captureAccountID = nil
        demoMode = true
        defaults.set(true, forKey: Key.demoMode)
        accounts = accountArchiveURL.flatMap(FireVaultAccountArchive.load(from:))
            ?? Self.savedAccounts(defaults: defaults, key: Key.demoAccounts)
            ?? Self.demoAccounts
        categoryRuleSuppressedAccountIDs = Set(
            defaults.stringArray(forKey: Key.demoCategoryRuleSuppressions) ?? []
        )
        locationStatus = "Demo location ready"
    }

    func importAccountsCSV(_ data: Data) throws -> FireVaultCSVImportResult {
        let analysis = try FireVaultCSVImporter.analyze(data, correctSwappedCoordinates: true)
        return applyCSVImport(analysis)
    }

    func previewAccountsCSV(
        _ data: Data,
        mapping: FireVaultCSVMapping? = nil,
        correctSwappedCoordinates: Bool = false
    ) throws -> FireVaultCSVAnalysis {
        try FireVaultCSVImporter.analyze(
            data,
            mapping: mapping,
            correctSwappedCoordinates: correctSwappedCoordinates
        )
    }

    var cloudSyncStatusText: String {
        if demoMode { return "Demo data" }
        if isCloudSyncing { return "Syncing" }
        if cloudSyncErrorMessage != nil { return "Needs attention" }
        return cloudLastSyncedAt == nil ? "Not synced yet" : "Up to date"
    }

    func syncAccountsNow() async {
        guard !demoMode, !isCloudSyncing else { return }
        isCloudSyncing = true
        cloudSyncErrorMessage = nil
        cloudSyncCompleted = 0
        cloudSyncTotal = accounts.filter { $0.cloudID == nil || $0.cloudSyncedAt == nil }.count
        defer { isCloudSyncing = false }
        do {
            let session = try await SupabaseManager.client.auth.session
            let visibleCloudRows = try await FireVaultAccountSyncService.fetchAccounts()
            try validateCloudVaultOwnership(userID: session.user.id, cloudRows: visibleCloudRows)
            let result = try await FireVaultAccountSyncService.backfillLegacyAccounts(accounts) { [weak self] completed, total in
                await MainActor.run {
                    self?.cloudSyncCompleted = completed
                    self?.cloudSyncTotal = total
                }
            }
            let timestamp = Date()
            for index in accounts.indices {
                guard let remoteID = result.mappings[accounts[index].id] else { continue }
                accounts[index].cloudID = remoteID.uuidString
                accounts[index].cloudSyncedAt = timestamp
                accounts[index].cloudSyncError = nil
            }
            persist()
            let cloudRows = try await FireVaultAccountSyncService.fetchAccounts()
            mergeCloudAccounts(cloudRows)
            recordCloudCheck()
            recordSuccessfulCloudSync()
        } catch {
            recordCloudCheck()
            cloudSyncErrorMessage = error.localizedDescription.isEmpty
                ? "Cloud sync failed. Your accounts remain saved on this iPhone."
                : error.localizedDescription
        }
    }

    @discardableResult
    func eraseLocalAccountDataAfterCloudDeletion(for userID: UUID) -> Bool {
        guard cloudVaultOwnerUserID == userID else { return false }
        accounts.removeAll()
        selectedAccountID = nil
        captureAccountID = nil
        cloudLastSyncedAt = nil
        cloudLastCheckedAt = nil
        defaults.removeObject(forKey: Key.cloudLastSyncedAt)
        defaults.removeObject(forKey: Key.cloudLastCheckedAt)
        defaults.removeObject(forKey: Key.cloudVaultOwnerUserID)
        persistAccounts()
        return true
    }

    func refreshAccountsFromCloud() async {
        guard !demoMode, !isCloudSyncing else { return }
        isCloudSyncing = true
        cloudSyncErrorMessage = nil
        defer { isCloudSyncing = false }

        do {
            // Reading session refreshes an expired token when needed, so Sync
            // Now verifies the saved sign-in before reading user-owned accounts.
            let session = try await SupabaseManager.client.auth.session
            let cloudRows = try await FireVaultAccountSyncService.fetchAccounts()
            try validateCloudVaultOwnership(userID: session.user.id, cloudRows: cloudRows)
            guard !demoMode else { return }
            mergeCloudAccounts(cloudRows)
            recordCloudCheck()
            recordSuccessfulCloudSync()
        } catch {
            recordCloudCheck()
            recordCloudSyncFailure(error)
        }
    }

    func applyCSVImportAndSync(
        _ analysis: FireVaultCSVAnalysis,
        csvData: Data,
        fileName: String
    ) async -> FireVaultCSVImportResult {
        let localResult = applyCSVImport(analysis)
        guard !demoMode else { return localResult }

        isCloudSyncing = true
        cloudSyncErrorMessage = nil
        defer { isCloudSyncing = false }

        var messages = localResult.messages
        do {
            let session = try await SupabaseManager.client.auth.session
            let visibleCloudRows = try await FireVaultAccountSyncService.fetchAccounts()
            try validateCloudVaultOwnership(userID: session.user.id, cloudRows: visibleCloudRows)
            let cloudResult = try await FireVaultAccountSyncService.importCSV(
                data: csvData,
                fileName: fileName.isEmpty ? "accounts.csv" : fileName,
                analysis: analysis,
                localAccounts: accounts
            )
            let cloudRows = try await FireVaultAccountSyncService.fetchAccounts()
            mergeCloudAccounts(cloudRows)
            recordCloudCheck()
            recordSuccessfulCloudSync()
            messages.insert(
                "Synced \(cloudResult.importedRows) account\(cloudResult.importedRows == 1 ? "" : "s") to your FireVault account.",
                at: 0
            )
        } catch {
            recordCloudCheck()
            recordCloudSyncFailure(error)
            messages.insert(
                "Saved on this iPhone. Cloud sync could not finish. Tap Sync Now in Settings to retry.",
                at: 0
            )
        }

        return .init(
            added: localResult.added,
            updated: localResult.updated,
            skipped: localResult.skipped,
            totalRows: localResult.totalRows,
            messages: Array(messages.prefix(12))
        )
    }

    private func recordSuccessfulCloudSync() {
        let timestamp = Date()
        cloudLastSyncedAt = timestamp
        defaults.set(timestamp, forKey: Key.cloudLastSyncedAt)
        cloudSyncErrorMessage = nil
    }

    private var cloudVaultOwnerUserID: UUID? {
        defaults.string(forKey: Key.cloudVaultOwnerUserID).flatMap(UUID.init(uuidString:))
    }

    func validateCloudVaultOwnership(
        userID: UUID,
        cloudRows: [FireVaultCloudAccountRow]
    ) throws {
        if let ownerID = cloudVaultOwnerUserID {
            guard ownerID == userID else {
                throw FireVaultCloudVaultAccessError.linkedToDifferentLogin
            }
            return
        }

        let linkedCloudIDs = Set(accounts.compactMap { account in
            account.cloudID.flatMap(UUID.init(uuidString:))
        })
        if !linkedCloudIDs.isEmpty {
            let visibleCloudIDs = Set(cloudRows.map(\.id))
            guard !linkedCloudIDs.isDisjoint(with: visibleCloudIDs) else {
                throw FireVaultCloudVaultAccessError.linkedToDifferentLogin
            }
        }

        defaults.set(userID.uuidString.lowercased(), forKey: Key.cloudVaultOwnerUserID)
    }

    private func recordCloudCheck() {
        let timestamp = Date()
        cloudLastCheckedAt = timestamp
        defaults.set(timestamp, forKey: Key.cloudLastCheckedAt)
    }

    private func recordCloudSyncFailure(_ error: Error? = nil) {
        if let accessError = error as? FireVaultCloudVaultAccessError {
            cloudSyncErrorMessage = accessError.localizedDescription
            return
        }
        // Offline-first behavior is intentional: the last valid on-device vault
        // stays available. Keep the customer message actionable and avoid
        // exposing low-level network or authentication details.
        cloudSyncErrorMessage = "FireVault Cloud could not be reached. Your saved accounts remain available."
    }

    private func mergeCloudAccounts(_ cloudRows: [FireVaultCloudAccountRow]) {
        for row in cloudRows where !row.archived {
            let cloud = row.workspaceAccount
            let cloudAccountID = Self.canonicalAccountID(cloud.accountId)
            let cloudIdentity = Self.csvIdentityKey(name: cloud.name, address: cloud.address)

            let existingIndex = accounts.firstIndex {
                $0.id.caseInsensitiveCompare(cloud.id) == .orderedSame
            } ?? accounts.firstIndex {
                !cloudAccountID.isEmpty && Self.canonicalAccountID($0.accountId) == cloudAccountID
            } ?? accounts.firstIndex {
                Self.csvIdentityKey(name: $0.name, address: $0.address) == cloudIdentity
            }

            guard let existingIndex else {
                accounts.append(cloud)
                continue
            }

            accounts[existingIndex].name = cloud.name
            if cloud.address != "No address supplied" {
                accounts[existingIndex].address = cloud.address
            }
            if !cloud.accountId.isEmpty {
                accounts[existingIndex].accountId = cloud.accountId
            }
            if !cloud.phone.isEmpty {
                accounts[existingIndex].phone = cloud.phone
            }
            if let latitude = cloud.latitude, let longitude = cloud.longitude {
                accounts[existingIndex].latitude = latitude
                accounts[existingIndex].longitude = longitude
            }
            if !accounts[existingIndex].tags.contains("Cloud Sync") {
                accounts[existingIndex].tags.append("Cloud Sync")
            }
            accounts[existingIndex].cloudID = row.id.uuidString
            accounts[existingIndex].cloudSyncedAt = Date()
            accounts[existingIndex].cloudSyncError = nil
        }

        persist()
    }

    func applyCSVImport(_ analysis: FireVaultCSVAnalysis) -> FireVaultCSVImportResult {
        var added = 0
        var updated = 0
        var skipped = 0
        var messages = analysis.preview.mappingMessages
        var seenAccountIDs: Set<String> = []
        var accountIDIndex: [String: Int] = [:]
        var nameAddressIndex: [String: Int] = [:]

        for (index, account) in accounts.enumerated() {
            let canonicalID = Self.canonicalAccountID(account.accountId)
            if !canonicalID.isEmpty, accountIDIndex[canonicalID] == nil {
                accountIDIndex[canonicalID] = index
            }
            let identity = Self.csvIdentityKey(name: account.name, address: account.address)
            if nameAddressIndex[identity] == nil {
                nameAddressIndex[identity] = index
            }
        }

        for record in analysis.records {
            guard record.rowResult.status != .rejected else {
                skipped += 1
                messages.append("Row \(record.rowNumber): \(record.rowResult.message)")
                continue
            }

            let accountID = record.accountID
            if !accountID.isEmpty, !seenAccountIDs.insert(accountID).inserted {
                skipped += 1
                messages.append("Row \(record.rowNumber): duplicate Account ID \(accountID) appears more than once in this file.")
                continue
            }

            let identity = Self.csvIdentityKey(name: record.name, address: record.address)
            let existingIndex = accountID.isEmpty
                ? nameAddressIndex[identity]
                : accountIDIndex[accountID]
            if let existingIndex {
                let addressChanged = !record.address.isEmpty &&
                    accounts[existingIndex].address.caseInsensitiveCompare(record.address) != .orderedSame
                accounts[existingIndex].name = record.name
                accounts[existingIndex].address = record.address.isEmpty ? accounts[existingIndex].address : record.address
                accounts[existingIndex].category = record.category.isEmpty ? accounts[existingIndex].category : record.category
                accounts[existingIndex].accountId = accountID.isEmpty ? accounts[existingIndex].accountId : accountID
                accounts[existingIndex].phone = record.phone.isEmpty ? accounts[existingIndex].phone : record.phone
                if let latitude = record.latitude, let longitude = record.longitude {
                    accounts[existingIndex].latitude = latitude
                    accounts[existingIndex].longitude = longitude
                } else if addressChanged {
                    accounts[existingIndex].latitude = nil
                    accounts[existingIndex].longitude = nil
                }
                if !accounts[existingIndex].tags.contains("CSV Import") {
                    accounts[existingIndex].tags.append("CSV Import")
                }
                if !accountID.isEmpty { accountIDIndex[accountID] = existingIndex }
                nameAddressIndex[Self.csvIdentityKey(
                    name: accounts[existingIndex].name,
                    address: accounts[existingIndex].address
                )] = existingIndex
                updated += 1
                continue
            }

            let newIndex = accounts.count
            accounts.append(
                .init(
                    id: UUID().uuidString,
                    name: record.name,
                    address: record.address.isEmpty ? "No address supplied" : record.address,
                    category: record.category,
                    accountId: accountID,
                    phone: record.phone,
                    favorite: false,
                    latitude: record.latitude,
                    longitude: record.longitude,
                    tags: ["CSV Import"],
                    notes: [], documents: [], equipment: [], locations: [], recent: []
                )
            )
            if !accountID.isEmpty { accountIDIndex[accountID] = newIndex }
            nameAddressIndex[Self.csvIdentityKey(
                name: record.name,
                address: record.address.isEmpty ? "No address supplied" : record.address
            )] = newIndex
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
            totalRows: analysis.records.count,
            messages: Array(messages.prefix(12))
        )
    }

    func accountsBackupData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(accounts)
    }

    func mergeAccountsBackup(_ data: Data) throws -> FireVaultBackupMergeResult {
        let incoming = try JSONDecoder().decode([FireVaultWorkspaceAccount].self, from: data)
        var existingIDs = Set(accounts.map(\.id))
        var existingAccountIDs = Set(
            accounts.map { Self.canonicalAccountID($0.accountId) }.filter { !$0.isEmpty }
        )
        var added = 0
        var preserved = 0

        for account in incoming {
            let accountID = Self.canonicalAccountID(account.accountId)
            let alreadyExists = existingIDs.contains(account.id)
                || (!accountID.isEmpty && existingAccountIDs.contains(accountID))
            if alreadyExists {
                preserved += 1
                continue
            }
            accounts.append(account)
            existingIDs.insert(account.id)
            if !accountID.isEmpty { existingAccountIDs.insert(accountID) }
            added += 1
        }

        persist()
        return .init(added: added, preserved: preserved)
    }

    func backupMediaRecords() throws -> [FireVaultVaultMediaRecord] {
        var records: [FireVaultVaultMediaRecord] = []
        for account in accounts {
            for document in account.documents {
                guard let fileName = document.mediaFileName,
                      fileName == URL(fileURLWithPath: fileName).lastPathComponent else { continue }
                let url = try mediaURL(accountID: account.id, fileName: fileName)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                records.append(
                    .init(
                        accountID: account.id,
                        fileName: fileName,
                        data: try Data(contentsOf: url, options: .mappedIfSafe)
                    )
                )
            }
        }
        return records
    }

    @discardableResult
    func installBackupMedia(
        _ records: [FireVaultVaultMediaRecord],
        allowedAccountIDs: Set<String>
    ) throws -> Int {
        var restored = 0
        for record in records where allowedAccountIDs.contains(record.accountID) && record.isValid {
            let url = try mediaURL(accountID: record.accountID, fileName: record.fileName)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try record.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            restored += 1
        }
        return restored
    }

    @discardableResult
    func deleteDocument(accountID: String, documentID: String) -> Bool {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == accountID }),
              let documentIndex = accounts[accountIndex].documents.firstIndex(where: { $0.id == documentID }) else {
            return false
        }
        let document = accounts[accountIndex].documents[documentIndex]
        if let fileName = document.mediaFileName,
           fileName == URL(fileURLWithPath: fileName).lastPathComponent,
           let url = try? mediaURL(accountID: accountID, fileName: fileName),
           FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                return false
            }
        }
        accounts[accountIndex].documents.remove(at: documentIndex)
        persist()
        return true
    }

    func mediaStorageReport() -> FireVaultMediaStorageReport {
        let referenced = referencedMediaPaths
        var storedFiles = Set<String>()
        var totalBytes: Int64 = 0
        guard let root = try? mediaRootURL(),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return .init(referencedFiles: referenced.count, orphanedFiles: 0, totalBytes: 0)
        }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            storedFiles.insert(url.standardizedFileURL.path)
            totalBytes += Int64(values.fileSize ?? 0)
        }
        return .init(
            referencedFiles: referenced.intersection(storedFiles).count,
            orphanedFiles: storedFiles.subtracting(referenced).count,
            totalBytes: totalBytes
        )
    }

    @discardableResult
    func removeOrphanedMedia() -> Int {
        let referenced = referencedMediaPaths
        guard let root = try? mediaRootURL(),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return 0 }
        var removed = 0
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  !referenced.contains(url.standardizedFileURL.path) else { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    private static func csvIdentityKey(name: String, address: String) -> String {
        "\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func persist() {
        applyCategoryRules()
        persistAccounts()
    }

    private func persistAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        if let accountArchiveURL {
            accountPersistenceGeneration += 1
            let generation = accountPersistenceGeneration
            Task {
                try? await FireVaultAccountArchiveWriter.shared.write(
                    data,
                    to: accountArchiveURL,
                    generation: generation
                )
            }
        } else {
            let key = demoMode ? Key.demoAccounts : Key.productionAccounts
            let backupKey = demoMode ? Key.demoAccountsBackup : Key.productionAccountsBackup
            if let existing = defaults.data(forKey: key),
               (try? JSONDecoder().decode([FireVaultWorkspaceAccount].self, from: existing)) != nil {
                defaults.set(existing, forKey: backupKey)
            }
            defaults.set(data, forKey: key)
        }
        let suppressionKey = demoMode
            ? Key.demoCategoryRuleSuppressions
            : Key.productionCategoryRuleSuppressions
        defaults.set(categoryRuleSuppressedAccountIDs.sorted(), forKey: suppressionKey)
    }

    @discardableResult
    private func applyCategoryRules() -> Int {
        var additions = 0
        for index in accounts.indices {
            guard !categoryRuleSuppressedAccountIDs.contains(accounts[index].id) else { continue }
            for rule in categoryRules where rule.isEnabled {
                let needle = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
                let tag = rule.categoryTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !needle.isEmpty, !tag.isEmpty else { continue }
                let source: String = switch rule.field {
                case .accountName: accounts[index].name
                case .address: accounts[index].address
                case .accountID: accounts[index].accountId
                case .category: accounts[index].category
                case .phone: accounts[index].phone
                }
                let matches = switch rule.condition {
                case .contains: source.localizedCaseInsensitiveContains(needle)
                case .beginsWith: source.lowercased().hasPrefix(needle.lowercased())
                case .equals: source.caseInsensitiveCompare(needle) == .orderedSame
                }
                if matches {
                    var changed = false
                    if accounts[index].category.caseInsensitiveCompare(tag) != .orderedSame {
                        accounts[index].category = tag
                        changed = true
                    }
                    if !accounts[index].tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                        accounts[index].tags.append(tag)
                        changed = true
                    }
                    if changed { additions += 1 }
                }
            }
        }
        return additions
    }

    private static func savedAccounts(defaults: UserDefaults, key: String) -> [FireVaultWorkspaceAccount]? {
        let backupKey = key == Key.demoAccounts ? Key.demoAccountsBackup : Key.productionAccountsBackup
        let decoded = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([FireVaultWorkspaceAccount].self, from: $0) }
            ?? defaults.data(forKey: backupKey)
                .flatMap { try? JSONDecoder().decode([FireVaultWorkspaceAccount].self, from: $0) }
        guard let decoded else { return nil }
        var seenIDs = Set<String>()
        return decoded.filter { seenIDs.insert($0.id).inserted }
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

    /// Repairs pre-integrity-build data without changing coordinates or any
    /// unrelated account fields. Re-running this migration is a no-op.
    @discardableResult
    private static func repairPlusCodes(
        in accounts: inout [FireVaultWorkspaceAccount],
        preferences: FireVaultPlusCodePreferences
    ) -> Bool {
        guard preferences.autoGenerate else { return false }
        var changed = false
        for accountIndex in accounts.indices {
            for locationIndex in accounts[accountIndex].locations.indices {
                guard let coordinate = accounts[accountIndex].locations[locationIndex].coordinate else { continue }
                let expected = FireVaultPlusCode.encode(coordinate, length: preferences.locationLength)
                guard accounts[accountIndex].locations[locationIndex].plusCode != expected else { continue }
                accounts[accountIndex].locations[locationIndex].plusCode = expected
                changed = true
            }
        }
        return changed
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
        FireVaultCSVImporter.parse(normalizedLineEndings(source), delimiter: explicitDelimiter)
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
