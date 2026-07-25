//
//  FireVaultDemoShowroom.swift
//  FireVault
//
//  Deterministic, isolated showroom data for Build 1.08.06.
//

import Foundation

@MainActor
enum FireVaultDemoShowroom {
    static let seedVersion = 2
    static let accountCount = 30
    static let breadcrumbDayCount = 7

    private static let demoAccountsKey = "firevault.native.demo-accounts.v1"
    private static let seedVersionKey = "firevault.native.demo-showroom.seed-version"

    static func installAccountsIfNeeded(
        into store: FireVaultStore,
        force: Bool = false,
        defaults: UserDefaults = .standard
    ) {
        guard store.demoMode else { return }

        let installedVersion = defaults.integer(forKey: seedVersionKey)
        let needsUpgrade = installedVersion < seedVersion
        let hasLegacyDemo = store.accounts.count <= 4
        guard force || needsUpgrade || hasLegacyDemo else { return }

        store.accounts = accounts
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: demoAccountsKey)
        }
        defaults.set(seedVersion, forKey: seedVersionKey)
    }

    static func makeBreadcrumbStore(forceReset: Bool = false) -> FireVaultBreadcrumbStore {
        let url = breadcrumbArchiveURL
        if forceReset || !FileManager.default.fileExists(atPath: url.path) {
            writeBreadcrumbArchive(to: url)
        }
        return FireVaultBreadcrumbStore(archiveURL: url)
    }

    static var summary: (equipment: Int, locations: Int, notes: Int, routePoints: Int) {
        let allAccounts = accounts
        let days = breadcrumbDays
        return (
            equipment: allAccounts.reduce(0) { $0 + $1.equipment.count },
            locations: allAccounts.reduce(0) { $0 + $1.locations.count },
            notes: allAccounts.reduce(0) { $0 + $1.notes.count },
            routePoints: days.reduce(0) { $0 + $1.points.count }
        )
    }

    static let accounts: [FireVaultWorkspaceAccount] = siteSeeds.enumerated().map { index, site in
        makeAccount(index: index, site: site)
    }

    static let breadcrumbDays: [FireVaultBreadcrumbDay] = makeBreadcrumbDays()

    private static var breadcrumbArchiveURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("FireVault", isDirectory: true)
            .appendingPathComponent("breadcrumbs-demo-v2.json")
    }

    private static func writeBreadcrumbArchive(to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.fireVaultBreadcrumbs.encode(breadcrumbDays)
            try data.write(to: url, options: .atomic)
        } catch {
            // Demo seeding must never prevent the production app from opening.
        }
    }

    private struct SiteSeed {
        let name: String
        let address: String
        let category: String
        let latitude: Double
        let longitude: Double
        let favorite: Bool
    }

    private static let siteSeeds: [SiteSeed] = [
        .init(name: "Pioneer Elementary School", address: "825 West Jefferson Street, Boise, ID 83702", category: "Education", latitude: 43.6194, longitude: -116.2024, favorite: true),
        .init(name: "Central Valley High School", address: "1100 North 8th Street, Boise, ID 83702", category: "Education", latitude: 43.6260, longitude: -116.1997, favorite: false),
        .init(name: "Mountain View Medical Center", address: "1550 River Street, Boise, ID 83702", category: "Healthcare", latitude: 43.6178, longitude: -116.1970, favorite: true),
        .init(name: "Westside Family Clinic", address: "2620 West State Street, Boise, ID 83702", category: "Healthcare", latitude: 43.6226, longitude: -116.2206, favorite: false),
        .init(name: "Granite Ridge Office Plaza", address: "350 North 9th Street, Boise, ID 83702", category: "Commercial", latitude: 43.6182, longitude: -116.2055, favorite: false),
        .init(name: "High Plains Distribution Center", address: "9100 West Emerald Street, Boise, ID 83704", category: "Warehouse", latitude: 43.6109, longitude: -116.2920, favorite: true),
        .init(name: "Summit Lodge Hotel", address: "1420 West Grove Street, Boise, ID 83702", category: "Hospitality", latitude: 43.6150, longitude: -116.2143, favorite: false),
        .init(name: "Cottonwood Apartments", address: "1800 North 15th Street, Boise, ID 83702", category: "Multifamily", latitude: 43.6323, longitude: -116.2108, favorite: false),
        .init(name: "Prairie Hills Shopping Center", address: "5200 West Franklin Road, Boise, ID 83705", category: "Retail", latitude: 43.6022, longitude: -116.2586, favorite: false),
        .init(name: "FreshMart Grocery", address: "830 East Parkcenter Boulevard, Boise, ID 83706", category: "Retail", latitude: 43.5848, longitude: -116.1729, favorite: true),
        .init(name: "Red Butte Manufacturing", address: "4700 South Apple Street, Boise, ID 83716", category: "Industrial", latitude: 43.5650, longitude: -116.1373, favorite: false),
        .init(name: "Grace Community Church", address: "2200 North Cole Road, Boise, ID 83704", category: "Assembly", latitude: 43.6368, longitude: -116.2745, favorite: false),
        .init(name: "Regional Public Library", address: "715 South Capitol Boulevard, Boise, ID 83702", category: "Government", latitude: 43.6102, longitude: -116.2077, favorite: true),
        .init(name: "County Courthouse Annex", address: "451 West Front Street, Boise, ID 83702", category: "Government", latitude: 43.6125, longitude: -116.2049, favorite: false),
        .init(name: "Metro Police Operations Center", address: "333 North Mark Stall Place, Boise, ID 83704", category: "Public Safety", latitude: 43.6075, longitude: -116.2716, favorite: false),
        .init(name: "Station 7 Firehouse", address: "1666 North Cole Road, Boise, ID 83704", category: "Public Safety", latitude: 43.6287, longitude: -116.2738, favorite: false),
        .init(name: "High Plains Airport Terminal", address: "3201 Airport Way, Boise, ID 83705", category: "Transportation", latitude: 43.5658, longitude: -116.2228, favorite: true),
        .init(name: "Cloud Peak Data Center", address: "7600 West Victory Road, Boise, ID 83709", category: "Data Center", latitude: 43.5884, longitude: -116.2820, favorite: true),
        .init(name: "Western Technical College", address: "600 South Capitol Boulevard, Boise, ID 83702", category: "Education", latitude: 43.6115, longitude: -116.2070, favorite: false),
        .init(name: "Meadowbrook Senior Living", address: "3900 North Bogus Basin Road, Boise, ID 83702", category: "Healthcare", latitude: 43.6526, longitude: -116.2080, favorite: false),
        .init(name: "Frontier History Museum", address: "610 Julia Davis Drive, Boise, ID 83702", category: "Cultural", latitude: 43.6087, longitude: -116.1999, favorite: false),
        .init(name: "Silver Spur Resort", address: "2450 South Vista Avenue, Boise, ID 83705", category: "Hospitality", latitude: 43.5780, longitude: -116.2138, favorite: false),
        .init(name: "Riverside Grill", address: "1500 Shoreline Drive, Boise, ID 83702", category: "Restaurant", latitude: 43.6170, longitude: -116.2260, favorite: false),
        .init(name: "Arctic Cold Storage", address: "6900 South Eisenman Road, Boise, ID 83716", category: "Industrial", latitude: 43.5382, longitude: -116.1255, favorite: true),
        .init(name: "River Water Treatment Facility", address: "11818 West Joplin Road, Boise, ID 83714", category: "Utility", latitude: 43.6703, longitude: -116.3310, favorite: false),
        .init(name: "Mountain West Utility Substation", address: "8400 West Overland Road, Boise, ID 83709", category: "Utility", latitude: 43.5901, longitude: -116.2968, favorite: false),
        .init(name: "Administrative Services Center", address: "700 West State Street, Boise, ID 83702", category: "Government", latitude: 43.6172, longitude: -116.2027, favorite: false),
        .init(name: "Northside Community Center", address: "2600 North 28th Street, Boise, ID 83703", category: "Assembly", latitude: 43.6437, longitude: -116.2298, favorite: false),
        .init(name: "Summit Conference Center", address: "850 West Front Street, Boise, ID 83702", category: "Assembly", latitude: 43.6163, longitude: -116.2110, favorite: true),
        .init(name: "Iron Creek Industrial Complex", address: "10900 West Executive Drive, Boise, ID 83713", category: "Industrial", latitude: 43.6177, longitude: -116.3272, favorite: true)
    ]

    private static let manufacturers = [
        ("Notifier", "NFS2-3030"),
        ("Fire-Lite", "ES-200X"),
        ("Silent Knight", "6820"),
        ("Potter", "IPA-4000"),
        ("Edwards / EST", "EST4"),
        ("Siemens", "FC2025"),
        ("Simplex", "4100ES"),
        ("Gamewell-FCI", "S3 Series")
    ]

    private static func makeAccount(index: Int, site: SiteSeed) -> FireVaultWorkspaceAccount {
        let sequence = index + 1
        let equipmentCount = 6 + (index % 5)
        let locationCount = 4 + (index % 3)
        let noteCount = 2 + (index % 4)

        let equipment = (0..<equipmentCount).map { item in
            makeEquipment(siteIndex: index, itemIndex: item)
        }
        let locations = makeLocations(
            siteIndex: index,
            count: locationCount,
            latitude: site.latitude,
            longitude: site.longitude
        )
        let notes = (0..<noteCount).map { item in
            makeNote(siteIndex: index, itemIndex: item)
        }
        let documents = [
            FireVaultWorkspaceDocument(
                id: "demo-\(sequence)-doc-riser",
                title: "Fire alarm riser diagram",
                subtitle: "Sample 3-page scan • DEMO",
                kind: "scan",
                date: "Jul 21"
            ),
            FireVaultWorkspaceDocument(
                id: "demo-\(sequence)-doc-report",
                title: "Annual inspection report",
                subtitle: "Sample PDF • DEMO",
                kind: "file",
                date: "Jul 18"
            )
        ]
        let recent = [
            FireVaultWorkspaceRecent(id: "demo-\(sequence)-recent-1", title: "Field note updated", subtitle: notes.first?.text ?? "Demo activity", kind: "note", date: "Today"),
            FireVaultWorkspaceRecent(id: "demo-\(sequence)-recent-2", title: "Equipment reviewed", subtitle: equipment.first?.title ?? "System equipment", kind: "equipment", date: "Yesterday"),
            FireVaultWorkspaceRecent(id: "demo-\(sequence)-recent-3", title: "Riser diagram opened", subtitle: "Sample document activity", kind: "document", date: "Jul 21")
        ]

        return .init(
            id: String(format: "demo-showroom-%02d", sequence),
            name: site.name,
            address: site.address,
            category: site.category,
            accountId: String(format: "DEMO-%04d", 1000 + sequence),
            phone: String(format: "208555%04d", sequence),
            favorite: site.favorite,
            latitude: site.latitude,
            longitude: site.longitude,
            tags: ["DEMO", site.category, sequence.isMultiple(of: 3) ? "Annual Inspection" : "Service Account"],
            notes: notes,
            documents: documents,
            equipment: equipment,
            locations: locations,
            recent: recent
        )
    }

    private static func makeEquipment(siteIndex: Int, itemIndex: Int) -> FireVaultWorkspaceEquipment {
        let manufacturer = manufacturers[(siteIndex + itemIndex) % manufacturers.count]
        let types = [
            ("Fire Alarm Control Panel", "Main system panel"),
            ("Remote Annunciator", "Lobby annunciator"),
            ("NAC Power Supply", "Remote notification power"),
            ("Cellular Communicator", "Dual-path communicator"),
            ("Sprinkler Monitoring Module", "Riser supervisory interface"),
            ("Elevator Recall Interface", "Primary and alternate recall"),
            ("Voice Evacuation Panel", "Emergency voice system"),
            ("Fire Pump Controller", "Pump status monitoring"),
            ("BDA System", "Radio enhancement head-end"),
            ("Generator Interface", "Emergency power monitoring")
        ]
        let type = types[itemIndex % types.count]
        let title = itemIndex == 0
            ? "\(manufacturer.0) \(manufacturer.1)"
            : "\(type.0)"
        let subtitle = itemIndex == 0
            ? "Main fire alarm panel • \(type.1)"
            : "\(manufacturer.0) sample equipment • \(type.1)"
        let status = itemIndex.isMultiple(of: 7) && itemIndex > 0 ? "Monitor" : "Active"
        return .init(
            id: "demo-eq-\(siteIndex + 1)-\(itemIndex + 1)",
            title: title,
            subtitle: subtitle,
            status: status
        )
    }

    private static func makeLocations(
        siteIndex: Int,
        count: Int,
        latitude: Double,
        longitude: Double
    ) -> [FireVaultWorkspaceLocation] {
        let templates = [
            ("Main Fire Alarm Panel", "Main electrical room; check in before entry", "Panel", 0.00005, 0.00004),
            ("Riser Room", "Exterior sprinkler riser room on service side", "Riser Room", -0.00018, 0.00016),
            ("Technician Parking", "Use marked service parking near loading area", "Parking", 0.00024, -0.00020),
            ("Front Entrance", "Primary customer check-in entrance", "Entrance", 0.00010, 0.00022),
            ("Remote Annunciator", "Inside main lobby beside security desk", "Annunciator", -0.00008, -0.00012),
            ("Loading Dock", "Service entrance available after 7 AM", "Service", -0.00025, 0.00028)
        ]
        return templates.prefix(count).enumerated().map { itemIndex, item in
            .init(
                id: "demo-loc-\(siteIndex + 1)-\(itemIndex + 1)",
                label: item.0,
                subtitle: item.1,
                type: item.2,
                plusCode: String(format: "85M5+%02d%02d", siteIndex + 10, itemIndex + 10),
                latitude: latitude + item.3,
                longitude: longitude + item.4
            )
        }
    }

    private static func makeNote(siteIndex: Int, itemIndex: Int) -> FireVaultWorkspaceNote {
        let templates = [
            ("Arrival instructions", "Call the facilities contact before arrival and check in at the main entrance."),
            ("Panel access", "Main panel key is maintained by facilities. Do not leave the panel unattended while open."),
            ("Recent service", "Battery load test passed during the previous visit; verify date labels at the next inspection."),
            ("Ground fault history", "Intermittent ground fault was previously traced to an exterior circuit. Recheck after wet weather."),
            ("Communicator", "Verify cellular signal strength and both reporting paths during the next scheduled service."),
            ("Coordination", "Coordinate sprinkler and elevator testing with the customer before placing systems on test.")
        ]
        let note = templates[(siteIndex + itemIndex) % templates.count]
        return .init(
            id: "demo-note-\(siteIndex + 1)-\(itemIndex + 1)",
            title: note.0,
            text: note.1,
            date: itemIndex == 0 ? "Today" : "Jul \(20 - itemIndex)"
        )
    }

    private static func makeBreadcrumbDays() -> [FireVaultBreadcrumbDay] {
        let routes = [
            [0, 2, 9, 1],
            [5, 6, 4, 22],
            [2, 19, 3],
            [10, 23, 25, 24],
            [13, 12, 27, 26],
            [14, 15, 8],
            [16, 17, 18, 28]
        ]
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        return routes.enumerated().map { dayOffset, route in
            let day = calendar.date(byAdding: .day, value: -(dayOffset + 1), to: today) ?? today
            let startedAt = calendar.date(byAdding: .minute, value: 7 * 60 + 35, to: day) ?? day
            var currentTime = startedAt
            var points: [FireVaultBreadcrumbPoint] = []
            var stops: [FireVaultBreadcrumbStop] = []
            var previous = (latitude: 43.6150, longitude: -116.2023)

            for (stopOrder, accountIndex) in route.enumerated() {
                let account = accounts[accountIndex]
                guard let latitude = account.latitude, let longitude = account.longitude else { continue }
                let destination = (latitude: latitude, longitude: longitude)
                let travelMinutes = 18 + ((dayOffset + stopOrder) % 4) * 6
                let segment = routePoints(
                    from: previous,
                    to: destination,
                    start: currentTime,
                    durationMinutes: travelMinutes,
                    idPrefix: "demo-day-\(dayOffset + 1)-segment-\(stopOrder + 1)"
                )
                points.append(contentsOf: segment)
                currentTime = calendar.date(byAdding: .minute, value: travelMinutes, to: currentTime) ?? currentTime

                let arrival = currentTime
                let visitMinutes = 42 + ((accountIndex + dayOffset) % 4) * 18
                let departure = calendar.date(byAdding: .minute, value: visitMinutes, to: arrival) ?? arrival
                stops.append(
                    .init(
                        id: stableUUID(namespace: 300 + dayOffset, value: stopOrder),
                        arrival: arrival,
                        departure: departure,
                        latitude: latitude,
                        longitude: longitude,
                        accountID: account.id,
                        accountName: account.name,
                        accountAddress: account.address,
                        technicianNote: demoStopNote(stopOrder),
                        isPersonal: false
                    )
                )

                points.append(contentsOf: stationaryPoints(
                    at: destination,
                    arrival: arrival,
                    departure: departure,
                    idPrefix: "demo-day-\(dayOffset + 1)-stop-\(stopOrder + 1)"
                ))
                currentTime = departure
                previous = destination
            }

            let returnSegment = routePoints(
                from: previous,
                to: (latitude: 43.6150, longitude: -116.2023),
                start: currentTime,
                durationMinutes: 22,
                idPrefix: "demo-day-\(dayOffset + 1)-return"
            )
            points.append(contentsOf: returnSegment)
            let endedAt = calendar.date(byAdding: .minute, value: 22, to: currentTime) ?? currentTime

            return .init(
                id: stableUUID(namespace: 200, value: dayOffset),
                startedAt: startedAt,
                endedAt: endedAt,
                isPaused: false,
                points: points.sorted { $0.timestamp < $1.timestamp },
                stops: stops
            )
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    private static func routePoints(
        from start: (latitude: Double, longitude: Double),
        to end: (latitude: Double, longitude: Double),
        start startTime: Date,
        durationMinutes: Int,
        idPrefix: String
    ) -> [FireVaultBreadcrumbPoint] {
        let count = max(8, durationMinutes / 2)
        return (0...count).map { index in
            let fraction = Double(index) / Double(count)
            let curve = sin(fraction * .pi) * 0.0012
            return .init(
                id: stableUUID(namespace: abs(idPrefix.hashValue % 900) + 400, value: index),
                timestamp: startTime.addingTimeInterval(Double(durationMinutes * 60) * fraction),
                latitude: start.latitude + ((end.latitude - start.latitude) * fraction) + curve,
                longitude: start.longitude + ((end.longitude - start.longitude) * fraction) - (curve * 0.6),
                horizontalAccuracy: 8
            )
        }
    }

    private static func stationaryPoints(
        at coordinate: (latitude: Double, longitude: Double),
        arrival: Date,
        departure: Date,
        idPrefix: String
    ) -> [FireVaultBreadcrumbPoint] {
        let duration = max(1, departure.timeIntervalSince(arrival))
        return (1...4).map { index in
            let fraction = Double(index) / 5.0
            let jitter = Double(index - 2) * 0.000006
            return .init(
                id: stableUUID(namespace: abs(idPrefix.hashValue % 900) + 1400, value: index),
                timestamp: arrival.addingTimeInterval(duration * fraction),
                latitude: coordinate.latitude + jitter,
                longitude: coordinate.longitude - jitter,
                horizontalAccuracy: 6
            )
        }
    }

    private static func demoStopNote(_ index: Int) -> String {
        let notes = [
            "DEMO: Reviewed panel and saved a field note.",
            "DEMO: Opened the equipment record and captured a sample photo.",
            "DEMO: Checked the riser-room location and recorded inspection activity.",
            "DEMO: Added a sample document scan and updated site notes."
        ]
        return notes[index % notes.count]
    }

    private static func stableUUID(namespace: Int, value: Int) -> UUID {
        let string = String(format: "%08X-0000-4000-8000-%012X", namespace & 0xFFFF_FFFF, value & 0xFFFF_FFFF)
        return UUID(uuidString: string) ?? UUID()
    }
}
