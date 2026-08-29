# QuotaGlance

## App overview

QuotaGlance is a local-first SwiftUI app for checking the remaining usage windows of supported AI services. The iOS app signs in to providers, retrieves 5-hour and Weekly quota data, shows the last successful update time, and shares non-sensitive snapshots with WidgetKit and Apple Watch.

The current product includes:

- Codex and Claude account connections;
- 5H and Weekly remaining-usage views on iPhone and iPad;
- multiple saved provider accounts, with entitlement-based access;
- iPhone and iPad small and medium widgets;
- an Apple Watch app plus circular, rectangular, and inline complications;
- foreground automatic refresh, iOS background-refresh requests, and separate manual refresh actions;
- English, Japanese, Korean, Simplified Chinese, and Traditional Chinese UI.

QuotaGlance has no backend, analytics, usage-history database, provider inference UI, or third-party runtime dependency. Provider credentials remain in the iOS app's Keychain.

## Supported platforms

| Target | Current implementation |
| --- | --- |
| iPhone / iPad App (`QuotaGlance`) | SwiftUI, iOS 18.0+ |
| iPhone / iPad Widget (`QuotaGlanceWidget`) | WidgetKit `.systemSmall` and `.systemMedium` families |
| Apple Watch App (`QuotaGlance Watch App`) | SwiftUI, watchOS 11.0+ |
| Apple Watch complication (`QuotaGlanceWatchWidget`) | WidgetKit `.accessoryCircular`, `.accessoryRectangular`, and `.accessoryInline` families |
| Tests (`QuotaGlanceTests`, `QuotaGlanceCoreTests`) | Xcode XCTest plus cross-platform Swift Testing coverage |

The iOS app target embeds the iPhone / iPad Widget and Watch app. The Watch app embeds the complication extension.

## Supported services and accounts

| Service | Login and usage implementation | Account identity used by the UI |
| --- | --- | --- |
| Codex | OpenAI browser OAuth with PKCE and a loopback callback; the iOS app retrieves Codex usage data | Readable OAuth/JWT name, then email |
| Claude | Claude browser OAuth with PKCE and a loopback callback; the iOS app retrieves Claude usage data | OAuth account name, then `email_address` |

Only `codex` and `claude` exist in the current `AIProvider` model and `AppEnvironment` provider registry. Both provider decoders map the returned 5H/session and Weekly windows into the shared `UsageSnapshot` model.

An account's display name follows this order:

1. a custom name entered in Settings;
2. the provider identity label, with the domain removed when it is an email address;
3. the localized `Account N` fallback.

Pro and an active Trial retain and expose multiple accounts. Free exposes only the first saved account; additional saved accounts are not deleted when access falls back to Free.

The provider OAuth flows and usage endpoints are compatibility-sensitive because they are not documented as stable third-party iOS APIs. OpenAI and Anthropic have not supplied written authorization for QuotaGlance, and QuotaGlance does not claim official provider support. Provider behavior or policy may change or restrict these integrations. This is a known compatibility and provider-policy risk, not a current App Store submission blocker; see [Provider compatibility](Docs/ProviderCompatibility.md).

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
| Automatic data refresh | 4 hours fixed | Off / 15 min / 30 min / 1 hour / 2 hours / 4 hours |

An active 7-day Trial has the same feature access as Pro. In Free, the iPhone / iPad Widget shows an Upgrade prompt instead of quota data, while the Watch receives only the first entitled account, the 5H display limit, and no Weekly rows. Trial and Pro can select up to two Apple Watch display accounts in the app's Settings and choose the Widget/Watch quota window.

The Apple Watch display-account setting is the only account-selection source for the Watch app and complications. The selected accounts have a persistent `1` / `2` display order: removing account `1` promotes the previous account `2`, and the next selected account is appended as `2`. Complications do not expose separate Account or Limit choices in Watch-face editing. The single-account circular complication always uses account `1`. The rectangular and inline complications can use accounts `1` and `2` in that order and safely fall back to their existing one-account presentation when account `2` is absent. Free applies its runtime rule of the first saved account and 5H without deleting the stored Trial/Pro selection or order; restoring Trial or Pro access restores that saved selection.

## Data refresh

Automatic refresh combines a foreground scheduler, `BGAppRefreshTask`, and a per-account data-age safety check. All automatic paths reuse `DashboardStore` and the existing snapshot-publication pipeline; they do not duplicate provider networking.

### Free

- The effective automatic refresh interval is fixed at **4 hours**.
- Settings displays `4 Hours` in one disabled Picker. Free cannot turn automatic refresh off.
- A previously stored Pro interval is left intact but is not used while access is Free.

### Trial and Pro

- The effective automatic refresh interval is the user's stored setting.
- One Picker offers `Off`, `15 Minutes`, `30 Minutes`, `1 Hour`, `2 Hours`, and `4 Hours`.
- `Off` disables foreground and background automatic refresh without disabling manual refresh.
- If the user returns from Free to Trial or Pro, the previously stored interval becomes effective again.

### Default and persistence

The initial stored and effective interval is **4 hours**. Trial and Pro unlock the Picker without silently changing that choice. Free also fixes the Widget/Watch quota display to 5H and the Watch account display to the first saved account; stored Pro choices remain intact and become effective again when Trial or Pro access returns.

The first v2 preference read migrates the legacy minute/hour pair to the nearest new option that is not shorter: `0` becomes Off; `1...15` minutes becomes 15 minutes; `16...30` becomes 30 minutes; `31...60` becomes 1 hour; `61...120` becomes 2 hours; and anything longer becomes 4 hours. Legacy hours map as `0` → Off, `1` → 1 hour, `2` → 2 hours, and `3+` → 4 hours. Once the v2 value exists, it takes precedence and access-level changes never rewrite it.

### Foreground scheduling

While the app scene is active, the foreground scheduler uses each entitled account's last successful `UsageSnapshot.updatedAt` to schedule the remaining time until it is eligible. Returning to the foreground retains the startup/active data-age check: stale accounts refresh immediately, while fresh accounts keep their remaining delay. Leaving the active scene stops the foreground timer, and changing the effective interval reschedules it immediately. Per-account refresh state prevents overlapping Provider requests.

### Background scheduling

The iOS app registers `com.songlabs.QuotaGlance.refresh` and schedules a `BGAppRefreshTaskRequest` when it enters the background. The effective interval sets `earliestBeginDate`; it is only the earliest time iOS may run the request. Actual background execution is controlled by iOS and may occur later than the selected interval, or not occur when system Background App Refresh is unavailable or disabled.

When iOS launches the task, QuotaGlance schedules the next request, refreshes eligible accounts through `DashboardStore`, publishes the same non-credential `SnapshotEnvelope` to the App Group and WatchConnectivity, reloads Widget timelines, and reports completion. Expiration cancels the in-flight Swift task and reports failure. Selecting Off as Trial or Pro cancels the pending request and prevents new automatic requests; Free always remains effective at 4 hours.

QuotaGlance does not promise exact background timing, use silent push or remote notifications, or operate a backend for scheduling.

### Manual refresh

Manual refresh is separate from automatic refresh and is not rate-gated by the configured interval:

- iOS app pull-to-refresh forces a refresh check;
- each iOS app account card can refresh directly;
- Apple Watch's Refresh Data action requests a refresh from the iPhone.

These actions remain available to Free users for their entitled account. A successful refresh replaces the snapshot and update timestamp; an error preserves the most recent successful snapshot.

## Usage presentation

- Percentages, rings, and progress bars represent **remaining** quota: `clamp(100 - used, 0...100)`.
- A provider window that is absent is displayed as `—`, not as `0%`.
- The iPhone and iPad dashboard shows the most recent successful snapshot update once in its header summary, while Watch surfaces show the update time for their displayed snapshot; snapshots older than 15 minutes receive the cached/stale treatment.
- Refresh failures keep the previous successful quota data and add an error state instead of replacing it with empty data.

Settings keeps the existing controls grouped by purpose: Pro access, General, Refresh, provider-specific Accounts, Display, Apple Watch, and About.

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

Settings presents Upgrade inside its own navigation flow for Free and Trial membership rows and Pro-only actions. The Lifetime Pro status row is informational and closing Settings cannot leave a deferred Dashboard upgrade sheet behind.

## Architecture and data flow

```text
Codex / Claude OAuth + Usage API (iOS app only)
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
     iPhone / iPad Widget          Watch snapshot cache
                                              |
                                              v
                                  Watch app + complication
```

OAuth credentials are encoded only into `kSecClassGenericPassword` Keychain items with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The App Group cache, Widget, WatchConnectivity payload, Watch cache, and complications handle `SnapshotEnvelope` data: provider/account display metadata, quota windows, reset dates, update dates, selected Watch accounts, display limit, and access level. They do not receive OAuth credentials.

## Privacy and Terms

QuotaGlance is an independent application and is not affiliated with or endorsed by OpenAI or Anthropic. Provider credentials remain in the iPhone or iPad Keychain and are used directly with the selected provider; they are not sent to WidgetKit, Apple Watch, or a QuotaGlance-owned backend. The app contains no advertising, analytics, or tracking SDKs.

Provider quota and reset values depend on compatibility-sensitive third-party services. Values may be delayed, unavailable, incomplete, or changed by the provider, and QuotaGlance does not create a missing reset time. Widget and complication refresh timing is controlled by Apple platforms and is not guaranteed to occur at an exact interval.

- [Website](https://songlabs.github.io/QuotaGlance/)
- [Privacy Policy](https://songlabs.github.io/QuotaGlance/privacy/)
- [Terms of Use](https://songlabs.github.io/QuotaGlance/terms/)
- [Support](https://songlabs.github.io/QuotaGlance/support/)
- Support email: [songlabs.dev@gmail.com](mailto:songlabs.dev@gmail.com)

## App Review Demo Mode

QuotaGlance includes an App Store Review-only demonstration mode so reviewers can inspect the supported access levels without signing in to a private Codex or Claude account. In Settings, tap the Version row seven times, open **App Review Demo**, enable **Demo Mode**, and select Free, Trial, or Pro. Turn Demo Mode off from the same screen to restore the dashboard and shared snapshot that were present before the demo; the demo also turns off when the app is relaunched.

Demo Mode reuses the existing screenshot/preview sample models, runs in Release builds, and is entered entirely through the app UI. It uses fixed local Codex and Claude sample accounts and quota values. It does not call provider APIs, start OAuth, read or write provider credentials, change the account registry, modify StoreKit transactions or the real entitlement, or overwrite the user's refresh, display-limit, default-provider, and Watch-account preferences. Purchase and Restore actions are disabled while Demo Mode is active.

The selected Demo access level is applied through the same Free/Trial/Pro presentation policy used by production state:

- Free shows the first account and 5H data on iPhone and Watch, uses the fixed four-hour automatic-refresh policy, and publishes the Widget Upgrade state.
- Trial and Pro expose all sample accounts on iPhone, 5H and Weekly data, configurable refresh/display choices in the isolated Demo context, full Widget data, and up to two ordered Watch accounts.

The iPhone publishes a clearly marked, non-credential Demo `SnapshotEnvelope` through the existing App Group and WatchConnectivity paths. The Widget reads that envelope directly; the Watch app and circular, rectangular, and inline complications read the same Watch cache. Keep the paired iPhone and Apple Watch available when enabling or changing Demo Mode so the latest application context can be delivered. Manual refresh in Demo Mode only reloads the local sample snapshots.

## Current verification boundary

The shared `QuotaGlanceCore` package can be built and tested cross-platform. StoreKit entitlement initialization gates the first shared snapshot publication. Published Trial snapshots include the verified expiry date, allowing the Widget, Watch app, and complication to fail back to Free independently; all Watch surfaces derive their accounts from the same at-most-two-account selection. The `iOS CI` workflow is configured to run Xcode tests and an unsigned Release simulator build on macOS. The manually triggered TestFlight workflow archives, verifies, signs, and uploads the iOS app together with its iPhone / iPad Widget, Watch app, and Watch complication.

The manually triggered `Simulator Screenshot` workflow uses Debug-only launch arguments and synthetic preview data to capture a submission-ready package: five 6.9-inch iPhone screenshots, five native 13-inch iPad screenshots, three Apple Watch Series 11 screenshots, and separate Trial and Lifetime Pro IAP review screenshots. It converts native Simulator output to non-alpha JPEG, validates the exact App Store inventory and accepted pixel dimensions, and keeps optional Trial/Lifetime state QA captures in a separate artifact. These launch arguments are screenshot infrastructure, not a production feature; Release builds do not activate the preview environment. Widget and complication layouts have Xcode previews, but automated App Store screenshots for Widgets and complications are not claimed because `simctl` does not provide a stable headless path to install each family onto the iPhone Home Screen or an Apple Watch face and render it for visual acceptance.

Core tests and static parsing do not prove real OAuth, provider network traffic, StoreKit/App Store Connect configuration, Settings interaction, Widget timelines, paired WatchConnectivity, physical-device layout, signing, archive, or TestFlight behavior. Those require the matching macOS, Simulator, App Store sandbox, or physical-device checks in [Validation](Docs/Validation.md).

## Open in Xcode

1. Open `QuotaGlance.xcodeproj` with Xcode 26.3 to match the current CI baseline.
2. Assign a development team to the four application/extension targets.
3. Register or replace the bundle identifiers and App Groups if the current identifiers are not available to the team.
4. Confirm these App Groups exist in the developer account:
   - `group.com.songlabs.QuotaGlance` for the iOS app and iPhone / iPad Widget;
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

Then validate both provider logins with test accounts, Trial/Pro/Free transitions, refresh-setting persistence and migration, foreground automatic scheduling, manual refresh, offline cached display, Background App Refresh system-list visibility and actual task execution, Widget updates, WatchConnectivity delivery, every Widget family, and a paired physical iPhone/Watch. OAuth loopback callbacks and real background scheduling in particular need device checks.

## Repository layout

```text
Sources/QuotaGlanceCore/       shared models, access policy, decoders, formatting
QuotaGlanceApp/                iPhone / iPad app, OAuth, Keychain, StoreKit, cache, Watch sync
QuotaGlanceWatch/              Watch dashboard, snapshot cache, connectivity receiver
QuotaGlanceWidget/             iPhone / iPad WidgetKit extension
QuotaGlanceWatchWidget/        circular, rectangular, and inline complications
SharedUI/                      shared dark theme and brand assets
Tests/QuotaGlanceCoreTests/    cross-platform Swift Testing tests and fixtures
QuotaGlanceTests/              Xcode XCTest target
Docs/                          purchase, provider, and validation documentation
```
