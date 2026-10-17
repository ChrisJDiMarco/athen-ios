import Foundation

enum MockCivicData {
    static let issues: [CivicIssue] = [
        CivicIssue(
            id: UUID(uuidString: "5A56986F-E7DD-47E7-9A61-F1D79A6B2A01")!,
            title: "Broad Street Re-Zoning",
            category: "Land Use",
            jurisdiction: "Philadelphia City Council",
            scope: .localPhilly,
            zipCode: "19129",
            summary: "Council will vote on a corridor rezoning package that changes what can be built near Broad Street transit stops.",
            impactLevel: .urgent,
            voteDate: mockDate(month: 5, day: 19, hour: 10, minute: 30),
            sourceName: "Resolution 260418",
            sourceDetail: "Zoning and Planning Committee packet",
            sourceURL: "https://phila.legistar.com/",
            facts: [
                TranslationFact(label: "What it does", value: "Allows multi-family housing on selected Broad Street parcels near existing transit.", systemImage: "building.2.fill"),
                TranslationFact(label: "The cost", value: "$0 projected impact on local taxes; construction is privately financed.", systemImage: "dollarsign.square.fill"),
                TranslationFact(label: "The timeline", value: "City Council vote is scheduled for Tuesday morning.", systemImage: "calendar.badge.clock")
            ],
            official: LocalOfficial(
                id: UUID(uuidString: "C472728D-A13D-4F62-8DC4-98B093D99825")!,
                name: "Councilmember Maya Patel",
                title: "District Councilmember",
                district: "District 4",
                contactTarget: "Council public comment portal"
            ),
            filingRoute: FilingRoute(
                verificationStep: "Verified address confirms District 4 eligibility.",
                routingStep: "Routing agent maps 19129 to Councilmember Patel.",
                destinationStep: "Formal message is filed through the public comment portal and copied to the district inbox.",
                deliveryWindow: "Typical confirmation under 60 seconds"
            ),
            reply: nil,
            topics: [.housing, .transit]
        ),
        CivicIssue(
            id: UUID(uuidString: "C21276EC-9953-4D2F-B6F4-E8C425105202")!,
            title: "Library Hours Extension",
            category: "Public Services",
            jurisdiction: "Free Library Board",
            scope: .localPhilly,
            zipCode: "19129",
            summary: "The board is considering an evening-hours pilot for branches serving high commuter neighborhoods.",
            impactLevel: .material,
            voteDate: mockDate(month: 5, day: 21, hour: 18, minute: 0),
            sourceName: "Board Agenda Item 7B",
            sourceDetail: "Operations Committee agenda",
            sourceURL: "https://libwww.freelibrary.org/about/board/",
            facts: [
                TranslationFact(label: "What it does", value: "Adds two evening service windows per week at selected neighborhood libraries.", systemImage: "books.vertical.fill"),
                TranslationFact(label: "The cost", value: "$410K pilot using existing facilities and temporary staffing funds.", systemImage: "chart.bar.doc.horizontal.fill"),
                TranslationFact(label: "The timeline", value: "Board vote is Thursday; pilot would begin in September.", systemImage: "calendar")
            ],
            official: LocalOfficial(
                id: UUID(uuidString: "03D0A536-D3D2-4B9D-886F-1B9D3F2D1E77")!,
                name: "Director Lena Brooks",
                title: "Library Board Secretary",
                district: "Citywide",
                contactTarget: "Board comment inbox"
            ),
            filingRoute: FilingRoute(
                verificationStep: "Verified address confirms Philadelphia residency.",
                routingStep: "Routing agent selects the citywide board contact.",
                destinationStep: "Message is delivered to the board comment inbox with the agenda item attached.",
                deliveryWindow: "Typical confirmation under 2 minutes"
            ),
            reply: OfficialReply(
                id: UUID(uuidString: "F0912766-D27F-4A6D-84C1-669804865B29")!,
                receivedAt: mockDate(month: 5, day: 16, hour: 14, minute: 45),
                summary: "The board confirmed that resident comments received before Wednesday at noon will be included in the packet.",
                stance: "Acknowledged"
            ),
            topics: [.education]
        ),
        CivicIssue(
            id: UUID(uuidString: "09C80687-422C-418C-A6B6-5BD5F6303C55")!,
            title: "Stormwater Fee Update",
            category: "Utilities",
            jurisdiction: "Water Department",
            scope: .localPhilly,
            zipCode: "19129",
            summary: "A proposed fee calculation update changes how commercial properties are credited for green infrastructure.",
            impactLevel: .watch,
            voteDate: mockDate(month: 5, day: 23, hour: 9, minute: 0),
            sourceName: "Rate Board Notice",
            sourceDetail: "Public hearing notice and staff memo",
            sourceURL: "https://www.phila.gov/departments/water-sewer-storm-water-rate-board/",
            facts: [
                TranslationFact(label: "What it does", value: "Updates credits for properties that reduce runoff with verified green infrastructure.", systemImage: "cloud.rain.fill"),
                TranslationFact(label: "The cost", value: "Most residential bills are unchanged; commercial credits may move up or down.", systemImage: "creditcard.fill"),
                TranslationFact(label: "The timeline", value: "Public hearing is Friday; written comments remain open for 10 days.", systemImage: "timer")
            ],
            official: LocalOfficial(
                id: UUID(uuidString: "85B18C9B-6165-47A0-A413-04B971C36D98")!,
                name: "Rate Board Clerk",
                title: "Public Comment Intake",
                district: "Citywide",
                contactTarget: "Rate Board hearing record"
            ),
            filingRoute: FilingRoute(
                verificationStep: "Verified address confirms city utility customer status.",
                routingStep: "Routing agent selects the Water, Sewer, and Storm Water Rate Board.",
                destinationStep: "Comment is filed into the formal hearing record.",
                deliveryWindow: "Typical confirmation same day"
            ),
            reply: nil,
            topics: [.environment, .money]
        )
    ]

    static let federalIssues: [CivicIssue] = [
        CivicIssue(
            id: UUID(uuidString: "F1000001-2222-3333-4444-FED00000A001")!,
            title: "FY27 Appropriations — Local Transit Grants",
            category: "Federal Budget",
            jurisdiction: "U.S. House of Representatives",
            scope: .federal,
            zipCode: "",
            summary: "The House is voting on whether to preserve formula funding for local public transit operations in next year's appropriations bill.",
            impactLevel: .material,
            voteDate: mockDate(month: 5, day: 22, hour: 14, minute: 0),
            sourceName: "H.R. 4218",
            sourceDetail: "Transportation, Housing and Urban Development Subcommittee report",
            sourceURL: "https://www.congress.gov/",
            facts: [
                TranslationFact(label: "What it does", value: "Preserves $13.6B in formula grants for bus and rail operations in cities of all sizes.", systemImage: "tram.fill"),
                TranslationFact(label: "Who it touches", value: "Anyone whose local transit agency depends on federal operating support.", systemImage: "person.3.fill"),
                TranslationFact(label: "The timeline", value: "Full House vote expected before Memorial Day recess.", systemImage: "calendar.badge.clock")
            ],
            official: LocalOfficial(
                id: UUID(uuidString: "FED10000-AAAA-BBBB-CCCC-100000000001")!,
                name: "Your U.S. Representative",
                title: "Member, U.S. House of Representatives",
                district: "Your district",
                contactTarget: "House office constituent inbox"
            ),
            filingRoute: FilingRoute(
                verificationStep: "Verified ZIP confirms your congressional district.",
                routingStep: "Routing agent selects your district's U.S. House member.",
                destinationStep: "Message is delivered to the representative's constituent inbox with H.R. 4218 referenced.",
                deliveryWindow: "Typical confirmation under 5 minutes"
            ),
            reply: nil,
            topics: [.transit, .money]
        ),
        CivicIssue(
            id: UUID(uuidString: "F1000002-2222-3333-4444-FED00000A002")!,
            title: "FCC Rule on Broadband Labels",
            category: "Federal Rulemaking",
            jurisdiction: "U.S. Senate",
            scope: .federal,
            zipCode: "",
            summary: "The Senate Commerce Committee is collecting comment on proposed updates to broadband 'nutrition label' disclosures.",
            impactLevel: .watch,
            voteDate: mockDate(month: 5, day: 28, hour: 10, minute: 0),
            sourceName: "FCC NPRM 24-256",
            sourceDetail: "Senate Commerce Committee comment window",
            sourceURL: "https://www.fcc.gov/ecfs/",
            facts: [
                TranslationFact(label: "What it does", value: "Adds clearer monthly-fee, data-cap, and throttling disclosures to home internet plans.", systemImage: "wifi"),
                TranslationFact(label: "Who it touches", value: "Every household shopping for or paying for home internet.", systemImage: "house.fill"),
                TranslationFact(label: "The timeline", value: "Senate comment window closes May 28.", systemImage: "timer")
            ],
            official: LocalOfficial(
                id: UUID(uuidString: "FED20000-AAAA-BBBB-CCCC-200000000002")!,
                name: "Your U.S. Senator",
                title: "Member, U.S. Senate",
                district: "Your state",
                contactTarget: "Senate office constituent inbox"
            ),
            filingRoute: FilingRoute(
                verificationStep: "Verified ZIP confirms your state.",
                routingStep: "Routing agent selects your senior U.S. Senator.",
                destinationStep: "Message is delivered to the senator's constituent inbox with the FCC docket referenced.",
                deliveryWindow: "Typical confirmation under 5 minutes"
            ),
            reply: nil,
            topics: [.money]
        )
    ]

    static let allIssues: [CivicIssue] = federalIssues + issues

    private static func mockDate(month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "America/New_York")
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute

        return components.date ?? .now
    }
}
