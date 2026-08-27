# Validation record

## Executed in the creation environment

Environment:

- Windows 10.0.26200
- PowerShell 7.6.5
- Swift 6.3.0
- no `xcodebuild`

Executed checks:

- `swift test` for `QuotaGlanceCore`
- Swift frontend parse over every committed `.swift` source
- XML parse over every `.plist`, `.entitlements`, `.xcprivacy`, workspace, and shared scheme file
- project-reference/static target membership checks
- credential-flow searches covering `UserDefaults`, App Group cache, WatchConnectivity, Widget sources, `print`, and logging calls
- final Git diff/status checks
- entitlement publication gating, Free/Trial/Pro transitions, cached Trial expiry,
  and shared Watch account-selection unit tests
- static routing tests for Free/Trial versus Lifetime Pro membership taps
- discrete automatic-refresh durations, Free/Trial/Pro effective values, downgrade
  preservation, legacy preference migration, retry-throttle, and schedule-date tests
- static `BGTaskScheduler` identifier, Background fetch mode, target capability, source
  membership, and five-language String Catalog checks

The exact final command results belong in the task handoff because this document may precede the final commit.

## Not executable in this environment

- Xcode project loading and dependency resolution
- iOS/watchOS compilation or unit tests under Apple SDKs
- iPhone or Watch Simulator launch
- WidgetKit preview rendering
- iPhone/Watch paired WatchConnectivity test
- OAuth browser login for either provider from the iOS app
- real Claude usage response
- physical-device Keychain, loopback listener, and refresh testing
- Background App Refresh system-list visibility, system launch of `BGAppRefreshTask`,
  and post-background Widget/Watch delivery
- code signing, archive, TestFlight, or App Store review
