import Foundation
import GymPassShared

public struct PassField: Codable, Sendable, Equatable {
    public var key: String
    public var label: String
    public var value: String
    public var changeMessage: String?
    public var textAlignment: String?

    public init(key: String, label: String, value: String, changeMessage: String? = nil, textAlignment: String? = nil) {
        self.key = key
        self.label = label
        self.value = value
        self.changeMessage = changeMessage
        self.textAlignment = textAlignment
    }
}

public struct PassBarcode: Codable, Sendable, Equatable {
    public var format: String
    public var message: String
    public var messageEncoding: String
    public var altText: String?

    public init(format: String, message: String, messageEncoding: String, altText: String? = nil) {
        self.format = format
        self.message = message
        self.messageEncoding = messageEncoding
        self.altText = altText
    }

    public static func qr(message: String, altText: String? = nil) -> PassBarcode {
        PassBarcode(format: "PKBarcodeFormatQR", message: message, messageEncoding: "iso-8859-1", altText: altText)
    }
}

public struct PassRelevantLocation: Codable, Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var relevantText: String?

    public init(latitude: Double, longitude: Double, relevantText: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.relevantText = relevantText
    }
}

public struct PassGeneric: Codable, Sendable, Equatable {
    public var headerFields: [PassField]?
    public var primaryFields: [PassField]?
    public var secondaryFields: [PassField]?
    public var auxiliaryFields: [PassField]?
    public var backFields: [PassField]?
}

public struct PassDocument: Codable, Sendable, Equatable {
    public var formatVersion: Int = 1
    public var passTypeIdentifier: String
    public var serialNumber: String
    public var teamIdentifier: String
    public var organizationName: String
    public var description: String
    public var logoText: String?
    public var foregroundColor: String?
    public var backgroundColor: String?
    public var labelColor: String?
    public var sharingProhibited: Bool?
    public var barcodes: [PassBarcode]
    public var generic: PassGeneric
    public var webServiceURL: String?
    public var authenticationToken: String?
    public var relevantDate: String?
    public var expirationDate: String?
    public var locations: [PassRelevantLocation]?
    public var voided: Bool?
}

public struct PassBuildInputs: Sendable {
    public var passTypeIdentifier: String
    public var teamIdentifier: String
    public var serialNumber: String
    public var authenticationToken: String
    public var webServiceURL: String?
    public var qrPayload: String
    public var appearance: PassAppearance
    public var location: PassLocation?
    public var expirationDate: Date?
    public var relevantDate: Date?
    public var organizationName: String
    public var description: String
    public var supportURL: String?

    public init(
        passTypeIdentifier: String,
        teamIdentifier: String,
        serialNumber: String,
        authenticationToken: String,
        webServiceURL: String?,
        qrPayload: String,
        appearance: PassAppearance,
        location: PassLocation? = nil,
        expirationDate: Date? = nil,
        relevantDate: Date? = nil,
        organizationName: String = "GymPass",
        description: String = "PureGym access code",
        supportURL: String? = nil
    ) {
        self.passTypeIdentifier = passTypeIdentifier
        self.teamIdentifier = teamIdentifier
        self.serialNumber = serialNumber
        self.authenticationToken = authenticationToken
        self.webServiceURL = webServiceURL
        self.qrPayload = qrPayload
        self.appearance = appearance
        self.location = location
        self.expirationDate = expirationDate
        self.relevantDate = relevantDate
        self.organizationName = organizationName
        self.description = description
        self.supportURL = supportURL
    }
}

public enum PassJSON {
    public static func rgbString(_ hex: String, fallback: String) -> String {
        let rgb = HexColor.rgb(from: hex) ?? HexColor.rgb(from: fallback) ?? RGB(red: 0, green: 0, blue: 0)
        let r = Int((rgb.red * 255).rounded())
        let g = Int((rgb.green * 255).rounded())
        let b = Int((rgb.blue * 255).rounded())
        return "rgb(\(r), \(g), \(b))"
    }
}

public enum PassBuilder {
    /// Builds `pass.json` for a generic pass.
    public static func document(_ inputs: PassBuildInputs) -> PassDocument {
        var secondary: [PassField] = [
            PassField(key: "gym", label: "HOME GYM", value: inputs.appearance.gymLabel, textAlignment: "PKTextAlignmentLeft"),
        ]

        var auxiliary: [PassField] = []
        if let expiry = inputs.expirationDate {
            auxiliary.append(PassField(key: "expiry", label: "VALID UNTIL", value: Self.shortDate(expiry), textAlignment: "PKTextAlignmentRight"))
        }

        var back: [PassField] = [
            PassField(key: "about", label: "About", value: "GymPass keeps this access code up to date automatically."),
            PassField(key: "updated", label: "Last generated", value: Self.shortDate(Date())),
        ]
        if let supportURL = inputs.supportURL {
            back.append(PassField(key: "support", label: "Support", value: supportURL))
        }

        var primary: [PassField] = []
        if inputs.appearance.showMemberName, let name = inputs.appearance.memberName, !name.isEmpty {
            primary.append(PassField(key: "member", label: "MEMBER", value: name, textAlignment: "PKTextAlignmentLeft"))
        }

        let generic = PassGeneric(
            headerFields: nil,
            primaryFields: primary.isEmpty ? nil : primary,
            secondaryFields: secondary,
            auxiliaryFields: auxiliary.isEmpty ? nil : auxiliary,
            backFields: back
        )

        var locations: [PassRelevantLocation]?
        if let location = inputs.location {
            locations = [PassRelevantLocation(latitude: location.latitude, longitude: location.longitude, relevantText: location.relevantText ?? location.label)]
        }

        return PassDocument(
            formatVersion: 1,
            passTypeIdentifier: inputs.passTypeIdentifier,
            serialNumber: inputs.serialNumber,
            teamIdentifier: inputs.teamIdentifier,
            organizationName: inputs.organizationName,
            description: inputs.description,
            logoText: inputs.appearance.title,
            foregroundColor: PassJSON.rgbString(inputs.appearance.foregroundHex, fallback: "#FFFFFF"),
            backgroundColor: PassJSON.rgbString(inputs.appearance.backgroundHex, fallback: "#6A35D4"),
            labelColor: PassJSON.rgbString(inputs.appearance.labelHex, fallback: "#E7DDFF"),
            sharingProhibited: true,
            barcodes: [.qr(message: inputs.qrPayload, altText: nil)],
            generic: generic,
            webServiceURL: inputs.webServiceURL,
            authenticationToken: inputs.webServiceURL == nil ? nil : inputs.authenticationToken,
            relevantDate: inputs.relevantDate.map { GymPassDate.iso8601($0) },
            expirationDate: inputs.expirationDate.map { GymPassDate.iso8601($0) },
            locations: locations,
            voided: nil
        )
    }

    public static func encode(_ document: PassDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
