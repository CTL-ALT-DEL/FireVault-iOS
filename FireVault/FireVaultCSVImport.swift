import Foundation

enum FireVaultCSVField: String, CaseIterable, Identifiable {
    case accountName
    case address
    case city
    case state
    case postalCode
    case accountID
    case category
    case phone
    case latitude
    case longitude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accountName: "Account Name"
        case .address: "Street Address"
        case .city: "City"
        case .state: "State / Province"
        case .postalCode: "ZIP / Postal Code"
        case .accountID: "Account ID"
        case .category: "Category"
        case .phone: "Phone"
        case .latitude: "Latitude"
        case .longitude: "Longitude"
        }
    }

    fileprivate var aliases: Set<String> {
        switch self {
        case .accountName:
            ["name", "accountname", "sitename", "site", "customername", "customer",
             "companyname", "company", "businessname", "business", "clientname", "client",
             "propertyname", "property", "premisename", "premise", "locationname", "location",
             "displayname", "description"]
        case .address:
            ["address", "address1", "addressline1", "street", "streetaddress", "siteaddress",
             "serviceaddress", "locationaddress", "propertyaddress"]
        case .city: ["city", "town", "municipality"]
        case .state: ["state", "province", "region"]
        case .postalCode: ["zip", "zipcode", "postalcode", "postcode"]
        case .accountID:
            ["accountid", "accountnumber", "accountno", "customerid", "customernumber",
             "siteid", "sitenumber", "clientid", "clientnumber", "reference"]
        case .category: ["category", "type", "sitegroupnum", "sitegroupnumber"]
        case .phone: ["phone", "phonenumber", "telephone", "sitephone", "customerphone", "devicephone"]
        case .latitude: ["latitude", "lat", "y", "ycoord", "ycoordinate"]
        case .longitude: ["longitude", "lon", "lng", "long", "x", "xcoord", "xcoordinate"]
        }
    }
}

enum FireVaultCSVRowStatus: String, Equatable {
    case successful = "Successful"
    case review = "Review"
    case rejected = "Rejected"
}

struct FireVaultCSVRowResult: Identifiable, Equatable {
    let id: Int
    let rowNumber: Int
    let status: FireVaultCSVRowStatus
    let accountName: String
    let message: String
    let latitude: Double?
    let longitude: Double?
}

struct FireVaultCSVMapping: Equatable {
    var columns: [FireVaultCSVField: Int]

    subscript(field: FireVaultCSVField) -> Int? {
        get { columns[field] }
        set { columns[field] = newValue }
    }
}

struct FireVaultCSVImportPreview: Equatable {
    let headers: [String]
    let mapping: FireVaultCSVMapping
    let rows: [FireVaultCSVRowResult]
    let requiresMappingReview: Bool
    let mappingMessages: [String]
    let delimiterName: String

    var successful: Int { rows.filter { $0.status == .successful }.count }
    var review: Int { rows.filter { $0.status == .review }.count }
    var rejected: Int { rows.filter { $0.status == .rejected }.count }
    var swappedCoordinateRows: Int {
        rows.filter { $0.message.localizedCaseInsensitiveContains("swapped") }.count
    }
}

struct FireVaultCSVParsedRecord: Equatable {
    let rowNumber: Int
    let name: String
    let address: String
    let addressLine1: String
    let city: String
    let state: String
    let postalCode: String
    let category: String
    let accountID: String
    let phone: String
    let latitude: Double?
    let longitude: Double?
    let rowResult: FireVaultCSVRowResult
}

struct FireVaultCSVAnalysis {
    let preview: FireVaultCSVImportPreview
    let records: [FireVaultCSVParsedRecord]
}

enum FireVaultCSVImportError: LocalizedError {
    case unreadableEncoding
    case empty
    case missingAccountNameMapping

    var errorDescription: String? {
        switch self {
        case .unreadableEncoding: "The CSV text encoding could not be read."
        case .empty: "The CSV file is empty."
        case .missingAccountNameMapping: "Choose which column contains the account name."
        }
    }
}

struct FireVaultCSVImporter {
    static func analyze(
        _ data: Data,
        mapping override: FireVaultCSVMapping? = nil,
        correctSwappedCoordinates: Bool = false
    ) throws -> FireVaultCSVAnalysis {
        guard var source = decode(data) else { throw FireVaultCSVImportError.unreadableEncoding }
        source = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var explicitDelimiter: Character?
        if let firstBreak = source.firstIndex(of: "\n") {
            let firstLine = cleaned(String(source[..<firstBreak]))
            if firstLine.lowercased().hasPrefix("sep="), let separator = firstLine.dropFirst(4).first {
                explicitDelimiter = separator
                source = String(source[source.index(after: firstBreak)...])
            }
        }

        let delimiter = explicitDelimiter ?? detectedDelimiter(in: source)
        let table = parse(source, delimiter: delimiter)
        guard let rawHeaders = table.first, !rawHeaders.isEmpty else { throw FireVaultCSVImportError.empty }

        let headers = rawHeaders.map { cleaned($0) }
        let normalizedHeaders = headers.map { normalizedHeader($0) }
        var suggested = suggestedMapping(headers: normalizedHeaders)
        if suggested.requiresReview,
           suggested.mapping[.accountName] == 0,
           let firstHeader = headers.first {
            suggested.messages.append("Used “\(firstHeader.isEmpty ? "Column 1" : firstHeader)” as the account-name column.")
        }
        let mapping = override ?? suggested.mapping
        guard mapping[.accountName] != nil else { throw FireVaultCSVImportError.missingAccountNameMapping }

        let nonemptyRows = table.dropFirst().enumerated().filter {
            $0.element.contains { !cleaned($0).isEmpty }
        }
        var results: [FireVaultCSVRowResult] = []
        var records: [FireVaultCSVParsedRecord] = []
        var seenAccountIDs: Set<String> = []

        for (offset, row) in nonemptyRows {
            let rowNumber = offset + 2
            func value(_ field: FireVaultCSVField) -> String {
                guard let index = mapping[field], row.indices.contains(index) else { return "" }
                return cleaned(row[index])
            }

            let name = value(.accountName)
            let accountID = canonicalAccountID(value(.accountID))
            let street = value(.address)
            let city = value(.city)
            let state = value(.state)
            let postalCode = value(.postalCode)
            let address = [street, city, state, postalCode]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")

            var latitude = coordinate(value(.latitude))
            var longitude = coordinate(value(.longitude))
            var status: FireVaultCSVRowStatus = .successful
            var message = "Ready to import."

            if name.isEmpty {
                status = .rejected
                message = "Missing account name."
            } else if !accountID.isEmpty, !seenAccountIDs.insert(accountID).inserted {
                status = .rejected
                message = "Duplicate Account ID \(accountID) appears more than once in this file."
            } else if latitude != nil || longitude != nil {
                if let lat = latitude, let lon = longitude {
                    if isValid(latitude: lat, longitude: lon) {
                        // Valid as supplied.
                    } else if isValid(latitude: lon, longitude: lat) {
                        if correctSwappedCoordinates {
                            latitude = lon
                            longitude = lat
                            message = "Likely swapped latitude/longitude corrected."
                        } else {
                            status = .review
                            message = "Latitude/longitude appear swapped. Confirm correction before import."
                            latitude = nil
                            longitude = nil
                        }
                    } else {
                        status = .review
                        message = "Coordinates are outside valid ranges and will be ignored."
                        latitude = nil
                        longitude = nil
                    }
                } else {
                    status = .review
                    message = "Only one coordinate is present; both values are required and will be ignored."
                    latitude = nil
                    longitude = nil
                }
            }

            let result = FireVaultCSVRowResult(
                id: rowNumber,
                rowNumber: rowNumber,
                status: status,
                accountName: name.isEmpty ? "Unnamed row" : name,
                message: message,
                latitude: latitude,
                longitude: longitude
            )
            results.append(result)
            records.append(
                .init(
                    rowNumber: rowNumber,
                    name: name,
                    address: address,
                    addressLine1: street,
                    city: city,
                    state: state,
                    postalCode: postalCode,
                    category: value(.category),
                    accountID: accountID,
                    phone: value(.phone),
                    latitude: latitude,
                    longitude: longitude,
                    rowResult: result
                )
            )
        }

        let review = suggested.requiresReview || override == nil && suggested.mapping[.accountName] == nil
        return .init(
            preview: .init(
                headers: headers,
                mapping: mapping,
                rows: results,
                requiresMappingReview: review,
                mappingMessages: suggested.messages,
                delimiterName: delimiterDescription(delimiter)
            ),
            records: records
        )
    }

    static func parse(_ source: String, delimiter: Character? = nil) -> [[String]] {
        let delimiter = delimiter ?? detectedDelimiter(in: source)
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
            } else if character == "\n", !quoted {
                row.append(field)
                if row.contains(where: { !cleaned($0).isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = next
        }
        row.append(field)
        if row.contains(where: { !cleaned($0).isEmpty }) { rows.append(row) }
        return rows
    }

    private static func suggestedMapping(headers: [String]) -> (
        mapping: FireVaultCSVMapping,
        requiresReview: Bool,
        messages: [String]
    ) {
        var columns: [FireVaultCSVField: Int] = [:]
        var claimed: Set<Int> = []
        var messages: [String] = []
        var requiresReview = false

        for field in FireVaultCSVField.allCases {
            let matches = headers.indices.filter { field.aliases.contains(headers[$0]) }
            if let first = matches.first, !claimed.contains(first) {
                columns[field] = first
                claimed.insert(first)
            }
            if matches.count > 1 {
                requiresReview = true
                messages.append("Multiple columns could be \(field.title).")
            }
        }

        if columns[.accountName] == nil {
            let likely = headers.indices.filter { index in
                ["name", "customer", "site", "company", "business", "client", "property", "premise", "location"]
                    .contains { headers[index].contains($0) }
            }
            if likely.count == 1 {
                columns[.accountName] = likely[0]
                messages.append("Please confirm column \(likely[0] + 1) as the account-name column.")
                requiresReview = true
            } else {
                if !headers.isEmpty {
                    columns[.accountName] = 0
                    messages.append("The account-name column was ambiguous; column 1 is selected for review.")
                } else {
                    messages.append("The account-name column could not be identified.")
                }
                requiresReview = true
            }
        }
        return (.init(columns: columns), requiresReview, messages)
    }

    private static func normalizedHeader(_ value: String) -> String {
        cleaned(value).lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\u{feff}")))
    }

    private static func coordinate(_ value: String) -> Double? {
        guard !value.isEmpty else { return nil }
        return Double(value.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces))
    }

    private static func isValid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite &&
            (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    private static func decode(_ data: Data) -> String? {
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252, .macOSRoman] {
            if let value = String(data: data, encoding: encoding) { return value }
        }
        return nil
    }

    private static func detectedDelimiter(in source: String) -> Character {
        let candidates: [Character] = [",", ";", "\t", "|"]
        let sampleLines = source.split(separator: "\n", omittingEmptySubsequences: true).prefix(5)
        var scores = Dictionary(uniqueKeysWithValues: candidates.map { ($0, 0) })
        for line in sampleLines {
            var quoted = false
            for character in line {
                if character == "\"" { quoted.toggle() }
                else if !quoted, scores[character] != nil { scores[character, default: 0] += 1 }
            }
        }
        return candidates.max { scores[$0, default: 0] < scores[$1, default: 0] }
            .flatMap { scores[$0, default: 0] > 0 ? $0 : nil } ?? ","
    }

    private static func delimiterDescription(_ delimiter: Character) -> String {
        switch delimiter {
        case ",": "Comma"
        case ";": "Semicolon"
        case "\t": "Tab"
        case "|": "Pipe"
        default: String(delimiter)
        }
    }

    static func canonicalAccountID(_ value: String) -> String {
        let hyphens = Set("‐‑‒–—―−﹘﹣－")
        return cleaned(value)
            .drop(while: { $0 == "'" })
            .map { hyphens.contains($0) ? "-" : String($0).uppercased() }
            .joined()
            .filter { !$0.isWhitespace }
    }
}
