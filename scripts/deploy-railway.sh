#!/usr/bin/env bash
# Deploy the Athen backend to Railway.
#
# Reads backend/.env, pushes each non-empty variable as a Railway environment
# variable, then triggers a deploy from the local source. Idempotent —
# re-running updates env vars and ships a new build.
#
# Prereqs:
#   - Railway CLI installed:  https://docs.railway.app/develop/cli
#   - You've run `railway login` and `railway link` (in backend/) once
#
# Usage:
#   ./scripts/deploy-railway.sh                  # full deploy
#   ./scripts/deploy-railway.sh --env-only       # push env vars, skip deploy
#   ./scripts/deploy-railway.sh --check          # report what would change
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
ENV_FILE="$BACKEND/.env"

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

MODE="deploy"
for arg in "$@"; do
  case "$arg" in
    --env-only) MODE="env" ;;
    --check)    MODE="check" ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *) fail "Unknown flag: $arg"; exit 2 ;;
  esac
done

# ────── prereqs ──────
header "Checking prereqs"
command -v railway >/dev/null || {
  fail "Railway CLI not installed."
  echo "Install:  brew install railway   (or:  npm i -g @railway/cli)"
  echo "Then:     cd backend && railway login && railway link"
  exit 1
}
ok "railway CLI: $(railway --version 2>&1 | head -1)"

if [[ ! -f "$ENV_FILE" ]]; then
  fail "backend/.env missing. Run ./bootstrap.sh first."
  exit 1
fi
ok "backend/.env found"

# Confirm we're linked to a project
if ! (cd "$BACKEND" && railway status >/dev/null 2>&1); then
  warn "No Railway project linked in backend/."
  echo "Run:  cd backend && railway link"
  echo "(or:  railway init   if this is a brand-new project)"
  exit 1
fi
ok "Linked to Railway project"

# ────── read non-empty .env keys ──────
header "Reading variables from backend/.env"
declare -a ENV_KEYS=()
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  [[ -z "$value" ]] && continue
  ENV_KEYS+=("$key")
done < "$ENV_FILE"
ok "${#ENV_KEYS[@]} variable(s) ready to push"

if [[ "$MODE" == "check" ]]; then
  for key in "${ENV_KEYS[@]}"; do
    printf "  ${DIM}·${RESET} %s\n" "$key"
  done
  exit 0
fi

# ────── push env vars ──────
header "Pushing environment variables to Railway"
for key in "${ENV_KEYS[@]}"; do
  value=$(grep "^${key}=" "$ENV_FILE" | head -1 | cut -d'=' -f2-)
  # Skip dev-only knobs we don't want in production
  case "$key" in
    PORT|NODE_ENV) continue ;;
  esac
  if (cd "$BACKEND" && railway variables --set "${key}=${value}" >/dev/null 2>&1); then
    printf "  ${GREEN}↑${RESET} %s\n" "$key"
  else
    printf "  ${RED}✗${RESET} %s (push failed)\n" "$key"
  fi
done
# Force production mode in the deployed environment
(cd "$BACKEND" && railway variables --set "NODE_ENV=production" >/dev/null 2>&1) && \
  printf "  ${GREEN}↑${RESET} NODE_ENV=production\n"

if [[ "$MODE" == "env" ]]; then
  ok "env vars synced. Skipping deploy as requested."
  exit 0
fi

# ────── deploy ──────
header "Building + deploying"
(cd "$BACKEND" && railway up --detach) || { fail "railway up failed"; exit 1; }

cat <<EOF

${GREEN}${BOLD}✓ Deploy queued.${RESET}

  ${CYAN}Watch the build:${RESET}  cd backend && railway logs
  ${CYAN}Get the URL:${RESET}      cd backend && railway domain
  ${CYAN}Verify health:${RESET}    curl \$URL/healthz

When the URL is live, open Athen → You tab → AI backend → paste it → Save & test.
EOF
