#!/usr/bin/env bash
# Take App Store screenshots on each required simulator size.
#
# What this does:
#   1. Builds the iOS app (Debug, no signing)
#   2. For each required device size, boots the simulator + installs the app
#   3. Pauses so you can navigate to a tab and capture
#   4. Saves each screenshot to docs/screenshots/{size}/{tab}.png
#
# Required App Store sizes (as of Apple's current rules):
#   - 6.9": iPhone 16 Pro Max (1320 × 2868)
#   - 6.1": iPhone 16 (1206 × 2622)
#   - iPad 13" (optional but recommended): iPad Pro 13-inch (2064 × 2752)
#
# Usage:
#   ./scripts/screenshots.sh                 # interactive — walks you tab by tab
#   ./scripts/screenshots.sh --device "iPhone 16 Pro Max"   # one device
#   ./scripts/screenshots.sh --list          # list available simulators
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ROOT="$ROOT/docs/screenshots"
BUNDLE_ID="com.chrisdimarco.Athen"
APP_PATH=""

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
prompt() { printf "${BOLD}${CYAN}? %s${RESET} " "$1"; }

# Devices App Store requires (or strongly recommends)
DEVICES=(
  "iPhone 16 Pro Max"
  "iPhone 16"
)

# Tabs to capture per device — names match the tab bar labels
TABS=(
  "01-home"
  "02-brief"
  "03-brief-detail"
  "04-square"
  "05-assistant"
  "06-you"
)

# ────── flags ──────
MODE="interactive"
ONLY_DEVICE=""
for arg in "$@"; do
  case "$arg" in
    --device)   shift; ONLY_DEVICE="$1"; shift || true ;;
    --list)     MODE="list" ;;
    -h|--help)  sed -n '2,18p' "$0"; exit 0 ;;
    *) ;;
  esac
done

if [[ "$MODE" == "list" ]]; then
  xcrun simctl list devices available | grep -E 'iPhone|iPad'
  exit 0
fi

# ────── build ──────
header "Building app (Debug, no signing)"
cd "$ROOT"
xcodebuild \
  -project CivicOS.xcodeproj \
  -scheme CivicOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  -derivedDataPath build/screenshots \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5

APP_PATH=$(find "$ROOT/build/screenshots/Build/Products" -name "CivicOS.app" -type d | head -1)
if [[ -z "$APP_PATH" ]]; then
  fail "Could not locate built CivicOS.app"
  exit 1
fi
ok "Built: $APP_PATH"

# ────── per-device loop ──────
for device in "${DEVICES[@]}"; do
  [[ -n "$ONLY_DEVICE" && "$ONLY_DEVICE" != "$device" ]] && continue

  header "Device: $device"
  DEVICE_DIR="$OUT_ROOT/${device// /-}"
  mkdir -p "$DEVICE_DIR"

  # Find or create a simulator with this device type
  UDID=$(xcrun simctl list devices available | grep -E "^\s*${device} \(" | head -1 | grep -oE '[A-F0-9-]{36}')
  if [[ -z "$UDID" ]]; then
    fail "No simulator found for $device. Create one in Xcode → Window → Devices and Simulators."
    continue
  fi
  ok "UDID: $UDID"

  # Boot if needed
  state=$(xcrun simctl list devices | grep "$UDID" | grep -oE '\([A-Za-z]+\)' | head -1 | tr -d '()')
  if [[ "$state" != "Booted" ]]; then
    echo "Booting…"
    xcrun simctl boot "$UDID"
    sleep 5
  fi
  open -a Simulator
  sleep 2

  # Reinstall fresh
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP_PATH"
  xcrun simctl launch "$UDID" "$BUNDLE_ID"
  sleep 3

  echo ""
  echo "${YELLOW}→ Set up the simulator the way you want screenshots to look:${RESET}"
  echo "    - Complete onboarding (or set ZIP via You tab)"
  echo "    - Navigate to the tab you want to capture"
  echo ""
  echo "For each tab below, press ENTER when the screen is ready."
  echo ""

  for tab in "${TABS[@]}"; do
    prompt "$tab — press ENTER when ready (or 's' to skip, 'q' to next device):"
    read -r answer
    case "$answer" in
      s|S) echo "  skipped"; continue ;;
      q|Q) break ;;
    esac
    out="$DEVICE_DIR/${tab}.png"
    xcrun simctl io "$UDID" screenshot "$out"
    ok "Saved $out"
  done
done

header "Done"
echo "Screenshots saved under: $OUT_ROOT"
echo ""
echo "Next:"
echo "  - Review each one"
echo "  - Crop / annotate in Figma or Sketch if you want overlays"
echo "  - Upload to App Store Connect under each device size"
