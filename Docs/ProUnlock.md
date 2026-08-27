# Pro unlock and App Store Connect

QuotaGlance uses StoreKit 2 with two **Non-Consumable** in-app purchases:

- Free 7-day Trial: `com.songlabs.QuotaGlance.pro.trial7d` (Price Tier 0), localized with a name such as “7-day Trial”.
- Lifetime Pro: `com.songlabs.QuotaGlance.pro.lifetime`.

The app is not a subscription and never charges automatically. It never embeds a
price or currency; the upgrade screen displays StoreKit's localized
`Product.displayPrice`.

## App Store Connect setup

1. Accept any pending Paid Apps agreement and complete Tax and Banking under
   Agreements, Tax, and Banking.
2. Create both products above with type **Non-Consumable**. Configure the Trial
   product as Free / Price Tier 0 and add its five localized names and descriptions.
3. Add the five required localized names/descriptions and review screenshots,
   then make both IAPs available with the app version.
4. Set the Lifetime product's base country or region to **Japan** and currency to
   **JPY**. Use a launch promotional price of **¥500**.
5. In App Store Connect, schedule the normal price of **¥980** for a specified
   date approximately three months after launch. A scheduled IAP price change
   normally requires neither a code change nor a new app release.

Before the user obtains the Trial product, the upgrade screen explains its
seven-day duration, included Pro features, features removed at expiry, continued
Free access, absence of automatic charges or purchases, and the Lifetime price
provided dynamically by StoreKit.

## Trial entitlement and clock protection

A verified Trial transaction starts the trial. Its authoritative start is the
transaction's original `purchaseDate`, and its end is exactly seven days later.
The non-consumable transaction prevents the same Apple ID from obtaining the
Trial again after expiry, app deletion, or reinstall. Restoring purchases uses
that original date, so it cannot restart an expired trial.

The Keychain stores only the greatest observed time after a Trial transaction
exists. This mitigates moving the device clock backwards, but it never creates a
trial or supplies its start date. The old, unreleased `proTrial.v1` record's
`startedAt` value is ignored; retaining the same record permits its `lastSeenAt`
to continue protecting internal test installations without a complex migration.

## Entitlement propagation

The app does not publish an App Group or WatchConnectivity snapshot until StoreKit
has completed its initial current-entitlement query. Every subsequent entitlement
change, including transaction updates, purchases, restore, foreground checks, and
the in-app Trial-expiry check, follows the same manager-to-store publication path.

Snapshots carry the active Trial's expiry date derived from the verified
transaction purchase date. Widget and Watch clients combine access level, expiry,
and their current time; an expired cached Trial therefore uses Free presentation
without requiring the iOS app to reopen. Lifetime Pro has no expiry date.

Settings presents Upgrade from within the Settings sheet. Free and Trial users can
open it from membership or gated controls, while the Lifetime Pro status does not
request an upgrade and dismissing Settings clears any deferred Dashboard route.
