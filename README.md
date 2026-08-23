# QuotaGlance

QuotaGlance is a local-first iPhone and Apple Watch utility for viewing the remaining Codex and Claude Code subscription windows. The repository contains:

- an iOS 18+ SwiftUI app;
- a watchOS 11+ SwiftUI companion app;
- an iPhone WidgetKit extension;
- a watchOS WidgetKit complication with circular, rectangular, and inline families;
- a shared `QuotaGlanceCore` Swift package;
- Swift Testing and XCTest coverage for quota mapping and provider schemas.

## Current verification boundary

The shared core builds and its tests pass on Swift 6.3 for Windows. The Apple-platform targets were created and syntax-checked, but this repository was initialized on Windows, where Xcode, iOS Simulator, watchOS Simulator, Widget previews, signing, and real OAuth browser flows are unavailable. Do not treat the Apple targets or provider login as runtime-verified until the macOS checklist below has passed.

The Provider APIs are also a compatibility risk: both usage paths are used by the vendors' own clients but are not documented as stable third-party iOS APIs. See [Provider compatibility](Docs/ProviderCompatibility.md) before distributing the app.

## Data flow

```text
Provider OAuth + Usage API (iPhone only)
                    |
                    v
             UsageSnapshot
              /          \
 App Group cache        WatchConnectivity
       |                       |
       v                       v
 iPhone Widget          Watch snapshot cache
                              |
                              v
                    watchOS complication
```

OAuth credentials are encoded only into a `kSecClassGenericPassword` Keychain item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The App Group, WidgetKit extensions, WatchConnectivity payload, and Watch app only handle `SnapshotEnvelope`, whose fields are provider, remaining-window inputs, reset dates, and update dates.

## Open in Xcode

1. Open `QuotaGlance.xcodeproj` in Xcode 16 or later.
2. Assign a development team to the four application/extension targets.
3. Register or replace the bundle identifiers and App Groups if `com.songlabs.QuotaGlance` is not available to the team.
4. Confirm these App Groups exist in the developer account:
   - `group.com.songlabs.QuotaGlance` for the iPhone app and iPhone widget;
   - `group.com.songlabs.QuotaGlance.watch` for the Watch app and watch complication.
5. Select the shared `QuotaGlance` scheme and build an iOS 18 simulator destination. The main app embeds both the iPhone widget and the Watch app; the Watch app embeds the complication extension.

Suggested macOS validation commands:

```bash
swift test
xcodebuild -project QuotaGlance.xcodeproj -scheme QuotaGlance \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build test
xcodebuild -project QuotaGlance.xcodeproj -target 'QuotaGlance Watch App' \
  -destination 'generic/platform=watchOS Simulator' build
xcodebuild -project QuotaGlance.xcodeproj -target QuotaGlanceWatchWidget \
  -destination 'generic/platform=watchOS Simulator' build
```

Then validate both provider logins with test accounts, background/foreground refresh, pull-to-refresh, offline cached display, WatchConnectivity delivery, every widget family, and a paired physical iPhone/Watch. OAuth loopback callbacks in particular need a real-device check.

## UX behavior

- Rings, percentages, and progress bars always represent **remaining**, calculated as `clamp(100 - used, 0...100)`.
- A missing window is `—`; it never becomes `0%`.
- Refresh errors preserve the most recent successful snapshot and add an explicit error message.
- Snapshots older than 15 minutes are visibly labeled cached/stale.
- Codex and Claude can be connected independently.
- The Watch app cannot log in and never receives provider credentials.

## Repository layout

```text
Sources/QuotaGlanceCore/       shared models, decoder boundary, formatting
QuotaGlanceApp/                iPhone app, OAuth, Keychain, cache, Watch sync
QuotaGlanceWatch/              watch-first dashboard and connectivity receiver
QuotaGlanceWidget/             iPhone widget
QuotaGlanceWatchWidget/        circular, rectangular, and inline complications
Tests/QuotaGlanceCoreTests/    cross-platform Swift Testing tests and fixtures
QuotaGlanceTests/              Xcode XCTest target
Docs/                          Provider research and validation boundaries
```

QuotaGlance has no backend, analytics, third-party runtime dependency, account system, usage history, subscription, or inference UI.
