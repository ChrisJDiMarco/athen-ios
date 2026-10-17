# Athen Localization

Currently English-only. Spanish (and beyond) ships in v1.1.

## How localization will work

Athen uses native iOS String Catalog (`Localizable.xcstrings`) — Apple's
modern replacement for `Localizable.strings` files. Each user-facing string
becomes a key and Apple's tools auto-extract them.

## Top 50 strings to translate first

These are the highest-frequency user-facing strings in the app. Once translated,
~80% of the UI is Spanish-readable. Listed in priority order.

### Navigation
- "Home"
- "Vote"
- "Square"
- "Assistant"
- "You"

### Onboarding
- "Athen — your civic OS."
- "Where do you live?"
- "Find my reps"
- "Looking up…"
- "Set your ZIP"
- "Want a heads-up before your bookmarked items vote?"
- "Yes, remind me"
- "Open the app"

### Home
- "Quick actions"
- "Tell Athen"
- "Petitions"
- "Reps"
- "Get help"
- "Today in"
- "This afternoon in"
- "Tonight in"
- "Last refresh"
- "Active"
- "Urgent"
- "Help"
- "Updates on your filings"
- "Aligned"
- "Mismatch"
- "You're all caught up"
- "See all items"

### Brief
- "Athen brief"
- "AI brief"
- "Read this brief"
- "Listen"
- "Stop"
- "Generate AI brief"
- "Athen is thinking…"
- "Key facts"
- "Both sides"
- "Fiscal impact"
- "Explain it for…"

### Filings
- "Endorse"
- "Oppose"
- "Filing as ENDORSE"
- "Filing as OPPOSE"
- "Send"
- "Recorded in your history"
- "Saves to your history only"
- "Connect Gmail to send for real"

### Voter Hub
- "Vote"
- "Election Day"
- "Next election"
- "days to go"
- "Today"
- "Preview my ballot"
- "Where you vote"
- "Register to vote"
- "Rep scorecard"

### Common
- "Done"
- "Cancel"
- "Close"
- "Save"
- "Try again"
- "Refresh"

## How to add Spanish translations

1. In Xcode: File → New → String Catalog → name `Localizable`
2. In the catalog editor, click `+` to add `es` (Spanish)
3. For each key above, paste the Spanish translation
4. Xcode auto-resolves at runtime when the device language is Spanish

## How code will reference the strings

Replace hardcoded strings:
```swift
Text("Where do you live?")
```

With:
```swift
Text("onboarding.zip.prompt")
// In Localizable.xcstrings: "onboarding.zip.prompt" → "Where do you live?" (en), "¿Dónde vives?" (es)
```

Or use String(localized:) for inline strings:
```swift
Text(String(localized: "Where do you live?"))
```

The String Catalog auto-extracts the second form's English copy as the key.

## Beyond Spanish

After Spanish, top US immigrant languages by speaker count:
1. Chinese (Simplified) — `zh-Hans`
2. Tagalog — `tl`
3. Vietnamese — `vi`
4. Arabic — `ar`
5. Korean — `ko`

Each adds a column to the String Catalog. No code changes required.
