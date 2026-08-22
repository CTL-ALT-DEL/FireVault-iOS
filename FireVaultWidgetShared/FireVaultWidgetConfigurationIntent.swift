//
//  FireVaultWidgetConfigurationIntent.swift
//  FireVault
//
//  Privacy-conscious account choices shared with the widget extension.
//

import AppIntents
import Foundation

struct FireVaultWidgetAccountEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "FireVault Account")
    static var defaultQuery = FireVaultWidgetAccountEntityQuery()

    let id: String

    @Property(title: "Site Name")
    var name: String

    @Property(title: "Account ID")
    var accountID: String

    @Property(title: "Category")
    var category: String

    @Property(title: "Address")
    var address: String

    @Property(title: "Drop Pins")
    var dropPinCount: Int

    var displayRepresentation: DisplayRepresentation {
        let detail = accountID.isEmpty ? category : "\(accountID) • \(category)"
        return DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    init(summary: FireVaultWidgetAccountSummary) {
        id = summary.id
        name = summary.name
        accountID = summary.accountID
        category = summary.category
        address = summary.address
        dropPinCount = summary.dropPinCount
    }

    var summary: FireVaultWidgetAccountSummary {
        FireVaultWidgetAccountSummary(
            id: id,
            name: name,
            accountID: accountID,
            category: category,
            address: address,
            dropPinCount: dropPinCount
        )
    }
}

struct FireVaultWidgetAccountEntityQuery: EntityStringQuery {
    func entities(
        for identifiers: [FireVaultWidgetAccountEntity.ID]
    ) async throws -> [FireVaultWidgetAccountEntity] {
        let byID = Dictionary(uniqueKeysWithValues: allEntities.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0] }
    }

    func entities(matching string: String) async throws -> [FireVaultWidgetAccountEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allEntities }
        return allEntities.filter { entity in
            [entity.name, entity.accountID, entity.category, entity.address]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func suggestedEntities() async throws -> [FireVaultWidgetAccountEntity] {
        allEntities
    }

    private var allEntities: [FireVaultWidgetAccountEntity] {
        (FireVaultWidgetSharedStore.load().accountChoices ?? [])
            .map(FireVaultWidgetAccountEntity.init(summary:))
    }
}

struct FireVaultAccountWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose FireVault Account"
    static var description = IntentDescription(
        "Select the current account or one of your favorite FireVault accounts."
    )

    @Parameter(title: "Account")
    var account: FireVaultWidgetAccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$account)")
    }
}
