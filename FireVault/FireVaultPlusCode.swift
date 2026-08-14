//
//  FireVaultPlusCode.swift
//  FireVault
//
//  Offline Open Location Code (Plus Code) support.
//

import CoreLocation
import Foundation

enum FireVaultPlusCode {
    private static let alphabet = Array("23456789CFGHJMPQRVWX")
    private static let alphabetSet = CharacterSet(charactersIn: "23456789CFGHJMPQRVWX")
    private static let pairResolutions = [20.0, 1.0, 0.05, 0.0025, 0.000125]
    private static let separator: Character = "+"
    private static let separatorPosition = 8

    /// Encodes a WGS84 coordinate as a full 10- or 11-digit Plus Code.
    static func encode(_ coordinate: CLLocationCoordinate2D, length: Int = 10) -> String {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return "" }
        let requestedLength = length >= 11 ? 11 : 10
        var latitude = min(90, max(-90, coordinate.latitude))
        if latitude == 90 { latitude -= 0.000000001 }
        var longitude = coordinate.longitude
        while longitude < -180 { longitude += 360 }
        while longitude >= 180 { longitude -= 360 }
        latitude += 90
        longitude += 180

        var digits = ""
        for resolution in pairResolutions {
            let latitudeDigit = min(19, Int(latitude / resolution))
            let longitudeDigit = min(19, Int(longitude / resolution))
            digits.append(alphabet[latitudeDigit])
            digits.append(alphabet[longitudeDigit])
            latitude -= Double(latitudeDigit) * resolution
            longitude -= Double(longitudeDigit) * resolution
        }

        if requestedLength == 11 {
            let latitudeDigit = min(4, Int(latitude / (0.000125 / 5)))
            let longitudeDigit = min(3, Int(longitude / (0.000125 / 4)))
            digits.append(alphabet[latitudeDigit * 4 + longitudeDigit])
        }

        let separatorIndex = digits.index(digits.startIndex, offsetBy: separatorPosition)
        digits.insert(separator, at: separatorIndex)
        return digits
    }

    /// Returns a normalized full Plus Code or nil. Short/compound codes are
    /// intentionally rejected because FireVault must persist unambiguous points.
    static func normalizedFullCode(_ value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { !$0.isWhitespace }
        guard isValidFullCode(normalized) else { return nil }
        return normalized
    }

    static func isValidFullCode(_ value: String) -> Bool {
        let characters = Array(value)
        guard characters.count == 11 || characters.count == 12,
              characters.filter({ $0 == separator }).count == 1,
              characters.indices.contains(separatorPosition),
              characters[separatorPosition] == separator else { return false }
        let digits = characters.filter { $0 != separator }
        guard digits.count == 10 || digits.count == 11,
              digits.allSatisfy({ character in
                  character.unicodeScalars.allSatisfy(alphabetSet.contains)
              }) else { return false }
        guard let first = alphabet.firstIndex(of: digits[0]), first < 9,
              let second = alphabet.firstIndex(of: digits[1]), second < 18 else { return false }
        return true
    }

    /// Coordinates are authoritative. This prevents an edited or imported pin
    /// from retaining a Plus Code that points somewhere else.
    static func codeForStorage(
        enteredCode: String,
        latitude: Double?,
        longitude: Double?,
        length: Int = 11,
        autoGenerate: Bool = true
    ) -> String? {
        if let latitude, let longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            if autoGenerate { return encode(coordinate, length: length) }
        }
        let trimmed = enteredCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return normalizedFullCode(trimmed)
    }

    static func googleMapsURL(for code: String) -> URL? {
        guard let code = normalizedFullCode(code) else { return nil }
        // A literal "+" in a URL query is commonly decoded as a space. Google
        // Maps requires the Plus Code separator itself, so preserve it as %2B.
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        let encodedCode = code.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = "api=1&query=\(encodedCode)"
        return components?.url
    }
}
