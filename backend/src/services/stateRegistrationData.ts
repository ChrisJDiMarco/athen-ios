/**
 * Per-state voter-registration metadata. Sourced from the secretary of state
 * portals and vote.gov as of 2026. Numbers like deadlines are typed
 * conservatively — when a state runs same-day registration or registration
 * at the DMV, that's noted. Verify on the linked portal before relying on
 * dates for a specific upcoming election.
 */

export interface StateRegistrationInfo {
  stateCode: string;
  stateName: string;
  /** Official state registration portal (online if available, else SoS landing). */
  portalURL: string;
  /** True when the state supports fully online registration. */
  online: boolean;
  /** True when the state allows same-day registration on Election Day. */
  sameDay: boolean;
  /** True for automatic registration at DMV interactions. */
  automaticAtDMV: boolean;
  /**
   * Days before election that registration closes. -1 for same-day, 0 for
   * unknown. Use the linked portal for the authoritative cutoff per election.
   */
  deadlineDaysBeforeElection: number;
  /** Acceptable ID at the polls. Plain English. */
  idRequirements: string;
  /** Notable nuances or recent changes (mail-in expansion, voter ID law). */
  notes?: string;
}

export const STATE_REGISTRATION_INFO: Record<string, StateRegistrationInfo> = {
  AL: { stateCode: "AL", stateName: "Alabama", portalURL: "https://www.alabamavotes.gov/olvr", online: true, sameDay: false, automaticAtDMV: false, deadlineDaysBeforeElection: 15, idRequirements: "Photo ID required at polls." },
  AK: { stateCode: "AK", stateName: "Alaska", portalURL: "https://voterregistration.alaska.gov", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 30, idRequirements: "ID required if a first-time voter who registered by mail." },
  AZ: { stateCode: "AZ", stateName: "Arizona", portalURL: "https://servicearizona.com/VoterRegistration", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 29, idRequirements: "Photo ID or two non-photo IDs required at polls." },
  AR: { stateCode: "AR", stateName: "Arkansas", portalURL: "https://www.sos.arkansas.gov/elections/voter-information", online: false, sameDay: false, automaticAtDMV: false, deadlineDaysBeforeElection: 30, idRequirements: "Photo ID required at polls." },
  CA: { stateCode: "CA", stateName: "California", portalURL: "https://registertovote.ca.gov", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 15, idRequirements: "ID required only if first-time voter who registered by mail without ID number." },
  CO: { stateCode: "CO", stateName: "Colorado", portalURL: "https://www.sos.state.co.us/Voter", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 8, idRequirements: "ID required when voting in person. Mail ballots default for all voters." },
  CT: { stateCode: "CT", stateName: "Connecticut", portalURL: "https://voterregistration.ct.gov", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 7, idRequirements: "ID encouraged; alternative affidavit accepted." },
  DE: { stateCode: "DE", stateName: "Delaware", portalURL: "https://ivote.de.gov/VoterView", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 24, idRequirements: "ID requested but signature alternative accepted." },
  FL: { stateCode: "FL", stateName: "Florida", portalURL: "https://registertovoteflorida.gov", online: true, sameDay: false, automaticAtDMV: false, deadlineDaysBeforeElection: 29, idRequirements: "Photo + signature ID required (driver's license, passport, etc.)." },
  GA: { stateCode: "GA", stateName: "Georgia", portalURL: "https://registertovote.sos.ga.gov", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 29, idRequirements: "Photo ID required at polls. Free state ID available." },
  HI: { stateCode: "HI", stateName: "Hawaii", portalURL: "https://olvr.hawaii.gov", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 10, idRequirements: "ID required at polls. State runs primarily by-mail." },
  ID: { stateCode: "ID", stateName: "Idaho", portalURL: "https://idahovotes.gov", online: true, sameDay: true, automaticAtDMV: false, deadlineDaysBeforeElection: 25, idRequirements: "Photo ID required at polls (affidavit alternative)." },
  IL: { stateCode: "IL", stateName: "Illinois", portalURL: "https://ova.elections.il.gov", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 16, idRequirements: "ID required only for first-time voters." },
  IN: { stateCode: "IN", stateName: "Indiana", portalURL: "https://indianavoters.in.gov", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 29, idRequirements: "Photo ID required at polls." },
  IA: { stateCode: "IA", stateName: "Iowa", portalURL: "https://sos.iowa.gov/elections/voterreg/onlineregistration.html", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 15, idRequirements: "Photo ID required at polls." },
  KS: { stateCode: "KS", stateName: "Kansas", portalURL: "https://www.kdor.ks.gov/Apps/VoterReg", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 21, idRequirements: "Photo ID required at polls." },
  KY: { stateCode: "KY", stateName: "Kentucky", portalURL: "https://elect.ky.gov/Pages/default.aspx", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 29, idRequirements: "Photo ID required at polls (alternative form available)." },
  LA: { stateCode: "LA", stateName: "Louisiana", portalURL: "https://voterportal.sos.la.gov", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 20, idRequirements: "Photo ID required (alternative signature affidavit accepted)." },
  ME: { stateCode: "ME", stateName: "Maine", portalURL: "https://www.maine.gov/sos/cec/elec/voter-info/voterguide.html", online: false, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 21, idRequirements: "ID required only if first-time voter." },
  MD: { stateCode: "MD", stateName: "Maryland", portalURL: "https://elections.maryland.gov/voter_registration", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 21, idRequirements: "ID required only for first-time voters who registered by mail." },
  MA: { stateCode: "MA", stateName: "Massachusetts", portalURL: "https://www.sec.state.ma.us/ovr", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 10, idRequirements: "ID required only for first-time voters or in mismatch cases." },
  MI: { stateCode: "MI", stateName: "Michigan", portalURL: "https://mvic.sos.state.mi.us/RegisterVoter", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 15, idRequirements: "Photo ID requested (affidavit alternative)." },
  MN: { stateCode: "MN", stateName: "Minnesota", portalURL: "https://mnvotes.sos.mn.gov/VoterRegistration", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 21, idRequirements: "ID required only for same-day registration or first-time voters." },
  MS: { stateCode: "MS", stateName: "Mississippi", portalURL: "https://www.sos.ms.gov/elections-voting/voter-registration-information", online: false, sameDay: false, automaticAtDMV: false, deadlineDaysBeforeElection: 30, idRequirements: "Photo ID required at polls." },
  MO: { stateCode: "MO", stateName: "Missouri", portalURL: "https://www.sos.mo.gov/elections/goVoteMissouri/register", online: true, sameDay: false, automaticAtDMV: false, deadlineDaysBeforeElection: 27, idRequirements: "Photo ID required at polls." },
  MT: { stateCode: "MT", stateName: "Montana", portalURL: "https://sosmt.gov/elections/vote", online: false, sameDay: true, automaticAtDMV: false, deadlineDaysBeforeElection: 30, idRequirements: "Photo ID required at polls (alternative forms accepted)." },
  NE: { stateCode: "NE", stateName: "Nebraska", portalURL: "https://www.nebraska.gov/apps-sos-voter-registration", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 18, idRequirements: "Photo ID required at polls (2024 law)." },
  NV: { stateCode: "NV", stateName: "Nevada", portalURL: "https://www.nvsos.gov/sosvoterservices/Registration/Step0.aspx", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 28, idRequirements: "ID required only for first-time voters." },
  NH: { stateCode: "NH", stateName: "New Hampshire", portalURL: "https://www.sos.nh.gov/elections/voters/registering-vote", online: false, sameDay: true, automaticAtDMV: false, deadlineDaysBeforeElection: 13, idRequirements: "Photo ID required at polls (affidavit alternative)." },
  NJ: { stateCode: "NJ", stateName: "New Jersey", portalURL: "https://voter.svrs.nj.gov/register", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 21, idRequirements: "ID required only for first-time voters." },
  NM: { stateCode: "NM", stateName: "New Mexico", portalURL: "https://portal.sos.state.nm.us/OVR/WebPages/InstructionsStep1.aspx", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 28, idRequirements: "ID required only for first-time voters who registered by mail." },
  NY: { stateCode: "NY", stateName: "New York", portalURL: "https://elections.ny.gov/election-day", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 10, idRequirements: "ID required only for first-time voters who registered by mail." },
  NC: { stateCode: "NC", stateName: "North Carolina", portalURL: "https://www.ncsbe.gov/registering", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 25, idRequirements: "Photo ID required at polls (free state ID available)." },
  ND: { stateCode: "ND", stateName: "North Dakota", portalURL: "https://vip.sos.nd.gov", online: false, sameDay: true, automaticAtDMV: false, deadlineDaysBeforeElection: 0, idRequirements: "Photo ID required at polls. North Dakota does NOT require voter registration." },
  OH: { stateCode: "OH", stateName: "Ohio", portalURL: "https://olvr.ohiosos.gov", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 30, idRequirements: "Photo ID required at polls (2023 law)." },
  OK: { stateCode: "OK", stateName: "Oklahoma", portalURL: "https://oklahoma.gov/elections/voter-registration.html", online: true, sameDay: false, automaticAtDMV: false, deadlineDaysBeforeElection: 25, idRequirements: "Photo ID or state voter ID required at polls." },
  OR: { stateCode: "OR", stateName: "Oregon", portalURL: "https://sos.oregon.gov/voting/Pages/registration.aspx", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 21, idRequirements: "ID needed only if first-time voter without driver's license number. State runs by-mail." },
  PA: { stateCode: "PA", stateName: "Pennsylvania", portalURL: "https://www.pavoterservices.pa.gov/Pages/VoterRegistrationApplication.aspx", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 15, idRequirements: "ID required only for first-time voters at a precinct." },
  RI: { stateCode: "RI", stateName: "Rhode Island", portalURL: "https://vote.sos.ri.gov/Voter/RegisterToVote", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 30, idRequirements: "Photo ID required at polls." },
  SC: { stateCode: "SC", stateName: "South Carolina", portalURL: "https://info.scvotes.sc.gov/eng/ovr/start.aspx", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 30, idRequirements: "Photo ID required at polls (alternative reasonable impediment process)." },
  SD: { stateCode: "SD", stateName: "South Dakota", portalURL: "https://sdsos.gov/elections-voting/voting/register-to-vote.aspx", online: false, sameDay: false, automaticAtDMV: false, deadlineDaysBeforeElection: 15, idRequirements: "Photo ID required at polls." },
  TN: { stateCode: "TN", stateName: "Tennessee", portalURL: "https://ovr.govote.tn.gov", online: true, sameDay: false, automaticAtDMV: false, deadlineDaysBeforeElection: 30, idRequirements: "Photo ID required at polls (federal ID accepted)." },
  TX: { stateCode: "TX", stateName: "Texas", portalURL: "https://www.votetexas.gov/register-to-vote", online: false, sameDay: false, automaticAtDMV: false, deadlineDaysBeforeElection: 30, idRequirements: "Photo ID required at polls (7 accepted forms)." },
  UT: { stateCode: "UT", stateName: "Utah", portalURL: "https://secure.utah.gov/voterreg/", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 11, idRequirements: "ID required only for first-time voters. State runs primarily by-mail." },
  VT: { stateCode: "VT", stateName: "Vermont", portalURL: "https://olvr.vermont.gov", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 0, idRequirements: "No ID required at polls." },
  VA: { stateCode: "VA", stateName: "Virginia", portalURL: "https://www.elections.virginia.gov/registration/how-to-register", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 22, idRequirements: "ID required at polls (alternative ID statement accepted)." },
  WA: { stateCode: "WA", stateName: "Washington", portalURL: "https://voter.votewa.gov", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 8, idRequirements: "No ID required at polls (state is fully by-mail)." },
  WV: { stateCode: "WV", stateName: "West Virginia", portalURL: "https://ovr.sos.wv.gov", online: true, sameDay: false, automaticAtDMV: true, deadlineDaysBeforeElection: 21, idRequirements: "Photo ID required at polls (alternative IDs accepted)." },
  WI: { stateCode: "WI", stateName: "Wisconsin", portalURL: "https://myvote.wi.gov/en-US/RegisterToVote", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 20, idRequirements: "Photo ID required at polls." },
  WY: { stateCode: "WY", stateName: "Wyoming", portalURL: "https://sos.wyo.gov/Elections/Default.aspx", online: false, sameDay: true, automaticAtDMV: false, deadlineDaysBeforeElection: 14, idRequirements: "Photo ID required at polls (2021 law)." },
  DC: { stateCode: "DC", stateName: "District of Columbia", portalURL: "https://dcboe.org/Voters/Register-To-Vote", online: true, sameDay: true, automaticAtDMV: true, deadlineDaysBeforeElection: 21, idRequirements: "No photo ID required to vote at polls." },
};

export function getStateRegistrationInfo(stateCode: string): StateRegistrationInfo | null {
  return STATE_REGISTRATION_INFO[stateCode.toUpperCase()] ?? null;
}
