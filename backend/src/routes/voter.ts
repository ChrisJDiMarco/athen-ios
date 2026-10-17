import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { rateLimit } from "../lib/rateLimiter.js";
import type { VoterRailService } from "../services/voterRail.js";
import type { SampleBallotService } from "../services/sampleBallot.js";
import type { RepScorecardService, ScorecardFilingInput } from "../services/repScorecard.js";
import type { LocationResolver } from "../services/locationResolver.js";
import type { OpenSecretsService } from "../services/openSecrets.js";

const MIN = 60_000;
const lookupLimiter = rateLimit({ name: "voter:lookup", max: 60, windowMs: 5 * MIN });
const ballotLimiter = rateLimit({ name: "voter:ballot", max: 20, windowMs: 5 * MIN });
const scorecardLimiter = rateLimit({ name: "voter:scorecard", max: 40, windowMs: 5 * MIN });

const ZipQuery = z.object({ zip: z.string().min(5).max(10) });
const StateParam = z.object({ stateCode: z.string().length(2) });
const BallotQuery = z.object({
  zip: z.string().min(5).max(10),
  electionId: z.string().optional(),
});

const ScorecardBody = z.object({
  filings: z.array(
    z.object({
      issueId: z.string().min(1),
      issueTitle: z.string().min(1),
      position: z.enum(["endorse", "oppose"]),
      filedAtISO: z.string().min(1),
      officialName: z.string().min(1),
    }),
  ),
});

export interface VoterRouteDeps {
  voterRail: VoterRailService;
  ballot: SampleBallotService;
  scorecard: RepScorecardService;
  locations: LocationResolver;
  openSecrets: OpenSecretsService;
}

const FinanceQuery = z.object({
  officialName: z.string().min(2),
  cid: z.string().optional(),
  stateCode: z.string().length(2).optional(),
  chamber: z.enum(["S", "H"]).optional(),
});

export function voterRoute(deps: VoterRouteDeps): FastifyPluginAsync {
  return async function (fastify: FastifyInstance) {
    fastify.get("/v1/voter/elections", async (request, reply) => {
      if (!lookupLimiter(request, reply)) return;
      if (!deps.voterRail.enabled) {
        return reply.send({ enabled: false, elections: [], notice: "Google Civic API key not configured. Set GOOGLE_CIVIC_API_KEY to enable upcoming-elections data." });
      }
      try {
        const elections = await deps.voterRail.listElections();
        return reply.send({ enabled: true, elections });
      } catch (err) {
        return reply.code(502).send({ error: { code: "elections_failed", message: err instanceof Error ? err.message : "Lookup failed." } });
      }
    });

    fastify.get("/v1/voter/polling-place", async (request, reply) => {
      if (!lookupLimiter(request, reply)) return;
      const parsed = ZipQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      if (!deps.voterRail.enabled) {
        return reply.send({
          enabled: false,
          pollingPlaces: [],
          notice: "Polling place lookup requires GOOGLE_CIVIC_API_KEY. Visit vote.gov to find yours.",
        });
      }
      try {
        const location = await deps.locations.resolveFromZip(parsed.data.zip);
        const address = location.normalized ?? `${parsed.data.zip}`;
        const info = await deps.voterRail.voterInfo(address);
        return reply.send({
          enabled: true,
          pollingPlaces: info.pollingPlaces,
          earlyVoteSites: info.earlyVoteSites,
          dropOffLocations: info.dropOffLocations,
          election: info.election,
          state: info.state,
        });
      } catch (err) {
        return reply.code(502).send({ error: { code: "polling_failed", message: err instanceof Error ? err.message : "Lookup failed." } });
      }
    });

    fastify.get("/v1/voter/ballot", async (request, reply) => {
      if (!ballotLimiter(request, reply)) return;
      const parsed = BallotQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      if (!deps.voterRail.enabled) {
        return reply.send({
          enabled: false,
          ballot: null,
          notice: "Sample ballot lookup requires GOOGLE_CIVIC_API_KEY. Visit your secretary of state's site to find your sample ballot.",
        });
      }
      try {
        const location = await deps.locations.resolveFromZip(parsed.data.zip);
        const address = location.normalized ?? `${parsed.data.zip}`;
        const info = await deps.voterRail.voterInfo(address, parsed.data.electionId);
        const ballot = await deps.ballot.generate(info);
        return reply.send({
          enabled: true,
          ballot,
          pollingPlaces: info.pollingPlaces,
          state: info.state,
        });
      } catch (err) {
        return reply.code(502).send({ error: { code: "ballot_failed", message: err instanceof Error ? err.message : "Ballot lookup failed." } });
      }
    });

    fastify.get("/v1/voter/registration/:stateCode", async (request, reply) => {
      if (!lookupLimiter(request, reply)) return;
      const parsed = StateParam.safeParse(request.params);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_params", message: parsed.error.message } });
      }
      const info = deps.voterRail.getRegistrationInfo(parsed.data.stateCode);
      if (!info) {
        return reply.code(404).send({ error: { code: "state_not_found", message: `No registration data for ${parsed.data.stateCode}.` } });
      }
      return reply.send({ registration: info });
    });

    fastify.get("/v1/voter/registration", async (_request, reply) => {
      return reply.send({ registration: deps.voterRail.allRegistrationInfo() });
    });

    fastify.get("/v1/voter/finance", async (request, reply) => {
      if (!lookupLimiter(request, reply)) return;
      const parsed = FinanceQuery.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_query", message: parsed.error.message } });
      }
      if (!deps.openSecrets.enabled) {
        return reply.send({
          enabled: false,
          finance: null,
          notice: "Campaign finance requires OPENSECRETS_API_KEY on the backend.",
        });
      }
      try {
        const args: { officialName: string; cid?: string; stateCode?: string; chamber?: "S" | "H" } = {
          officialName: parsed.data.officialName,
        };
        if (parsed.data.cid) args.cid = parsed.data.cid;
        if (parsed.data.stateCode) args.stateCode = parsed.data.stateCode;
        if (parsed.data.chamber) args.chamber = parsed.data.chamber;
        const summary = await deps.openSecrets.summaryFor(args);
        return reply.send({ enabled: true, finance: summary });
      } catch (err) {
        return reply.code(502).send({
          error: { code: "finance_failed", message: err instanceof Error ? err.message : "OpenSecrets lookup failed." },
        });
      }
    });

    fastify.post("/v1/voter/scorecard", async (request, reply) => {
      if (!scorecardLimiter(request, reply)) return;
      const parsed = ScorecardBody.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: { code: "invalid_body", message: parsed.error.message } });
      }
      const filings: ScorecardFilingInput[] = parsed.data.filings;
      const result = deps.scorecard.build(filings);
      return reply.send(result);
    });
  };
}
