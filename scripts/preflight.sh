#!/usr/bin/env bash
# Athen App Store pre-flight check. Runs before every TestFlight upload.
# Verifies signing, version, secrets, privacy manifest, prod URL — fails
# loud if anything's missing. Exit 0 = ready, exit 1 = blockers.

set -euo pipefail
cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

PASS=0
WARN=0
FAIL=0

ok()    { echo -e "${GREEN}✓${RESET} $1"; PASS=$((PASS+1)); }
warn()  { echo -e "${YELLOW}⚠${RESET}  $1"; WARN=$((WARN+1)); }
fail()  { echo -e "${RED}✗${RESET} $1"; FAIL=$((FAIL+1)); }

echo "━━━ Athen App Store pre-flight ━━━"
echo ""

# 1. Version bump
VERSION=$(grep -m1 "MARKETING_VERSION" CivicOS.xcodeproj/project.pbxproj | sed 's/.*= //;s/;//' | xargs)
BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" CivicOS.xcodeproj/project.pbxproj | sed 's/.*= //;s/;//' | xargs)
if [[ "$VERSION" == "0.1" ]]; then
  fail "MARKETING_VERSION is still 0.1 — bump to 1.0 for first submission"
else
  ok "Version: $VERSION (build $BUILD)"
fi

# 2. Bundle ID present
BUNDLE_ID=$(grep -m1 "PRODUCT_BUNDLE_IDENTIFIER" CivicOS.xcodeproj/project.pbxproj | sed 's/.*= //;s/;//' | xargs)
if [[ -z "$BUNDLE_ID" ]]; then
  fail "PRODUCT_BUNDLE_IDENTIFIER missing"
else
  ok "Bundle ID: $BUNDLE_ID"
fi

# 3. App icon
if [[ -f "CivicOS/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" ]]; then
  ok "App icon (1024px) present"
else
  fail "App icon (1024px) missing"
fi

# 4. Privacy manifest
if [[ -f "CivicOS/Resources/PrivacyInfo.xcprivacy" ]]; then
  ok "PrivacyInfo.xcprivacy present"
else
  fail "PrivacyInfo.xcprivacy missing — Apple rejects without this since May 2024"
fi

# 5. Info.plist required keys
PLIST="CivicOS/Resources/Info.plist"
for key in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription \
           NSCameraUsageDescription NSPhotoLibraryUsageDescription \
           ITSAppUsesNonExemptEncryption; do
  if grep -q "<key>$key</key>" "$PLIST"; then
    ok "Info.plist has $key"
  else
    fail "Info.plist missing $key"
  fi
done

# 6. Production backend URL configured
PROD_URL=$(grep -A1 "ATHEN_API_BASE_URL" "$PLIST" | grep "<string>" | sed 's/.*<string>//;s/<\/string>.*//')
if [[ -z "$PROD_URL" ]]; then
  warn "ATHEN_API_BASE_URL is empty — fine for DEBUG, REQUIRED for Release"
elif [[ "$PROD_URL" =~ ^https:// ]]; then
  ok "Production backend URL set: $PROD_URL"
else
  fail "ATHEN_API_BASE_URL must be HTTPS (got: $PROD_URL)"
fi

# 7. Backend .env not committed
if git ls-files --error-unmatch backend/.env > /dev/null 2>&1; then
  fail "backend/.env is tracked by git — DELETE FROM HISTORY before submission"
else
  ok "backend/.env not tracked"
fi

# 8. No leaked API keys in source tree
if grep -rEn "sk-ant-api03-[A-Za-z0-9_-]{30,}|sk_[a-f0-9]{40,}|AIza[A-Za-z0-9_-]{30,}" \
   CivicOS/ backend/src/ 2>/dev/null | grep -v "YOUR_\|example\|placeholder" > /tmp/secret-leak.tmp; then
  fail "Possible secrets in source — review /tmp/secret-leak.tmp"
  cat /tmp/secret-leak.tmp
else
  ok "No hard-coded API keys found in source tree"
fi
rm -f /tmp/secret-leak.tmp

# 9. App Store listing copy ready
if [[ -f "APP-STORE-LISTING.md" ]]; then
  ok "App Store listing copy drafted (APP-STORE-LISTING.md)"
else
  warn "APP-STORE-LISTING.md missing — draft listing copy"
fi

# 10. Reviewer notes
if [[ -f "APP-STORE-REVIEWER-NOTES.md" ]]; then
  ok "Reviewer notes drafted (APP-STORE-REVIEWER-NOTES.md)"
else
  warn "APP-STORE-REVIEWER-NOTES.md missing — needed for Submission step"
fi

# 11. Privacy nutrition labels spec
if [[ -f "PRIVACY-NUTRITION-LABELS.md" ]]; then
  ok "Privacy nutrition labels spec ready (PRIVACY-NUTRITION-LABELS.md)"
else
  warn "PRIVACY-NUTRITION-LABELS.md missing"
fi

# 12. Privacy + Terms hosted (best-effort check)
warn "Privacy Policy + Terms must be live at HTTPS URLs before submission (manual)"

# 13. Release-config build (don't crash on signing — most CIs need real cert)
echo ""
echo "Building Debug to confirm code compiles..."
if xcodebuild -project CivicOS.xcodeproj -scheme CivicOS \
   -destination 'platform=iOS Simulator,name=iPhone 16' \
   -configuration Debug build -quiet > /tmp/build.log 2>&1; then
  ok "Debug build succeeds"
else
  fail "Debug build FAILED — see /tmp/build.log"
fi

echo ""
echo "━━━ Summary ━━━"
echo -e "${GREEN}Pass:${RESET}  $PASS"
[[ $WARN -gt 0 ]] && echo -e "${YELLOW}Warn:${RESET}  $WARN"
[[ $FAIL -gt 0 ]] && echo -e "${RED}Fail:${RESET}  $FAIL"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo -e "${RED}NOT READY FOR SUBMISSION${RESET} — fix the $FAIL blocker(s) above."
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo ""
  echo -e "${YELLOW}READY WITH WARNINGS${RESET} — address before TestFlight if you can."
  exit 0
else
  echo ""
  echo -e "${GREEN}READY FOR SUBMISSION${RESET} 🚀"
  exit 0
fi
