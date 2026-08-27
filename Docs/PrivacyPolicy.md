# QuotaGlance Privacy Policy

Effective date: August 27, 2026

QuotaGlance is a local-first application for displaying usage-quota information returned by services that a user chooses to connect. This policy explains the data handled by the current iPhone, iPad, WidgetKit, Apple Watch, and complication implementation.

## Independent product

QuotaGlance is an independent application. It is not affiliated with, endorsed by, or sponsored by OpenAI or Anthropic.

The names OpenAI, ChatGPT, Codex, Anthropic, Claude, and Claude Code are used only to identify third-party services that a user may choose to connect. QuotaGlance does not claim that either provider has approved its OAuth implementation, its use of provider data, or its distribution through the App Store.

## Data handled by QuotaGlance

### Provider credentials

When you connect an account, QuotaGlance handles an OAuth access token, refresh token, token expiration date, granted scopes, and, when supplied by the provider, a provider account identifier. The current app stores this credential as a generic-password item in the iPhone or iPad Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` accessibility. This setting makes the item available after the device has first been unlocked and marks it as specific to that device rather than migratable to another device through a backup.

QuotaGlance uses the credential directly from the iPhone or iPad when it communicates with the selected provider's authorization, token, and usage services. QuotaGlance does not send provider credentials to a QuotaGlance-owned server.

Provider credentials are not written to either QuotaGlance App Group, included in WidgetKit timelines, sent through WatchConnectivity, stored in the Apple Watch snapshot cache, or exposed to the Watch app or complications.

### Account and display information

The iPhone or iPad app keeps its account registry and settings in local app preferences. Depending on what the provider returns and what you enter, this can include:

- a locally generated account identifier and account order;
- the provider name;
- a provider-supplied identity label, which can be a name or email address; and
- an optional custom display name.

QuotaGlance uses this information to distinguish saved accounts and produce display metadata for the dashboard, widgets, Watch app, and complications. The shared snapshot contains a display name rather than the OAuth credential. When a provider identity is an email address and no custom name is set, the current display-name logic removes the domain before publishing that display name in a shared snapshot.

### Usage and refresh information

QuotaGlance processes the usage windows returned by the connected provider. Local snapshots can contain:

- the provider and locally generated account identifier;
- usage or remaining-quota percentages for the available 5-hour/session and Weekly windows;
- a provider-supplied reset date, when present; and
- the time of the last successful refresh.

A missing usage window or reset date remains unavailable. QuotaGlance does not create a reset date when the provider omits one.

### Preferences and access information

Local app preferences can include the selected language, automatic-refresh interval, selected provider or accounts, Widget/Watch display limit, and Apple Watch account selection.

The shared snapshot also contains the current Free, Trial, or Lifetime Pro access level and, for an active Trial, its expiration date. This lets widgets and Watch surfaces apply the correct feature access without receiving StoreKit payment details.

QuotaGlance also stores a single greatest-observed timestamp in a separate device-only Keychain item after a verified Trial transaction exists. This timestamp is used only to reduce device-clock rollback of the seven-day Trial. It does not contain payment-card data and does not create or restart a Trial.

## Where local data is stored and shared

| Location or transfer | Current data scope |
| --- | --- |
| iPhone or iPad Keychain | Provider OAuth credentials; separate Trial clock-protection timestamp |
| iPhone or iPad app preferences | Account registry and identity/custom-name metadata; language and refresh preferences |
| iPhone/iPad App Group | Non-credential `SnapshotEnvelope`, Widget selection, display limit, and Watch account selection |
| WatchConnectivity | Encoded non-credential `SnapshotEnvelope` and refresh request/result messages |
| Apple Watch App Group cache | Non-credential `SnapshotEnvelope` used by the Watch app and complications |
| WidgetKit and complications | Locally cached snapshot presentation; they do not perform provider OAuth or provider usage requests |

The shared `SnapshotEnvelope` includes quota windows, reset and update dates, account display metadata, locally generated account identifiers, Watch selection, display limit, access level, and an active Trial expiration date. It does not include access tokens, refresh tokens, provider account identifiers from the credential, granted OAuth scopes, or token expiration dates.

## QuotaGlance servers, analytics, advertising, and tracking

The current QuotaGlance implementation does not operate a QuotaGlance-owned backend. It does not include advertising, analytics, or tracking SDKs, and it does not maintain a remote usage-history database.

The Privacy Manifests for the app, iPhone/iPad widget, Watch app, and Watch complication declare that tracking is disabled and contain no collected-data types. They declare UserDefaults access for app functionality. These statements concern the current QuotaGlance code and do not describe or control the separate practices of OpenAI, Anthropic, or Apple.

## Third-party services

You choose whether to connect an OpenAI/ChatGPT/Codex account or an Anthropic/Claude account. The provider receives the OAuth and usage requests needed to authorize the connection, refresh credentials, and return quota data. Those requests and the provider's handling of your account and network information are governed by that provider's own policies and terms. QuotaGlance does not control those practices.

- [OpenAI policies and terms](https://openai.com/policies/)
- [Anthropic policies and terms](https://privacy.anthropic.com/en/collections/10672414-policies-terms-of-service)

Purchases and restores use Apple's StoreKit and App Store services. Apple processes payment, account, purchase, refund, and related App Store information under Apple's policies. QuotaGlance does not receive your payment-card details.

- [Apple Media Services terms](https://www.apple.com/legal/internet-services/)
- [App Store and Privacy](https://www.apple.com/legal/privacy/data/en/appstore/)

## Retention and deletion

QuotaGlance keeps local account information and the latest successful snapshots until they are replaced, the account is removed, the relevant app data is cleared, or the app is uninstalled, subject to the platform behavior described below.

When you remove a current account in QuotaGlance, the app deletes that account's account-scoped OAuth credential from the iPhone or iPad Keychain, removes the account from the local registry and current iPhone/iPad App Group snapshot, updates selections, and publishes a new non-credential snapshot for widgets and Apple Watch. WatchConnectivity and WidgetKit delivery are scheduled by Apple, so previously cached account information may remain visible on a Watch or widget until the updated snapshot or timeline is delivered. Removing an account from QuotaGlance does not itself revoke the provider-side authorization; use the provider's account controls if you also want to revoke access there.

The app contains a migration path for credentials created by an older, provider-only storage format. That migration intentionally retains the older Keychain item after copying it to account-scoped storage. The current account-removal path deletes the account-scoped item but does not target a retained legacy item. Users of a build that performed this migration should be aware that the older item may remain in Keychain.

Uninstalling the iPhone or iPad app normally removes its app-container and App Group preferences, while uninstalling the Watch app normally removes its Watch-local cache. Keychain items are managed separately by the operating system and may survive app deletion and a later reinstall. The `ThisDeviceOnly` setting prevents these items from migrating to another device through backup; it does not guarantee removal on uninstall. For this reason, remove connected accounts in QuotaGlance before uninstalling when possible, and use provider controls to revoke authorization if needed.

## Security

QuotaGlance relies on Apple's Keychain, app-container, App Group, and WatchConnectivity protections. Provider network requests use HTTPS; the OAuth flow uses a localhost loopback callback on the same device. No storage or transmission method can be guaranteed to be completely secure, and third-party account security remains subject to the provider and your own account practices.

## Changes to this policy

This policy may be updated when QuotaGlance's implementation, supported providers, StoreKit products, or legal obligations change. The effective date above should be updated when a revised policy is published.

## Contact

For privacy questions or requests, contact QuotaGlance through the public [Support and issue tracker](https://github.com/songlabs/QuotaGlance/issues).

This policy is based on the repository implementation as of its effective date. Legal review is recommended when required for the publisher's jurisdiction and distribution.
