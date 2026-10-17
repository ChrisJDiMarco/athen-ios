import Fastify from "fastify";
import { config } from "./config.js";
import { fileRoute } from "./routes/file.js";
import { profileRoute } from "./routes/profile.js";
import { chatRoute } from "./routes/chat.js";
import { backgroundRoute } from "./routes/background.js";
import { adminRoute } from "./routes/admin.js";
import { issuesRoute } from "./routes/issues.js";
import { sourcesRoute } from "./routes/sources.js";
import { refreshRoute } from "./routes/refresh.js";
import { briefRoute } from "./routes/brief.js";
import { briefingRoute } from "./routes/briefing.js";
import { ballotRoute } from "./routes/ballot.js";
import { integrationsRoute } from "./routes/integrations.js";
import { ComposioService } from "./services/composio.js";
import { PetitionStore } from "./services/petitionStore.js";
import { petitionsRoute } from "./routes/petitions.js";
import { PetitionDeliveryWorker } from "./services/petitionWorker.js";
import { VoterRailService } from "./services/voterRail.js";
import { SampleBallotService } from "./services/sampleBallot.js";
import { RepScorecardService } from "./services/repScorecard.js";
import { voterRoute } from "./routes/voter.js";
import { VoteStore } from "./services/voteStore.js";
import { VoteIngestor } from "./services/voteIngestor.js";
import { VoteWorker } from "./services/voteWorker.js";
import { GovInfoService } from "./services/govInfo.js";
import { OpenSecretsService } from "./services/openSecrets.js";
import { LocalDataService } from "./services/localData.js";
import { localRoute } from "./routes/local.js";
import { OfficialsDirectoryService } from "./services/officialsDirectory.js";
import { officialsRoute } from "./routes/officials.js";
import { LifeEventsService } from "./services/lifeEvents.js";
import { lifeEventsRoute } from "./routes/lifeEvents.js";
import { draftVariantsRoute } from "./routes/draftVariants.js";
import { servicesRoute } from "./routes/services.js";
import { evidenceRoute } from "./routes/evidence.js";
import { briefsRoute } from "./routes/briefs.js";
import { voiceRoute } from "./routes/voice.js";
import { speechRoute } from "./routes/speech.js";
import { speechService } from "./services/speech.js";
import { registerInstallAuth } from "./lib/installAuth.js";
import { ModerationStore } from "./services/moderationStore.js";
import { moderationRoute } from "./routes/moderation.js";
import { podcastRoute } from "./routes/podcast.js";
import { tickerRoute } from "./routes/ticker.js";
import { dataDeleteRoute } from "./routes/dataDelete.js";
import { quotaRoute } from "./routes/quota.js";
import { newsRoute } from "./routes/news.js";
import { CompositeLocationResolver } from "./services/locationResolver.js";
import { JurisdictionAwareOfficialResolver } from "./services/officialResolver.js";
import { StaticFederalOfficialsLookup } from "./services/federalOfficialsLookup.js";
import { OpenStatesLegislatorsLookup } from "./services/stateLegislatorsLookup.js";
import { ClaudeMessageDrafter } from "./services/messageDrafter.js";
import { makeEmailFiler } from "./services/emailFiler.js";
import { ChatAssistant } from "./services/chatAssistant.js";
import { FirecrawlNewsCorroborator } from "./services/newsCorroborator.js";
import { FirecrawlIngestionPipeline } from "./services/ingestionPipeline.js";
import { LegistarConnector } from "./services/connectors/legistar.js";
import { IssueStore } from "./services/issueStore.js";
import { DefaultJurisdictionIngestor } from "./services/jurisdictionIngestor.js";
import { ContactFormQueue } from "./services/contactFormQueue.js";
import { ChannelAwareFilingDispatcher } from "./services/filingDispatcher.js";
import { IngestionScheduler, parseClientsEnv } from "./services/scheduler.js";
import { IngestionOrchestrator } from "./services/ingestionOrchestrator.js";
import { BriefAnalysisService } from "./services/briefAnalysis.js";
import { AudioBriefingService } from "./services/audioBriefing.js";
import { CivicSourceRegistry } from "./services/sourceRegistry.js";
import { FirecrawlSourceDiscovery } from "./services/sourceDiscovery.js";
import { EvidenceVault } from "./services/evidenceVault.js";
import { CivicSourceSweeper } from "./services/connectors/civicSourceConnectors.js";
import { SavedSearchStore } from "./services/savedSearchStore.js";
import { FilingTallyStore } from "./services/filingTallyStore.js";
import { savedSearchesRoute } from "./routes/savedSearches.js";
import { urlAnalyzeRoute } from "./routes/urlAnalyze.js";
import { personalImpactRoute } from "./routes/personalImpact.js";

async function buildServer() {
  const fastify = Fastify({
    logger: {
      level: config.NODE_ENV === "production" ? "info" : "debug",
    },
  });

  const locations = new CompositeLocationResolver();
  const federal = new StaticFederalOfficialsLookup();
  const stateLegislators = new OpenStatesLegislatorsLookup(config.OPENSTATES_API_KEY);
  const officials = await JurisdictionAwareOfficialResolver.load({ federal, stateLegislators });
  const drafter = new ClaudeMessageDrafter();
  const filer = makeEmailFiler();
  const assistant = new ChatAssistant();
  const corroborator = new FirecrawlNewsCorroborator();
  const ingestion = new FirecrawlIngestionPipeline();
  const legistar = new LegistarConnector();
  const issueStore = await IssueStore.load();
  const evidenceVault = await EvidenceVault.load();
  await evidenceVault.seedFromIssues(issueStore.all());
  const sourceRegistry = new CivicSourceRegistry();
  const sourceDiscovery = new FirecrawlSourceDiscovery();
  const sourceSweeper = new CivicSourceSweeper();
  const contactFormQueue = await ContactFormQueue.load();
  const dispatcher = new ChannelAwareFilingDispatcher(filer, contactFormQueue);
  const jurisdictionIngestor = new DefaultJurisdictionIngestor(legistar, ingestion, issueStore, evidenceVault);
  const orchestrator = new IngestionOrchestrator(issueStore, jurisdictionIngestor);
  const briefAnalysis = await BriefAnalysisService.load();
  const govInfo = await GovInfoService.load();
  briefAnalysis.attachGovInfo(govInfo);
  const audioBriefing = new AudioBriefingService(briefAnalysis, issueStore);
  const petitionStore = await PetitionStore.load();
  const voterRail = VoterRailService.fromEnv();
  const sampleBallot = await SampleBallotService.load();
  const voteStore = await VoteStore.load();
  const repScorecard = new RepScorecardService(issueStore, voteStore);
  const openSecrets = await OpenSecretsService.load();
  const localData = new LocalDataService();
  const officialsDirectory = await OfficialsDirectoryService.load();
  // Kick off a directory refresh in the background on boot so federal
  // members are warm before the first user request.
  void officialsDirectory.refreshFederal();
  const lifeEvents = new LifeEventsService();
  const moderationStore = await ModerationStore.load();
  const savedSearches = await SavedSearchStore.load();
  const filingTally = await FilingTallyStore.load();
  const scheduler = new IngestionScheduler({
    enabled: config.INGEST_SCHEDULE_ENABLED,
    intervalMinutes: config.INGEST_INTERVAL_MINUTES,
    clients: parseClientsEnv(config.INGEST_CLIENTS),
    ingestor: jurisdictionIngestor,
    logger: {
      info: (msg, meta) => fastify.log.info(meta as object | undefined, msg),
      error: (msg, meta) => fastify.log.error(meta as object | undefined, msg),
    },
  });

  // Per-install auth must register before route plugins so the hook applies.
  registerInstallAuth(fastify);

  fastify.get("/healthz", async () => ({
    status: "ok",
    dryRun: config.EMAIL_DRY_RUN,
    model: config.ANTHROPIC_MODEL,
    email: config.POSTMARK_SERVER_TOKEN && config.EMAIL_FROM_ADDRESS ? "postmark" : "log-only",
    stateLegislators: config.OPENSTATES_API_KEY ? "enabled" : "disabled",
    firecrawl: config.FIRECRAWL_API_KEY ? "enabled" : "disabled",
    scheduler: config.INGEST_SCHEDULE_ENABLED ? "enabled" : "disabled",
    sources: sourceRegistry.list().length,
    issues: issueStore.stats(),
    evidence: evidenceVault.stats(),
    briefs: briefAnalysis.stats(),
    voice: config.ELEVENLABS_API_KEY && config.ELEVENLABS_AGENT_ID ? "elevenlabs-enabled" : "native-fallback",
    audioBriefing: config.ELEVENLABS_API_KEY ? "elevenlabs-tts" : "client-fallback",
    contactFormQueue: contactFormQueue.count(),
    integrations: config.COMPOSIO_API_KEY ? "composio-enabled" : "disabled",
    voterRail: config.GOOGLE_CIVIC_API_KEY ? "google-civic-enabled" : "registration-only",
    petitions: petitionStore.stats(),
    votes: voteStore.stats(),
    officials: officialsDirectory.stats(),
  }));

  const composio = ComposioService.fromEnv();
  await fastify.register(fileRoute({ locations, officials, drafter, dispatcher, composio, tally: filingTally }));
  await fastify.register(profileRoute({ locations, officials }));
  await fastify.register(chatRoute({ assistant }));
  await fastify.register(backgroundRoute({ corroborator }));
  await fastify.register(issuesRoute({ store: issueStore, sourceRegistry, votes: voteStore }));
  await fastify.register(savedSearchesRoute({ searches: savedSearches, issues: issueStore }));
  await fastify.register(urlAnalyzeRoute({ issues: issueStore }));
  await fastify.register(personalImpactRoute({ issues: issueStore, briefs: briefAnalysis }));
  await fastify.register(sourcesRoute({ sourceRegistry, issueStore }));
  await fastify.register(refreshRoute({ orchestrator }));
  await fastify.register(briefRoute({ briefs: briefAnalysis, issues: issueStore }));
  await fastify.register(briefingRoute({ audioBriefing }));
  await fastify.register(ballotRoute());
  await fastify.register(integrationsRoute({ composio }));
  await fastify.register(petitionsRoute({
    petitions: petitionStore,
    issues: issueStore,
    officials,
    locations,
    dispatcher,
    composio,
  }));
  await fastify.register(voterRoute({
    voterRail,
    ballot: sampleBallot,
    scorecard: repScorecard,
    locations,
    openSecrets,
  }));
  await fastify.register(lifeEventsRoute({ lifeEvents }));
  await fastify.register(localRoute({ localData }));
  await fastify.register(officialsRoute({ directory: officialsDirectory }));
  await fastify.register(speechRoute({ speech: speechService }));
  await fastify.register(moderationRoute({ store: moderationStore }));
  await fastify.register(podcastRoute({ audioBriefing, issues: issueStore }));
  await fastify.register(tickerRoute({ issues: issueStore, votes: voteStore }));
  await fastify.register(dataDeleteRoute({ petitions: petitionStore, moderation: moderationStore }));
  await fastify.register(quotaRoute());
  await fastify.register(newsRoute());

  // Background worker for petition delivery. Runs after server.listen so we
  // don't ship anything until the HTTP surface is up.
  const petitionWorker = new PetitionDeliveryWorker(
    petitionStore,
    dispatcher,
    composio,
    {
      info: (msg, meta) => fastify.log.info(meta as object | undefined, msg),
      error: (msg, meta) => fastify.log.error(meta as object | undefined, msg),
    },
  );

  // Vote ingestion worker — polls upstream APIs for roll-call votes on
  // bills we've already ingested. Powers the rep scorecard.
  const voteIngestor = new VoteIngestor(issueStore, voteStore, {
    info: (msg, meta) => fastify.log.info(meta as object | undefined, msg),
    error: (msg, meta) => fastify.log.error(meta as object | undefined, msg),
  });
  const voteWorker = new VoteWorker(voteIngestor, {
    info: (msg, meta) => fastify.log.info(meta as object | undefined, msg),
    error: (msg, meta) => fastify.log.error(meta as object | undefined, msg),
  });
  await fastify.register(draftVariantsRoute());
  await fastify.register(servicesRoute());
  await fastify.register(evidenceRoute({ vault: evidenceVault, store: issueStore }));
  await fastify.register(briefsRoute({ store: issueStore, evidenceVault }));
  await fastify.register(voiceRoute({
    issueStore,
    sourceRegistry,
    evidenceVault,
    locations,
    officials,
    drafter,
  }));
  await fastify.register(adminRoute({
    ingestion,
    jurisdictionIngestor,
    scheduler,
    contactFormQueue,
    issueStore,
    sourceRegistry,
    sourceDiscovery,
    evidenceVault,
    sourceSweeper,
  }));

  scheduler.start();
  petitionWorker.start();
  voteWorker.start();

  // Auto-seed: if the store boots empty, fire one orchestrator pass in the
  // background so the iOS app sees real civic items on first load instead of
  // a "nothing yet" screen. Failures are logged but don't block startup.
  if (issueStore.all().length === 0) {
    void orchestrator
      .run()
      .then((report) =>
        fastify.log.info({ report }, "auto-seed orchestrator finished"),
      )
      .catch((err) => fastify.log.error({ err }, "auto-seed orchestrator failed"));
  }

  return fastify;
}

async function main() {
  const server = await buildServer();
  try {
    await server.listen({ port: config.PORT, host: "0.0.0.0" });
    server.log.info(`Athen backend listening on :${config.PORT} (dry_run=${config.EMAIL_DRY_RUN})`);
  } catch (err) {
    server.log.error(err);
    process.exit(1);
  }
}

main();
