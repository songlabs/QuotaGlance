# QuotaGlance Terms of Use

Effective date: August 27, 2026

These Terms of Use govern your use of the QuotaGlance application. By using QuotaGlance, you agree to these Terms. If you do not agree, do not use the application.

## Independent product

QuotaGlance is an independent application. It is not affiliated with, endorsed by, or sponsored by OpenAI or Anthropic.

OpenAI, ChatGPT, Codex, Anthropic, Claude, Claude Code, Apple, App Store, and related names and marks belong to their respective owners. QuotaGlance uses those names only to identify compatible third-party services and platform functionality. No statement in the application or its documentation represents that a provider has approved QuotaGlance's OAuth implementation, access to provider data, or App Store distribution.

## Your accounts and provider terms

You connect and use your own OpenAI/ChatGPT/Codex or Anthropic/Claude account. You are responsible for maintaining the security of that account and for complying with all terms, usage policies, account restrictions, and eligibility requirements imposed by the connected provider.

QuotaGlance does not act for a provider and cannot determine or guarantee that your account, plan, region, or intended use is eligible for a particular provider feature or endpoint. You should review the current [OpenAI policies](https://openai.com/policies/) or [Anthropic policies](https://privacy.anthropic.com/en/collections/10672414-policies-terms-of-service), as applicable.

## Provider availability and compatibility

QuotaGlance depends on third-party OAuth, token, and usage services. A provider can change its API, OAuth flow, client requirements, scopes, response fields, quota rules, account eligibility, rate limits, or availability at any time. A provider may return incomplete data, reject or revoke a credential, suspend an endpoint, or prevent QuotaGlance from connecting.

The provider usage endpoints used by the current implementation are compatibility-sensitive and are not represented by QuotaGlance as stable, provider-supported third-party iOS APIs. QuotaGlance does not guarantee that any provider connection or feature will remain available.

## Quota and reset information

Quota and reset information is based on data returned by the connected provider. QuotaGlance converts a returned used percentage into a remaining percentage and displays only the windows that the provider response supplies.

Provider data can be delayed, incomplete, inconsistent, or different from information shown in a provider's own application or website. If a provider does not return a quota window or reset time, QuotaGlance may display that value as unavailable. QuotaGlance does not fabricate missing reset times or promise that displayed values will always match a provider's own presentation.

QuotaGlance is an informational display. It does not grant quota, change a plan, reserve capacity, or control a provider's decisions about limits, throttling, suspension, termination, billing, or account access. You should verify important usage information with the provider before relying on it.

## Refresh behavior

Automatic refresh is a minimum data-age check performed when the iPhone or iPad app receives execution time, such as when the dashboard starts or the app becomes active. It is not a continuous background timer or a guarantee that a provider request will occur at a particular minute.

Widget and complication timeline scheduling is controlled by iOS, iPadOS, watchOS, and WidgetKit. Watch data delivery also depends on Apple's WatchConnectivity scheduling and device conditions. A requested timeline interval, manual refresh, or Watch refresh request does not guarantee an immediate provider response or an exact update time. Cached data may continue to appear after a network, authorization, provider, or delivery failure.

## Trial and Lifetime Pro

QuotaGlance uses StoreKit 2 and is not a subscription.

### Seven-day Trial

`com.songlabs.QuotaGlance.pro.trial7d` is designed as a free Non-Consumable App Store product that you must choose to obtain. A verified transaction's purchase date starts seven days of Trial access. The Trial does not automatically charge you, renew, purchase Lifetime Pro, or convert into a paid product. When it expires, the app returns to its Free feature set unless Lifetime Pro is active.

Because the Trial is a Non-Consumable, its prior transaction can prevent the same Apple ID from obtaining it again. Deleting or reinstalling QuotaGlance does not create a new Trial.

### Lifetime Pro

`com.songlabs.QuotaGlance.pro.lifetime` is designed as a Non-Consumable, one-time purchase. It is Lifetime Pro access for the product under the applicable App Store rules, not a recurring subscription.

### Restore, billing, and refunds

Restore Purchases calls `AppStore.sync()` and rebuilds access from verified current StoreKit entitlements. Apple processes App Store billing, payment methods, purchase records, revocations, and refunds under the [Apple Media Services terms](https://www.apple.com/legal/internet-services/) and the rules applicable in your storefront. Product availability and the localized Lifetime price are supplied through the App Store and may vary by country or region.

QuotaGlance cannot guarantee approval of a purchase, restore, or refund. Statutory rights and any rights provided by Apple or applicable consumer-protection law are not limited by these Terms.

## Acceptable use

You may use QuotaGlance only in compliance with applicable law, these Terms, the applicable provider's terms and policies, and Apple's platform rules. You must not use the application to bypass provider restrictions, interfere with provider or Apple services, gain unauthorized access to another person's account, or misrepresent QuotaGlance as an official provider product.

## Privacy

The [QuotaGlance Privacy Policy](PrivacyPolicy.md) explains how the current application handles credentials, account display information, usage snapshots, local caches, Watch/Widget data, and StoreKit-related state.

## Service changes and discontinuation

QuotaGlance may need to change, suspend, or remove a provider integration or application feature when providers, Apple platforms, laws, security requirements, or technical conditions change. Where reasonably possible, material changes should be described in updated application documentation or release information.

## Availability, informational use, and responsibility

QuotaGlance is provided on an availability basis. To the extent permitted by applicable law, no promise is made that it will be uninterrupted, error-free, compatible with every account, or able to retrieve complete and current third-party data. You remain responsible for your provider accounts and for decisions based on displayed quota information.

OpenAI, Anthropic, and Apple are responsible for their own services and decisions. QuotaGlance does not control provider limits, account actions, data retention, outages, or policy changes. Nothing in these Terms excludes or limits rights or responsibilities that cannot lawfully be excluded or limited, including mandatory consumer protections.

These Terms intentionally do not select a governing law, court, arbitration forum, indemnification regime, or fixed liability cap. Any provisions legally required for the publisher's jurisdiction and distribution should be settled through qualified legal review.

## Changes to these Terms

These Terms may be updated when QuotaGlance's implementation, supported providers, StoreKit products, or legal obligations change. The effective date above should be updated when revised Terms are published. If a change requires notice or consent under applicable law, the publisher should provide it through an appropriate channel.

## Contact

For questions about these Terms, contact QuotaGlance through the public [Support and issue tracker](https://github.com/songlabs/QuotaGlance/issues).

These Terms are based on the repository implementation as of their effective date. Legal review is recommended when required for the publisher's jurisdiction and distribution.
