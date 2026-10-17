import Foundation
import SwiftUI

enum ServiceCategory: String, CaseIterable, Codable, Hashable, Identifiable {
    case housing
    case food
    case health
    case transit
    case education
    case jobs
    case legalAid
    case documents

    var id: String { rawValue }

    var label: String {
        switch self {
        case .housing: "Housing"
        case .food: "Food"
        case .health: "Health"
        case .transit: "Transit"
        case .education: "Education"
        case .jobs: "Jobs"
        case .legalAid: "Legal aid"
        case .documents: "IDs & permits"
        }
    }

    var prompt: String {
        switch self {
        case .housing: "I need help with rent, eviction, shelter, or housing paperwork."
        case .food: "I need help finding food benefits, meals, or grocery support."
        case .health: "I need help finding healthcare, insurance, or a clinic."
        case .transit: "I need help with transit fares, routes, or transportation access."
        case .education: "I need help with school, meals, childcare, or student support."
        case .jobs: "I need help finding work, training, or income support."
        case .legalAid: "I need help understanding a legal notice or finding free legal aid."
        case .documents: "I need help with IDs, permits, records, or government forms."
        }
    }

    var systemImage: String {
        switch self {
        case .housing: "house.fill"
        case .food: "fork.knife"
        case .health: "cross.case.fill"
        case .transit: "tram.fill"
        case .education: "graduationcap.fill"
        case .jobs: "briefcase.fill"
        case .legalAid: "scale.3d"
        case .documents: "doc.text.fill"
        }
    }

    var tint: Color {
        switch self {
        case .housing: CivicTheme.cyan
        case .food: CivicTheme.green
        case .health: CivicTheme.violet
        case .transit: CivicTheme.amber
        case .education: CivicTheme.cyan
        case .jobs: CivicTheme.green
        case .legalAid: CivicTheme.red
        case .documents: CivicTheme.violet
        }
    }

    var relatedTopics: Set<CivicTopic> {
        switch self {
        case .housing: [.housing, .money]
        case .food: [.health, .money]
        case .health: [.health]
        case .transit: [.transit, .money]
        case .education: [.education, .health]
        case .jobs: [.money, .education]
        case .legalAid: [.housing, .publicSafety]
        case .documents: [.money, .publicSafety]
        }
    }
}

enum EligibilitySignal: String, CaseIterable, Codable, Hashable, Identifiable {
    case renter
    case parentOrGuardian
    case student
    case olderAdult
    case veteran
    case disability
    case unemployed
    case lowIncome
    case smallBusiness
    case urgentHousingRisk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .renter: "Renter"
        case .parentOrGuardian: "Parent / guardian"
        case .student: "Student"
        case .olderAdult: "Older adult"
        case .veteran: "Veteran"
        case .disability: "Disability access"
        case .unemployed: "Looking for work"
        case .lowIncome: "Income-sensitive"
        case .smallBusiness: "Small business"
        case .urgentHousingRisk: "Urgent housing risk"
        }
    }

    var systemImage: String {
        switch self {
        case .renter: "key.fill"
        case .parentOrGuardian: "figure.2.and.child.holdinghands"
        case .student: "book.closed.fill"
        case .olderAdult: "person.crop.circle.badge.clock"
        case .veteran: "star.circle.fill"
        case .disability: "figure.roll"
        case .unemployed: "magnifyingglass.circle.fill"
        case .lowIncome: "dollarsign.circle.fill"
        case .smallBusiness: "storefront.fill"
        case .urgentHousingRisk: "exclamationmark.triangle.fill"
        }
    }
}

enum IncomeBand: String, CaseIterable, Codable, Hashable, Identifiable {
    case unknown
    case under25k
    case under50k
    case under80k
    case over80k

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unknown: "Not set"
        case .under25k: "Under $25k"
        case .under50k: "Under $50k"
        case .under80k: "Under $80k"
        case .over80k: "Over $80k"
        }
    }
}

enum HouseholdSize: String, CaseIterable, Codable, Hashable, Identifiable {
    case unknown
    case one
    case two
    case threeOrFour
    case fivePlus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unknown: "Not set"
        case .one: "1 person"
        case .two: "2 people"
        case .threeOrFour: "3-4 people"
        case .fivePlus: "5+ people"
        }
    }
}

enum ResidentLanguage: String, CaseIterable, Codable, Hashable, Identifiable {
    case english
    case spanish
    case chinese
    case vietnamese
    case arabic
    case french
    case portuguese
    case russian
    case tagalog

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        case .chinese: "Chinese"
        case .vietnamese: "Vietnamese"
        case .arabic: "Arabic"
        case .french: "French"
        case .portuguese: "Portuguese"
        case .russian: "Russian"
        case .tagalog: "Tagalog"
        }
    }
}

enum CivicDocumentKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case photoID
    case proofOfAddress
    case incomeProof
    case leaseOrMortgage
    case utilityBill
    case benefitsLetter
    case schoolRecord
    case medicalOrAccessLetter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photoID: "Photo ID"
        case .proofOfAddress: "Proof of address"
        case .incomeProof: "Income proof"
        case .leaseOrMortgage: "Lease / mortgage"
        case .utilityBill: "Utility bill"
        case .benefitsLetter: "Benefits letter"
        case .schoolRecord: "School record"
        case .medicalOrAccessLetter: "Medical/access letter"
        }
    }

    var systemImage: String {
        switch self {
        case .photoID: "person.text.rectangle.fill"
        case .proofOfAddress: "mappin.and.ellipse"
        case .incomeProof: "dollarsign.square.fill"
        case .leaseOrMortgage: "house.and.flag.fill"
        case .utilityBill: "bolt.fill"
        case .benefitsLetter: "doc.badge.gearshape.fill"
        case .schoolRecord: "graduationcap.fill"
        case .medicalOrAccessLetter: "cross.case.fill"
        }
    }
}

struct CivicService: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var category: ServiceCategory
    var provider: String
    var summary: String
    var eligibility: String
    var applySteps: [String]
    var documents: [CivicDocumentKind]
    var signals: Set<EligibilitySignal>
    var languages: [ResidentLanguage]
    var sourceName: String
    var sourceURL: String
    var freshness: String

    init(
        id: UUID,
        title: String,
        category: ServiceCategory,
        provider: String,
        summary: String,
        eligibility: String,
        applySteps: [String],
        documents: [CivicDocumentKind],
        signals: Set<EligibilitySignal>,
        languages: [ResidentLanguage],
        sourceName: String,
        sourceURL: String,
        freshness: String
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.provider = provider
        self.summary = summary
        self.eligibility = eligibility
        self.applySteps = applySteps
        self.documents = documents
        self.signals = signals
        self.languages = languages
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.freshness = freshness
    }

    func matchScore(for profile: UserProfile?) -> Int {
        guard let profile else { return 0 }
        var score = 20
        if profile.serviceNeeds.contains(category) { score += 38 }
        if !signals.isDisjoint(with: profile.eligibilitySignals) { score += 24 }
        if profile.interests.contains(where: category.relatedTopics.contains) { score += 10 }
        if profile.preferredLanguage != .english && languages.contains(profile.preferredLanguage) { score += 8 }
        if !documents.isEmpty {
            let prepared = Set(documents).intersection(profile.preparedDocuments).count
            score += min(prepared * 5, 15)
        }
        return min(score, 100)
    }

    func documentProgress(for profile: UserProfile?) -> (ready: Int, total: Int) {
        guard let profile else { return (0, documents.count) }
        return (Set(documents).intersection(profile.preparedDocuments).count, documents.count)
    }
}

extension CivicService {
    static let samples: [CivicService] = [
        CivicService(
            id: UUID(uuidString: "E1000001-AAAA-BBBB-CCCC-000000000001")!,
            title: "Rent, eviction, and shelter triage",
            category: .housing,
            provider: "Local housing access point",
            summary: "One starting point for rent relief, eviction defense, emergency shelter, and housing counseling.",
            eligibility: "Usually depends on ZIP, household size, income, lease status, and urgency.",
            applySteps: ["Confirm address and household size", "Gather lease or proof of residence", "Call or apply online", "Save confirmation and follow-up deadline"],
            documents: [.photoID, .proofOfAddress, .incomeProof, .leaseOrMortgage],
            signals: [.renter, .lowIncome, .urgentHousingRisk],
            languages: [.english, .spanish, .chinese, .vietnamese, .arabic],
            sourceName: "City housing services directory",
            sourceURL: "https://www.usa.gov/housing-help",
            freshness: "Verified source pattern"
        ),
        CivicService(
            id: UUID(uuidString: "E1000001-AAAA-BBBB-CCCC-000000000002")!,
            title: "Food benefits and meal sites",
            category: .food,
            provider: "Benefits office and community pantry network",
            summary: "Find SNAP, WIC, school meal, senior meal, and nearby food distribution options.",
            eligibility: "Programs often consider income, household size, age, pregnancy, student status, or children in the home.",
            applySteps: ["Pick benefit type", "Check income band and household size", "Prepare ID and income documents", "Apply online or by phone"],
            documents: [.photoID, .proofOfAddress, .incomeProof, .benefitsLetter],
            signals: [.lowIncome, .parentOrGuardian, .student, .olderAdult],
            languages: [.english, .spanish, .chinese, .vietnamese, .tagalog],
            sourceName: "USDA and local food access directories",
            sourceURL: "https://www.fns.usda.gov/snap/applicant-recipient",
            freshness: "Official federal/state starting point"
        ),
        CivicService(
            id: UUID(uuidString: "E1000001-AAAA-BBBB-CCCC-000000000003")!,
            title: "Clinic, insurance, and mental health access",
            category: .health,
            provider: "Public health and community clinic network",
            summary: "Locate low-cost clinics, insurance enrollment help, behavioral health resources, and urgent support lines.",
            eligibility: "Most programs depend on residence, insurance status, income, age, disability, or urgent need.",
            applySteps: ["Choose care type", "Check language/access needs", "Call intake or book online", "Bring ID and insurance/benefit letters if available"],
            documents: [.photoID, .proofOfAddress, .benefitsLetter, .medicalOrAccessLetter],
            signals: [.lowIncome, .disability, .olderAdult],
            languages: [.english, .spanish, .chinese, .arabic, .french],
            sourceName: "HRSA health center lookup",
            sourceURL: "https://findahealthcenter.hrsa.gov/",
            freshness: "Official federal source"
        ),
        CivicService(
            id: UUID(uuidString: "E1000001-AAAA-BBBB-CCCC-000000000004")!,
            title: "Reduced fare transit pass",
            category: .transit,
            provider: "Transit authority",
            summary: "Discounted passes for students, older adults, people with disabilities, veterans, or income-qualified riders.",
            eligibility: "Depends on transit agency rules, age, income, disability status, student status, or veteran status.",
            applySteps: ["Select rider category", "Prepare proof of status", "Apply through transit portal", "Save renewal date"],
            documents: [.photoID, .proofOfAddress, .schoolRecord, .medicalOrAccessLetter, .benefitsLetter],
            signals: [.student, .olderAdult, .veteran, .disability, .lowIncome],
            languages: [.english, .spanish, .chinese],
            sourceName: "Local transit authority",
            sourceURL: "https://www.transit.dot.gov/",
            freshness: "Agency-specific"
        ),
        CivicService(
            id: UUID(uuidString: "E1000001-AAAA-BBBB-CCCC-000000000005")!,
            title: "School meals, childcare, and student support",
            category: .education,
            provider: "School district and family services",
            summary: "Connect to school meal programs, summer benefits, childcare subsidies, tutoring, and student transportation help.",
            eligibility: "Often based on student enrollment, household size, income, disability, or school district.",
            applySteps: ["Confirm school/district", "Check household and student details", "Gather school record or benefit letter", "Submit district or state form"],
            documents: [.proofOfAddress, .incomeProof, .schoolRecord, .benefitsLetter],
            signals: [.parentOrGuardian, .student, .lowIncome, .disability],
            languages: [.english, .spanish, .chinese, .vietnamese, .arabic],
            sourceName: "School district and state education agency",
            sourceURL: "https://www.fns.usda.gov/school-meals",
            freshness: "Official program family"
        ),
        CivicService(
            id: UUID(uuidString: "E1000001-AAAA-BBBB-CCCC-000000000006")!,
            title: "Job training and income support",
            category: .jobs,
            provider: "Workforce development board",
            summary: "Find workforce training, unemployment help, resume support, apprenticeships, and income-stabilizing programs.",
            eligibility: "Depends on work status, income, age, veteran status, training goals, and residence.",
            applySteps: ["Pick goal: job, training, unemployment, or business help", "Prepare ID and work history", "Book intake", "Track next appointment"],
            documents: [.photoID, .proofOfAddress, .incomeProof, .benefitsLetter],
            signals: [.unemployed, .lowIncome, .veteran, .smallBusiness],
            languages: [.english, .spanish, .chinese, .french],
            sourceName: "CareerOneStop",
            sourceURL: "https://www.careeronestop.org/",
            freshness: "Official federal/state starting point"
        ),
        CivicService(
            id: UUID(uuidString: "E1000001-AAAA-BBBB-CCCC-000000000007")!,
            title: "Free legal help for housing, benefits, and debt",
            category: .legalAid,
            provider: "Legal aid network",
            summary: "Find free or low-cost legal support for eviction, benefits denial, debt collection, wage theft, or family safety.",
            eligibility: "Usually income-based, location-based, and issue-specific. Some urgent safety matters get priority.",
            applySteps: ["Choose issue type", "Check intake hours", "Prepare notices or court papers", "Call early and save case deadlines"],
            documents: [.photoID, .proofOfAddress, .incomeProof, .leaseOrMortgage, .benefitsLetter],
            signals: [.lowIncome, .renter, .urgentHousingRisk, .disability],
            languages: [.english, .spanish, .chinese, .arabic],
            sourceName: "Legal Services Corporation",
            sourceURL: "https://www.lsc.gov/about-lsc/what-legal-aid/get-legal-help",
            freshness: "Official legal-aid directory"
        ),
        CivicService(
            id: UUID(uuidString: "E1000001-AAAA-BBBB-CCCC-000000000008")!,
            title: "IDs, records, permits, and city forms",
            category: .documents,
            provider: "City/county service counter",
            summary: "Get oriented on IDs, birth/marriage records, business permits, property records, and common city forms.",
            eligibility: "Depends on document type, proof of identity, residence, fees, and appointment availability.",
            applySteps: ["Pick document or permit", "Check fees and accepted proof", "Book appointment or start online", "Save receipt and pickup deadline"],
            documents: [.photoID, .proofOfAddress, .utilityBill, .incomeProof],
            signals: [.smallBusiness, .renter, .parentOrGuardian],
            languages: [.english, .spanish, .chinese, .vietnamese],
            sourceName: "City/county records office",
            sourceURL: "https://www.usa.gov/replace-vital-documents",
            freshness: "Official directory pattern"
        )
    ]
}
