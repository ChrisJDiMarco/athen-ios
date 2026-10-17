import Foundation
import SwiftUI

struct UserProfile: Equatable, Hashable, Codable {
    var zipCode: String
    var stateCode: String
    var stateName: String
    var congressionalDistrict: String?
    var localityLabel: String?
    var officials: ResolvedOfficials
    var interests: Set<CivicTopic>
    var factors: Set<CivicProfileFactor>
    var serviceNeeds: Set<ServiceCategory>
    var eligibilitySignals: Set<EligibilitySignal>
    var householdSize: HouseholdSize
    var incomeBand: IncomeBand
    var preferredLanguage: ResidentLanguage
    var preparedDocuments: Set<CivicDocumentKind>

    init(
        zipCode: String,
        stateCode: String,
        stateName: String,
        congressionalDistrict: String? = nil,
        localityLabel: String? = nil,
        officials: ResolvedOfficials,
        interests: Set<CivicTopic> = [],
        factors: Set<CivicProfileFactor> = [],
        serviceNeeds: Set<ServiceCategory> = [],
        eligibilitySignals: Set<EligibilitySignal> = [],
        householdSize: HouseholdSize = .unknown,
        incomeBand: IncomeBand = .unknown,
        preferredLanguage: ResidentLanguage = .english,
        preparedDocuments: Set<CivicDocumentKind> = []
    ) {
        self.zipCode = zipCode
        self.stateCode = stateCode
        self.stateName = stateName
        self.congressionalDistrict = congressionalDistrict
        self.localityLabel = localityLabel
        self.officials = officials
        self.interests = interests
        self.factors = factors
        self.serviceNeeds = serviceNeeds
        self.eligibilitySignals = eligibilitySignals
        self.householdSize = householdSize
        self.incomeBand = incomeBand
        self.preferredLanguage = preferredLanguage
        self.preparedDocuments = preparedDocuments
    }

    var displayLocation: String {
        if let locality = localityLabel, !locality.isEmpty {
            return "\(locality), \(stateCode)"
        }
        return "\(stateName) (\(zipCode))"
    }

    enum CodingKeys: String, CodingKey {
        case zipCode
        case stateCode
        case stateName
        case congressionalDistrict
        case localityLabel
        case officials
        case interests
        case factors
        case serviceNeeds
        case eligibilitySignals
        case householdSize
        case incomeBand
        case preferredLanguage
        case preparedDocuments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zipCode = try container.decode(String.self, forKey: .zipCode)
        stateCode = try container.decode(String.self, forKey: .stateCode)
        stateName = try container.decode(String.self, forKey: .stateName)
        congressionalDistrict = try container.decodeIfPresent(String.self, forKey: .congressionalDistrict)
        localityLabel = try container.decodeIfPresent(String.self, forKey: .localityLabel)
        officials = try container.decode(ResolvedOfficials.self, forKey: .officials)
        interests = try container.decodeIfPresent(Set<CivicTopic>.self, forKey: .interests) ?? []
        factors = try container.decodeIfPresent(Set<CivicProfileFactor>.self, forKey: .factors) ?? []
        serviceNeeds = try container.decodeIfPresent(Set<ServiceCategory>.self, forKey: .serviceNeeds) ?? []
        eligibilitySignals = try container.decodeIfPresent(Set<EligibilitySignal>.self, forKey: .eligibilitySignals) ?? []
        householdSize = try container.decodeIfPresent(HouseholdSize.self, forKey: .householdSize) ?? .unknown
        incomeBand = try container.decodeIfPresent(IncomeBand.self, forKey: .incomeBand) ?? .unknown
        preferredLanguage = try container.decodeIfPresent(ResidentLanguage.self, forKey: .preferredLanguage) ?? .english
        preparedDocuments = try container.decodeIfPresent(Set<CivicDocumentKind>.self, forKey: .preparedDocuments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(zipCode, forKey: .zipCode)
        try container.encode(stateCode, forKey: .stateCode)
        try container.encode(stateName, forKey: .stateName)
        try container.encodeIfPresent(congressionalDistrict, forKey: .congressionalDistrict)
        try container.encodeIfPresent(localityLabel, forKey: .localityLabel)
        try container.encode(officials, forKey: .officials)
        try container.encode(interests, forKey: .interests)
        try container.encode(factors, forKey: .factors)
        try container.encode(serviceNeeds, forKey: .serviceNeeds)
        try container.encode(eligibilitySignals, forKey: .eligibilitySignals)
        try container.encode(householdSize, forKey: .householdSize)
        try container.encode(incomeBand, forKey: .incomeBand)
        try container.encode(preferredLanguage, forKey: .preferredLanguage)
        try container.encode(preparedDocuments, forKey: .preparedDocuments)
    }
}

enum CivicProfileFactor: String, CaseIterable, Codable, Hashable, Identifiable {
    case renter
    case homeowner
    case parent
    case commuter
    case businessOwner
    case accessibilityNeeds
    case climateFlood

    var id: String { rawValue }

    var label: String {
        switch self {
        case .renter: "Renter"
        case .homeowner: "Homeowner"
        case .parent: "Parent"
        case .commuter: "Commuter"
        case .businessOwner: "Business owner"
        case .accessibilityNeeds: "Accessibility needs"
        case .climateFlood: "Flood / climate risk"
        }
    }

    var systemImage: String {
        switch self {
        case .renter: "key.fill"
        case .homeowner: "house.fill"
        case .parent: "figure.2.and.child.holdinghands"
        case .commuter: "tram.fill"
        case .businessOwner: "storefront.fill"
        case .accessibilityNeeds: "figure.roll"
        case .climateFlood: "drop.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .renter: CivicTheme.cyan
        case .homeowner: CivicTheme.green
        case .parent: CivicTheme.amber
        case .commuter: CivicTheme.violet
        case .businessOwner: CivicTheme.cyan
        case .accessibilityNeeds: CivicTheme.red
        case .climateFlood: CivicTheme.green
        }
    }

    var topics: Set<CivicTopic> {
        switch self {
        case .renter: [.housing, .money]
        case .homeowner: [.housing, .money, .environment]
        case .parent: [.education, .publicSafety, .health]
        case .commuter: [.transit, .environment]
        case .businessOwner: [.money, .publicSafety, .transit]
        case .accessibilityNeeds: [.health, .transit, .publicSafety]
        case .climateFlood: [.environment, .money]
        }
    }
}

struct ResolvedOfficials: Equatable, Hashable, Codable {
    var federalSenators: [OfficialSummary]
    var federalHouseRep: OfficialSummary?
    var stateSenators: [OfficialSummary]
    var stateRepresentatives: [OfficialSummary]
    var local: [OfficialSummary]

    static let empty = ResolvedOfficials(
        federalSenators: [],
        federalHouseRep: nil,
        stateSenators: [],
        stateRepresentatives: [],
        local: []
    )

    var hasAny: Bool {
        !federalSenators.isEmpty
            || federalHouseRep != nil
            || !stateSenators.isEmpty
            || !stateRepresentatives.isEmpty
            || !local.isEmpty
    }
}

struct OfficialSummary: Equatable, Hashable, Codable, Identifiable {
    var id: String { "\(level)|\(name)|\(district ?? "")" }

    let name: String
    let title: String
    let level: String
    let district: String?
    let party: String?
    let contactLabel: String?
    /// Populated lazily by the directory lookup. Nil for officials not yet
    /// enriched — UI hides the quick-action pills in that case.
    var phone: String?
    var email: String?
    var websiteURL: String?

    init(
        name: String,
        title: String,
        level: String,
        district: String? = nil,
        party: String? = nil,
        contactLabel: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        websiteURL: String? = nil,
    ) {
        self.name = name
        self.title = title
        self.level = level
        self.district = district
        self.party = party
        self.contactLabel = contactLabel
        self.phone = phone
        self.email = email
        self.websiteURL = websiteURL
    }

    private enum CodingKeys: String, CodingKey {
        case name, title, level, district, party, contactLabel, phone, email, websiteURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        title = try c.decode(String.self, forKey: .title)
        level = try c.decode(String.self, forKey: .level)
        district = try? c.decode(String.self, forKey: .district)
        party = try? c.decode(String.self, forKey: .party)
        contactLabel = try? c.decode(String.self, forKey: .contactLabel)
        phone = try? c.decode(String.self, forKey: .phone)
        email = try? c.decode(String.self, forKey: .email)
        websiteURL = try? c.decode(String.self, forKey: .websiteURL)
    }
}
