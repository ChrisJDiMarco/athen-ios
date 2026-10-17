#!/usr/bin/env bash
# Athen — one-command bootstrap.
#
# Installs backend deps, walks you through API keys, writes backend/.env, and
# starts the Fastify server on http://localhost:8787. Re-run any time —
# existing values in .env are preserved unless you choose to overwrite.
#
# Usage:
#   ./bootstrap.sh              # interactive setup + start
#   ./bootstrap.sh --no-start   # set up only, don't launch the server
#   ./bootstrap.sh --check      # show what's configured, don't change anything
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND="$ROOT/backend"
ENV_FILE="$BACKEND/.env"
ENV_EXAMPLE="$BACKEND/.env.example"

# ────── colors ──────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
else
  BOLD=''; DIM=''; RESET=''; CYAN=''; GREEN=''; YELLOW=''; RED=''
fi

header() { printf "\n${BOLD}${CYAN}▌ %s${RESET}\n" "$1"; }
ok()     { printf "${GREEN}✓${RESET} %s\n" "$1"; }
warn()   { printf "${YELLOW}!${RESET} %s\n" "$1"; }
fail()   { printf "${RED}✗ %s${RESET}\n" "$1" >&2; }

# ────── flags ──────
MODE="setup"
for arg in "$@"; do
  case "$arg" in
    --no-start) MODE="setup" ;;
    --check)    MODE="check" ;;
    --start)    MODE="start" ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) fail "Unknown flag: $arg"; exit 2 ;;
  esac
done

# ────── prereqs ──────
header "Checking prerequisites"
command -v node >/dev/null || { fail "node is required (https://nodejs.org)"; exit 1; }
node_major=$(node -p 'process.versions.node.split(".")[0]')
if (( node_major < 20 )); then
  fail "node >= 20 required, found $(node -v)"; exit 1
fi
ok "node $(node -v)"
command -v npm >/dev/null || { fail "npm is required"; exit 1; }
ok "npm $(npm -v)"
command -v xcodebuild >/dev/null && ok "xcodebuild $(xcodebuild -version | head -1)" || warn "xcodebuild not found — iOS build will need to be opened manually"

# ────── read existing .env on demand (works on macOS bash 3.2) ──────
get_current() {
  local key="$1"
  [[ -f "$ENV_FILE" ]] || { printf ''; return; }
  # Match KEY=value at start-of-line; trim everything after the first =.
  local line
  line=$(grep -m1 "^${key}=" "$ENV_FILE" 2>/dev/null || true)
  [[ -z "$line" ]] && { printf ''; return; }
  printf '%s' "${line#${key}=}"
}

# ────── --check mode ──────
if [[ "$MODE" == "check" ]]; then
  header "Current configuration"
  if [[ ! -f "$ENV_FILE" ]]; then
    warn "No backend/.env file yet. Run './bootstrap.sh' to create one."
  else
    print_status() {
      local key="$1" label="$2"
      local val
      val="$(get_current "$key")"
      if [[ -n "$val" && "$val" != "sk-ant-..." && "$val" != "civic@yourdomain.example" ]]; then
        printf "  ${GREEN}✓${RESET} %-26s %s\n" "$label" "${DIM}set${RESET}"
      else
        printf "  ${DIM}·${RESET} %-26s %s\n" "$label" "${DIM}unset${RESET}"
      fi
    }
    print_status ANTHROPIC_API_KEY  "Claude (required)"
    print_status OPENSTATES_API_KEY "OpenStates"
    print_status FIRECRAWL_API_KEY  "Firecrawl"
    print_status POSTMARK_SERVER_TOKEN "Postmark (real email)"
    print_status ELEVENLABS_API_KEY "ElevenLabs voice"
    print_status CONGRESSGOV_API_KEY "Congress.gov"
  fi
  exit 0
fi

# ────── --start mode ──────
if [[ "$MODE" == "start" ]]; then
  [[ -f "$ENV_FILE" ]] || { fail "No backend/.env. Run ./bootstrap.sh first."; exit 1; }
  header "Starting backend on :8787"
  cd "$BACKEND"
  exec npm run dev
fi

# ────── interactive prompts ──────
header "Athen bootstrap"
cat <<EOF
${DIM}This walks through the API keys the backend needs. Press ENTER on any prompt
to keep what's already in backend/.env (or leave blank to skip that integration).
The script never echoes keys to the terminal.${RESET}

EOF

prompt_key() {
  local key="$1" label="$2" required="$3" url="$4"
  local existing="$(get_current "$key")"
  local placeholder="" hint=""
  if [[ -n "$existing" && "$existing" != "sk-ant-..." && "$existing" != "civic@yourdomain.example" ]]; then
    placeholder="(already set — ENTER to keep)"
  elif [[ "$required" == "yes" ]]; then
    placeholder="(REQUIRED)"
  else
    placeholder="(optional, ENTER to skip)"
  fi
  [[ -n "$url" ]] && hint="${DIM} → $url${RESET}"
  printf "${BOLD}%s${RESET} %s%s\n" "$label" "$placeholder" "$hint"
  printf "  ${CYAN}%s${RESET}: " "$key"
  local input=""
  IFS= read -rs input
  echo
  if [[ -z "$input" ]]; then
    printf '%s' "$existing"
  else
    printf '%s' "$input"
  fi
}

prompt_value() {
  local key="$1" label="$2" default="$3"
  local existing="$(get_current "$key")"
  local current="${existing:-$default}"
  printf "${BOLD}%s${RESET} ${DIM}[%s]${RESET}\n  ${CYAN}%s${RESET}: " "$label" "$current" "$key"
  local input=""
  IFS= read -r input
  if [[ -z "$input" ]]; then
    printf '%s' "$current"
  else
    printf '%s' "$input"
  fi
}

ANTHROPIC_API_KEY="$(prompt_key ANTHROPIC_API_KEY 'Anthropic (Claude)'  yes 'https://console.anthropic.com/settings/keys')"
OPENSTATES_API_KEY="$(prompt_key OPENSTATES_API_KEY 'OpenStates (state reps)' no 'https://openstates.org/accounts/profile/')"
FIRECRAWL_API_KEY="$(prompt_key FIRECRAWL_API_KEY 'Firecrawl (news + scraping)' no 'https://firecrawl.dev')"
CONGRESSGOV_API_KEY="$(prompt_key CONGRESSGOV_API_KEY 'Congress.gov (federal data)' no 'https://api.congress.gov/sign-up/')"
GOVINFO_API_KEY="$(prompt_key GOVINFO_API_KEY 'GovInfo' no 'https://api.govinfo.gov/docs/')"
POSTMARK_SERVER_TOKEN="$(prompt_key POSTMARK_SERVER_TOKEN 'Postmark (REAL email — leave blank for dry-run)' no 'https://postmarkapp.com')"
EMAIL_FROM_ADDRESS=""
if [[ -n "$POSTMARK_SERVER_TOKEN" ]]; then
  EMAIL_FROM_ADDRESS="$(prompt_value EMAIL_FROM_ADDRESS 'Verified sender email' 'civic@yourdomain.example')"
fi
ELEVENLABS_API_KEY="$(prompt_key ELEVENLABS_API_KEY 'ElevenLabs (voice)' no 'https://elevenlabs.io')"
ELEVENLABS_AGENT_ID=""
if [[ -n "$ELEVENLABS_API_KEY" ]]; then
  ELEVENLABS_AGENT_ID="$(prompt_value ELEVENLABS_AGENT_ID 'ElevenLabs agent ID' '')"
fi

if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  fail "ANTHROPIC_API_KEY is required. Get one at https://console.anthropic.com and re-run."
  exit 1
fi

# ────── write .env ──────
header "Writing $ENV_FILE"
mkdir -p "$BACKEND"
cat > "$ENV_FILE" <<EOF
# Generated by bootstrap.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
PORT=8787
NODE_ENV=development

# Anthropic
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
ANTHROPIC_MODEL=$(get_current ANTHROPIC_MODEL | grep -v '^$' || echo claude-sonnet-4-6)

# Email
EMAIL_DRY_RUN=$([[ -n "$POSTMARK_SERVER_TOKEN" ]] && echo false || echo true)
POSTMARK_SERVER_TOKEN=$POSTMARK_SERVER_TOKEN
EMAIL_FROM_ADDRESS=$EMAIL_FROM_ADDRESS
EMAIL_FROM_NAME=$(get_current EMAIL_FROM_NAME | grep -v '^$' || echo 'Athen')
EMAIL_DRY_RUN_RECIPIENT=$(get_current EMAIL_DRY_RUN_RECIPIENT)

# OpenStates
OPENSTATES_API_KEY=$OPENSTATES_API_KEY
OPENSTATES_JURISDICTIONS=$(get_current OPENSTATES_JURISDICTIONS | grep -v '^$' || echo Pennsylvania)

# Government data
CONGRESSGOV_API_KEY=$CONGRESSGOV_API_KEY
GOVINFO_API_KEY=$GOVINFO_API_KEY
REGULATIONS_API_KEY=$(get_current REGULATIONS_API_KEY)
SOCRATA_APP_TOKEN=$(get_current SOCRATA_APP_TOKEN)
SOCRATA_CATALOG_DOMAINS=$(get_current SOCRATA_CATALOG_DOMAINS | grep -v '^$' || echo 'data.cityofnewyork.us,data.sfgov.org,data.cityofchicago.org')
OPEN311_ENDPOINTS=$(get_current OPEN311_ENDPOINTS)

# Firecrawl
FIRECRAWL_API_KEY=$FIRECRAWL_API_KEY

# Voice
ELEVENLABS_API_KEY=$ELEVENLABS_API_KEY
ELEVENLABS_AGENT_ID=$ELEVENLABS_AGENT_ID

# Admin
ADMIN_API_TOKEN=$(get_current ADMIN_API_TOKEN)

# Scheduler
INGEST_SCHEDULE_ENABLED=$(get_current INGEST_SCHEDULE_ENABLED | grep -v '^$' || echo false)
INGEST_INTERVAL_MINUTES=$(get_current INGEST_INTERVAL_MINUTES | grep -v '^$' || echo 360)
INGEST_CLIENTS=$(get_current INGEST_CLIENTS)
EOF
chmod 600 "$ENV_FILE"
ok "Wrote $ENV_FILE"

# ────── install + districts ──────
if [[ ! -d "$BACKEND/node_modules" ]]; then
  header "Installing backend dependencies"
  (cd "$BACKEND" && npm install)
  ok "npm install complete"
else
  ok "Backend deps already installed"
fi

if [[ ! -f "$BACKEND/data/districts.json" ]]; then
  header "Fetching congressional district boundaries (first run only)"
  (cd "$BACKEND" && npm run fetch:districts) || warn "fetch:districts failed (federal reps will fall back to defaults)"
fi

# ────── done ──────
cat <<EOF

${GREEN}${BOLD}✓ Bootstrap complete.${RESET}

${BOLD}Next steps:${RESET}

  ${CYAN}1.${RESET} Start the backend
       ${BOLD}./bootstrap.sh --start${RESET}            # or:  cd backend && npm run dev
       ${DIM}backend listens on http://localhost:8787${RESET}

  ${CYAN}2.${RESET} Open the iOS project
       ${BOLD}open CivicOS.xcodeproj${RESET}

  ${CYAN}3.${RESET} Run on iPhone simulator (any iPhone 16 family). Once it launches:
       • Set a ZIP in onboarding (try 19129 for Philadelphia, 10001 for NYC).
       • Tap the ${BOLD}You${RESET} tab → ${BOLD}AI backend${RESET} → enter ${BOLD}http://localhost:8787${RESET} → Save & test.
       • Status chip should flip to green ${GREEN}Connected${RESET}.
       • Open the ${BOLD}Assistant${RESET} tab and ask "what should I act on first?" to verify the Claude stream.

${DIM}To re-run setup later:        ./bootstrap.sh${RESET}
${DIM}To inspect current keys:      ./bootstrap.sh --check${RESET}
${DIM}To just start the server:     ./bootstrap.sh --start${RESET}
EOF
