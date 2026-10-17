export type ServiceCategory =
  | "housing"
  | "food"
  | "health"
  | "transit"
  | "education"
  | "jobs"
  | "legalAid"
  | "documents";

export interface ServiceProgram {
  id: string;
  title: string;
  category: ServiceCategory;
  provider: string;
  summary: string;
  eligibility: string;
  applySteps: string[];
  documents: string[];
  signals: string[];
  languages: string[];
  sourceName: string;
  sourceURL: string;
  freshness: string;
}

export interface ServiceMatchProfile {
  needs: string[];
  signals: string[];
  preparedDocuments: string[];
  language?: string;
}

export interface MatchedService extends ServiceProgram {
  matchScore: number;
  reasons: string[];
  missingDocuments: string[];
  documentProgress: {
    ready: number;
    total: number;
  };
  nextStep: string;
}

export const serviceCatalog: ServiceProgram[] = [
  {
    id: "E1000001-AAAA-BBBB-CCCC-000000000001",
    title: "Rent, eviction, and shelter triage",
    category: "housing",
    provider: "Local housing access point",
    summary: "One starting point for rent relief, eviction defense, emergency shelter, and housing counseling.",
    eligibility: "Usually depends on ZIP, household size, income, lease status, and urgency.",
    applySteps: ["Confirm address and household size", "Gather lease or proof of residence", "Call or apply online", "Save confirmation and follow-up deadline"],
    documents: ["photoID", "proofOfAddress", "incomeProof", "leaseOrMortgage"],
    signals: ["renter", "lowIncome", "urgentHousingRisk"],
    languages: ["english", "spanish", "chinese", "vietnamese", "arabic"],
    sourceName: "City housing services directory",
    sourceURL: "https://www.usa.gov/housing-help",
    freshness: "Verified source pattern",
  },
  {
    id: "E1000001-AAAA-BBBB-CCCC-000000000002",
    title: "Food benefits and meal sites",
    category: "food",
    provider: "Benefits office and community pantry network",
    summary: "Find SNAP, WIC, school meal, senior meal, and nearby food distribution options.",
    eligibility: "Programs often consider income, household size, age, pregnancy, student status, or children in the home.",
    applySteps: ["Pick benefit type", "Check income band and household size", "Prepare ID and income documents", "Apply online or by phone"],
    documents: ["photoID", "proofOfAddress", "incomeProof", "benefitsLetter"],
    signals: ["lowIncome", "parentOrGuardian", "student", "olderAdult"],
    languages: ["english", "spanish", "chinese", "vietnamese", "tagalog"],
    sourceName: "USDA and local food access directories",
    sourceURL: "https://www.fns.usda.gov/snap/applicant-recipient",
    freshness: "Official federal/state starting point",
  },
  {
    id: "E1000001-AAAA-BBBB-CCCC-000000000003",
    title: "Clinic, insurance, and mental health access",
    category: "health",
    provider: "Public health and community clinic network",
    summary: "Locate low-cost clinics, insurance enrollment help, behavioral health resources, and urgent support lines.",
    eligibility: "Most programs depend on residence, insurance status, income, age, disability, or urgent need.",
    applySteps: ["Choose care type", "Check language/access needs", "Call intake or book online", "Bring ID and insurance/benefit letters if available"],
    documents: ["photoID", "proofOfAddress", "benefitsLetter", "medicalOrAccessLetter"],
    signals: ["lowIncome", "disability", "olderAdult"],
    languages: ["english", "spanish", "chinese", "arabic", "french"],
    sourceName: "HRSA health center lookup",
    sourceURL: "https://findahealthcenter.hrsa.gov/",
    freshness: "Official federal source",
  },
  {
    id: "E1000001-AAAA-BBBB-CCCC-000000000004",
    title: "Reduced fare transit pass",
    category: "transit",
    provider: "Transit authority",
    summary: "Discounted passes for students, older adults, people with disabilities, veterans, or income-qualified riders.",
    eligibility: "Depends on transit agency rules, age, income, disability status, student status, or veteran status.",
    applySteps: ["Select rider category", "Prepare proof of status", "Apply through transit portal", "Save renewal date"],
    documents: ["photoID", "proofOfAddress", "schoolRecord", "medicalOrAccessLetter", "benefitsLetter"],
    signals: ["student", "olderAdult", "veteran", "disability", "lowIncome"],
    languages: ["english", "spanish", "chinese"],
    sourceName: "Local transit authority",
    sourceURL: "https://www.transit.dot.gov/",
    freshness: "Agency-specific",
  },
  {
    id: "E1000001-AAAA-BBBB-CCCC-000000000005",
    title: "School meals, childcare, and student support",
    category: "education",
    provider: "School district and family services",
    summary: "Connect to school meal programs, summer benefits, childcare subsidies, tutoring, and student transportation help.",
    eligibility: "Often based on student enrollment, household size, income, disability, or school district.",
    applySteps: ["Confirm school/district", "Check household and student details", "Gather school record or benefit letter", "Submit district or state form"],
    documents: ["proofOfAddress", "incomeProof", "schoolRecord", "benefitsLetter"],
    signals: ["parentOrGuardian", "student", "lowIncome", "disability"],
    languages: ["english", "spanish", "chinese", "vietnamese", "arabic"],
    sourceName: "School district and state education agency",
    sourceURL: "https://www.fns.usda.gov/school-meals",
    freshness: "Official program family",
  },
  {
    id: "E1000001-AAAA-BBBB-CCCC-000000000006",
    title: "Job training and income support",
    category: "jobs",
    provider: "Workforce development board",
    summary: "Find workforce training, unemployment help, resume support, apprenticeships, and income-stabilizing programs.",
    eligibility: "Depends on work status, income, age, veteran status, training goals, and residence.",
    applySteps: ["Pick goal: job, training, unemployment, or business help", "Prepare ID and work history", "Book intake", "Track next appointment"],
    documents: ["photoID", "proofOfAddress", "incomeProof", "benefitsLetter"],
    signals: ["unemployed", "lowIncome", "veteran", "smallBusiness"],
    languages: ["english", "spanish", "chinese", "french"],
    sourceName: "CareerOneStop",
    sourceURL: "https://www.careeronestop.org/",
    freshness: "Official federal/state starting point",
  },
  {
    id: "E1000001-AAAA-BBBB-CCCC-000000000007",
    title: "Free legal help for housing, benefits, and debt",
    category: "legalAid",
    provider: "Legal aid network",
    summary: "Find free or low-cost legal support for eviction, benefits denial, debt collection, wage theft, or family safety.",
    eligibility: "Usually income-based, location-based, and issue-specific. Some urgent safety matters get priority.",
    applySteps: ["Choose issue type", "Check intake hours", "Prepare notices or court papers", "Call early and save case deadlines"],
    documents: ["photoID", "proofOfAddress", "incomeProof", "leaseOrMortgage", "benefitsLetter"],
    signals: ["lowIncome", "renter", "urgentHousingRisk", "disability"],
    languages: ["english", "spanish", "chinese", "arabic"],
    sourceName: "Legal Services Corporation",
    sourceURL: "https://www.lsc.gov/about-lsc/what-legal-aid/get-legal-help",
    freshness: "Official legal-aid directory",
  },
  {
    id: "E1000001-AAAA-BBBB-CCCC-000000000008",
    title: "IDs, records, permits, and city forms",
    category: "documents",
    provider: "City/county service counter",
    summary: "Get oriented on IDs, birth/marriage records, business permits, property records, and common city forms.",
    eligibility: "Depends on document type, proof of identity, residence, fees, and appointment availability.",
    applySteps: ["Pick document or permit", "Check fees and accepted proof", "Book appointment or start online", "Save receipt and pickup deadline"],
    documents: ["photoID", "proofOfAddress", "utilityBill", "incomeProof"],
    signals: ["smallBusiness", "renter", "parentOrGuardian"],
    languages: ["english", "spanish", "chinese", "vietnamese"],
    sourceName: "City/county records office",
    sourceURL: "https://www.usa.gov/replace-vital-documents",
    freshness: "Official directory pattern",
  },
];

export function matchServices(
  profile: ServiceMatchProfile,
  options: { limit?: number | undefined; category?: string | undefined } = {},
): MatchedService[] {
  const needs = new Set(profile.needs);
  const signals = new Set(profile.signals);
  const preparedDocuments = new Set(profile.preparedDocuments);
  const language = profile.language ?? "english";

  return serviceCatalog
    .filter((service) => !options.category || service.category === options.category)
    .map((service) => {
      let score = 20;
      const reasons: string[] = [];

      if (needs.has(service.category)) {
        score += 38;
        reasons.push(`matches ${labelForCategory(service.category)} need`);
      }

      const matchingSignals = service.signals.filter((signal) => signals.has(signal));
      if (matchingSignals.length > 0) {
        score += 24;
        reasons.push(`fits ${matchingSignals.map(labelForSignal).slice(0, 2).join(" and ")}`);
      }

      if (language !== "english" && service.languages.includes(language)) {
        score += 8;
        reasons.push(`${labelForLanguage(language)} language support`);
      }

      const readyDocs = service.documents.filter((doc) => preparedDocuments.has(doc));
      if (readyDocs.length > 0) {
        score += Math.min(readyDocs.length * 5, 15);
        reasons.push(`${readyDocs.length} document${readyDocs.length === 1 ? "" : "s"} ready`);
      }

      const missingDocuments = service.documents.filter((doc) => !preparedDocuments.has(doc));
      const firstStep = service.applySteps[0] ?? "Check the official source";

      return {
        ...service,
        matchScore: Math.min(score, 100),
        reasons: reasons.length > 0 ? reasons : ["good general starting point"],
        missingDocuments,
        documentProgress: {
          ready: readyDocs.length,
          total: service.documents.length,
        },
        nextStep: firstStep,
      };
    })
    .sort((a, b) => {
      if (a.matchScore !== b.matchScore) return b.matchScore - a.matchScore;
      return a.title.localeCompare(b.title);
    })
    .slice(0, options.limit ?? serviceCatalog.length);
}

function labelForCategory(category: string): string {
  const labels: Record<string, string> = {
    housing: "housing",
    food: "food",
    health: "healthcare",
    transit: "transit",
    education: "education",
    jobs: "jobs",
    legalAid: "legal aid",
    documents: "documents",
  };
  return labels[category] ?? category;
}

function labelForSignal(signal: string): string {
  const labels: Record<string, string> = {
    renter: "renter",
    parentOrGuardian: "parent/guardian",
    student: "student",
    olderAdult: "older adult",
    veteran: "veteran",
    disability: "disability access",
    unemployed: "job search",
    lowIncome: "income-sensitive",
    smallBusiness: "small business",
    urgentHousingRisk: "urgent housing risk",
  };
  return labels[signal] ?? signal;
}

function labelForLanguage(language: string): string {
  const labels: Record<string, string> = {
    spanish: "Spanish",
    chinese: "Chinese",
    vietnamese: "Vietnamese",
    arabic: "Arabic",
    french: "French",
    portuguese: "Portuguese",
    russian: "Russian",
    tagalog: "Tagalog",
  };
  return labels[language] ?? language;
}
