# QuotaGlance

## App overview

QuotaGlance is a local-first SwiftUI app for checking the remaining usage windows of supported AI services. The iPhone app signs in to providers, retrieves 5-hour and Weekly quota data, shows the last successful update time, and shares non-sensitive snapshots with WidgetKit and Apple Watch.

The current product includes:

- Codex and Claude account connections;
- 5H and Weekly remaining-usage views on iPhone;
- multiple saved provider accounts, with entitlement-based access;
- iPhone small and medium widgets;
- an Apple Watch app plus circular, rectangular, and inline complications;
- automatic refresh checks and separate manual refresh actions;
- English, Japanese, Korean, Simplified Chinese, and Traditional Chinese UI.

QuotaGlance has no backend, analytics, usage-history database, provider inference UI, or third-party runtime dependency. Provider credentials remain on the iPhone in Keychain.

## Supported platforms

| Target | Current implementation |
| --- | --- |
| iPhone app (`QuotaGlance`) | SwiftUI, iOS 18.0+; the Xcode target also declares the iPad device family |
| iPhone widget (`QuotaGlanceWidget`) | WidgetKit `.systemSmall` and `.systemMedium` families |
| Apple Watch app (`QuotaGlance Watch App`) | SwiftUI, watchOS 11.0+ |
| Apple Watch complication (`QuotaGlanceWatchWidget`) | WidgetKit `.accessoryCircular`, `.accessoryRectangular`, and `.accessoryInline` families |
| Tests (`QuotaGlanceTests`, `QuotaGlanceCoreTests`) | Xcode XCTest plus cross-platform Swift Testing coverage |

The iPhone app embeds the iPhone widget and Watch app. The Watch app embeds the complication extension.

## Supported services and accounts

| Service | Login and usage implementation | Account identity used by the UI |
| --- | --- | --- |
| Codex | OpenAI browser OAuth with PKCE and a loopback callback; the iPhone retrieves Codex usage data | Readable OAuth/JWT name, then email |
| Claude | Claude browser OAuth with PKCE and a loopback callback; the iPhone retrieves Claude usage data | OAuth account name, then `email_address` |

Only `codex` and `claude` exist in the current `AIProvider` model and `AppEnvironment` provider registry. Both provider decoders map the returned 5H/session and Weekly windows into the shared `UsageSnapshot` model.

An account's display name follows this order:

1. a custom name entered in Settings;
2. the provider identity label, with the domain removed when it is an email address;
3. the localized `Account N` fallback.

Pro and an active Trial retain and expose multiple accounts. Free exposes only the first saved account; additional saved accounts are not deleted when access falls back to Free.

The provider usage endpoints are compatibility-sensitive because they are not documented as stable third-party iOS APIs. See [Provider compatibility](Docs/ProviderCompatibility.md) before distribution.

## Free and Pro

The Upgrade screen and product policy use the same comparison:

| Feature | Free | Pro |
| --- | :---: | :---: |
| iPhone 5H | ✓ | ✓ |
| iPhone Weekly | — | ✓ |
| iPhone multiple accounts | — | ✓ |
| iPhone Widget | — | ✓ |
| Apple Watch 5H | ✓ | ✓ |
| Apple Watch Weekly | — | ✓ |
| Apple Watch multiple accounts | — | ✓ |
| Automatic data refresh | 60 min fixed | Customizable |

An active 7-day Trial has the same feature access as Pro. In Free, the iPhone widget shows an Upgrade prompt instead of quota data, while the Watch receives only the first entitled account, the 5H display limit, and no Weekly rows. Pro can select up to two Watch accounts and choose the Widget/Watch quota window.

## Data refresh

Automatic refresh is a minimum data-age check, not a guaranteed background schedule. The iPhone evaluates it when the dashboard first runs and when the app returns to the active scene phase. Each connected, entitled account is checked independently against its last successful `UsageSnapshot.updatedAt`; there is no parallel timer, `BGTaskScheduler`, silent-push, or background-fetch system.

### Free

- The effective automatic refresh interval is fixed at **60 minutes**.
- Settings displays `60` + `Minutes`, and both controls are disabled.
- A previously stored Pro interval is left intact but is not used while access is Free.

### Trial and Pro

- The effective automatic refresh interval is the user's stored setting.
- The existing Settings controls remain available with `Minutes` (`0...60`) and `Hours` (`0...23`) units. A previously stored larger minute value, such as 120, remains selected and effective until the user changes it.
- `0` keeps the selected unit and disables automatic refresh.
- If the user returns from Free to Trial or Pro, the previously stored interval becomes effective again.

### Default and persistence

The initial/fallback interval is **60 minutes**. It is used only when both refresh preference keys do not contain a complete valid saved setting. Loading the new default does not write over a valid existing value, and switching access levels does not rewrite the stored interval.

### Manual refresh

Manual refresh is separate from automatic refresh and is not rate-gated by the configured interval:

- iPhone pull-to-refresh forces a refresh check;
- each iPhone account card can refresh directly;
- Apple Watch's Refresh Data action requests a refresh from the iPhone.

These actions remain available to Free users for their entitled account. A successful refresh replaces the snapshot and update timestamp; an error preserves the most recent successful snapshot.

## Usage presentation

- Percentages, rings, and progress bars represent **remaining** quota: `clamp(100 - used, 0...100)`.
- A provider window that is absent is displayed as `—`, not as `0%`.
- The iPhone and Watch show the last successful update time; snapshots older than 15 minutes receive the cached/stale treatment.
- Refresh failures keep the previous successful quota data and add an error state instead of replacing it with empty data.

## Purchase and Trial

QuotaGlance uses StoreKit 2 and is not a subscription:

| Access | StoreKit behavior |
| --- | --- |
| Free | No purchase is required; one-account and 5H access remains after Trial expiry |
| 7-day Trial | Separate free non-consumable product `com.songlabs.QuotaGlance.pro.trial7d`; a verified transaction's original purchase date starts exactly seven days of Pro features |
| Pro | One-time Lifetime non-consumable product `com.songlabs.QuotaGlance.pro.lifetime` |
| Restore Purchases | Calls `AppStore.sync()` and rebuilds access from verified current entitlements |

The Trial is not an auto-renewing introductory subscription and creates no automatic charge or Pro purchase. A Trial transaction prevents the same Apple ID from starting it again after expiry; a Keychain record retains only the greatest observed time to mitigate clock rollback. StoreKit supplies the localized Lifetime price at runtime through `Product.displayPrice`.

The repository does not contain a local `.storekit` configuration file. Product type, availability, localization, and pricing therefore also require App Store Connect verification; the expected setup is documented in [Pro unlock and App Store Connect](Docs/ProUnlock.md).

## Localization

`Localizable.xcstrings` and the Xcode project currently support:

- English (`en`);
- Japanese (`ja`);
- Korean (`ko`);
- Simplified Chinese (`zh-Hans`);
- Traditional Chinese (`zh-Hant`).

The app can follow the system language or persist an explicit language choice. Upgrade, refresh-setting, Widget, Watch, and complication strings use the same String Catalog.

## Architecture and data flow

```text
Codex / Claude OAuth + Usage API (iPhone only)
                         |
                         v
                  DashboardStore
                         |
                         v
              UsageSnapshot / SnapshotEnvelope
                   /                       \
                  v                         v
      App Group UserDefaults            WatchConnectivity
                  |                         |
                  v                         v
         iPhone Widget              Watch snapshot cache
                                              |
                                              v
                                  Watch app + complication
```

OAuth credentials are encoded only into `kSecClassGenericPassword` Keychain items with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The App Group cache, Widget, WatchConnectivity payload, Watch cache, and complications handle `SnapshotEnvelope` data: provider/account display metadata, quota windows, reset dates, update dates, selected Watch accounts, display limit, and access level. They do not receive OAuth credentials.

## Current verification boundary

The shared `QuotaGlanceCore` package can be built and tested cross-platform. The `iOS CI` workflow is configured to run Xcode tests and an unsigned Release simulator build on macOS. The manually triggered TestFlight workflow archives, verifies, signs, and uploads the iPhone app together with its iPhone widget, Watch app, and Watch complication.

The manually triggered `Simulator Screenshot` workflow uses Debug-only launch arguments and synthetic preview data to capture required iPhone Dashboard, Settings, Upgrade (Trial available, Trial active, Trial expired, and Lifetime Pro), and Apple Watch Free/Pro scenarios. Each scenario is launched independently, every required PNG is checked for non-zero size, and the complete inventory is uploaded as `quota-glance-simulator-screenshots`. These launch arguments are screenshot infrastructure, not a production feature; Release builds do not activate the preview environment. Widget and complication layouts have Xcode previews, but the workflow does not claim automated Widget/Watch-face screenshots because `simctl` does not provide a stable headless path to install each family onto the iPhone Home Screen or an Apple Watch face and render it for visual acceptance.

Core tests and static parsing do not prove real OAuth, provider network traffic, StoreKit/App Store Connect configuration, Settings interaction, Widget timelines, paired WatchConnectivity, physical-device layout, signing, archive, or TestFlight behavior. Those require the matching macOS, Simulator, App Store sandbox, or physical-device checks in [Validation](Docs/Validation.md).

## Open in Xcode

1. Open `QuotaGlance.xcodeproj` with Xcode 26.3 to match the current CI baseline.
2. Assign a development team to the four application/extension targets.
3. Register or replace the bundle identifiers and App Groups if the current identifiers are not available to the team.
4. Confirm these App Groups exist in the developer account:
   - `group.com.songlabs.QuotaGlance` for the iPhone app and iPhone widget;
   - `group.com.songlabs.QuotaGlance.watch` for the Watch app and Watch complication.
5. Select the shared `QuotaGlance` scheme and build an iOS 18 simulator destination.

Suggested macOS validation commands:

```bash
swift test
xcodebuild -project QuotaGlance.xcodeproj -scheme QuotaGlance \
  -destination 'platform=iOS Simulator,name=iPhone 17' build test
xcodebuild -project QuotaGlance.xcodeproj -target 'QuotaGlance Watch App' \
  -destination 'generic/platform=watchOS Simulator' build
xcodebuild -project QuotaGlance.xcodeproj -target QuotaGlanceWatchWidget \
  -destination 'generic/platform=watchOS Simulator' build
```

Then validate both provider logins with test accounts, Trial/Pro/Free transitions, refresh-setting persistence, foreground automatic-refresh gates, manual refresh, offline cached display, WatchConnectivity delivery, every Widget family, and a paired physical iPhone/Watch. OAuth loopback callbacks in particular need a real-device check.

## Repository layout

```text
Sources/QuotaGlanceCore/       shared models, access policy, decoders, formatting
QuotaGlanceApp/                iPhone app, OAuth, Keychain, StoreKit, cache, Watch sync
QuotaGlanceWatch/              Watch dashboard, snapshot cache, connectivity receiver
QuotaGlanceWidget/             iPhone WidgetKit extension
QuotaGlanceWatchWidget/        circular, rectangular, and inline complications
SharedUI/                      shared dark theme and brand assets
Tests/QuotaGlanceCoreTests/    cross-platform Swift Testing tests and fixtures
QuotaGlanceTests/              Xcode XCTest target
Docs/                          purchase, provider, and validation documentation
```
