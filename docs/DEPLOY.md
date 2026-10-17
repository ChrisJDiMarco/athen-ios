# Deploy Athen backend to Railway

The iOS app is local-first, but the AI features (Brief generation, Assistant chat, audio briefings, filing drafts) need a backend with API keys. Railway is the fastest path to a real HTTPS URL anyone can reach.

## One-time setup (about 10 min)

### 1. Sign up for Railway

[railway.app](https://railway.app) — free tier works fine for one or a few users.

### 2. Install the CLI

```sh
brew install railway
# or
npm install -g @railway/cli
```

### 3. Log in and create the project

```sh
cd backend
railway login          # opens browser
railway init           # creates a new Railway project, links this folder
```

### 4. Provision the service

In the Railway dashboard, your new project has one service that auto-detects the `Dockerfile` and `railway.json`. Confirm health checks point to `/healthz`. Don't deploy yet — env vars come next.

## Every deploy

From the repo root:

```sh
./scripts/deploy-railway.sh           # full deploy (env + build)
./scripts/deploy-railway.sh --env-only # push env vars, skip build
./scripts/deploy-railway.sh --check    # list what would be pushed
```

The script:
1. Reads non-empty keys from `backend/.env`
2. Pushes each as a Railway environment variable (`railway variables --set`)
3. Sets `NODE_ENV=production`
4. Triggers `railway up` to build + deploy from local source

### Watch the build

```sh
cd backend
railway logs           # streams build + runtime logs
```

### Get the public URL

```sh
cd backend
railway domain         # creates an athen-backend-production.up.railway.app domain
```

## After it's live

1. Open the URL in a browser. You should see a 404 (no `/` route) or hit `/healthz` for the status JSON.
2. In the iOS app: **You** tab → **AI backend** → paste the URL → **Save & test**.
3. The status chip should flip to **Connected**.

## Custom domain

Railway → Service → Settings → Domains → **Custom Domain**. Add `api.athen.app` (or whatever) and follow the CNAME instructions. Free TLS certs.

## What this costs

Single-user, light traffic:
- Railway Hobby plan: $5/month (includes $5 of usage credit — backend uses well under that)
- Anthropic Claude: $0.02–0.05 per brief generated (cached after first run; ~$1/month for personal use)
- ElevenLabs (optional): $5/month starter for ~30,000 chars TTS
- Postmark (optional, real email): free tier 100 emails/month

About **$5–10/month** to run for yourself + a few friends.

## Scaling up

When more than a few people use it:
- Railway autoscales the service
- JSON files (issue store, brief cache, comments) need to move to Postgres — add `DATABASE_URL` to Railway env, write a migration. See [Tier 3 in the production-readiness roadmap].
- Switch from local notifications to APNS push for cross-device sync

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `railway up` errors `not linked` | `cd backend && railway link <project>` |
| Build succeeds but `/healthz` returns 502 | Check `railway logs` for missing env vars — config.ts throws if `ANTHROPIC_API_KEY` is unset |
| iOS app shows "Offline" after pointing at URL | Check `Accept: application/json` reaches the URL (Railway terminates TLS fine; if you put Cloudflare in front make sure it's not blocking) |
| Audio briefings sound robotic | `ELEVENLABS_API_KEY` not set in Railway — push it via `./scripts/deploy-railway.sh --env-only` |
| Cost spiking | Check Railway usage dashboard. If Claude calls dominate, the brief cache may not be persisting (Railway resets `/tmp` on redeploy — see Postgres migration above) |

## Rolling back

```sh
cd backend
railway deployments    # list recent deployments
railway redeploy <id>  # restore a known-good build
```
