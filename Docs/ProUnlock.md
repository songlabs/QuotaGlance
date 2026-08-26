# Pro unlock and App Store Connect

QuotaGlance uses StoreKit 2 with the non-consumable product identifier
`com.songlabs.QuotaGlance.pro.lifetime`. The application never embeds a price;
the upgrade screen displays StoreKit's localized `Product.displayPrice`.

## App Store Connect setup

1. Accept any pending Paid Apps agreement and complete Tax and Banking under
   Agreements, Tax, and Banking.
2. In the app record, create an in-app purchase with type **Non-Consumable** and
   product ID `com.songlabs.QuotaGlance.pro.lifetime`.
3. Add the five required localized display names/descriptions and review
   screenshot, then make the IAP available with the app version.
4. Select the App Store Connect price point whose China storefront price is
   CNY 500 for the launch period. Storefront prices and tax adjustments remain
   controlled by App Store Connect.
5. After the launch period, schedule/select the price point whose China
   storefront price is CNY 980. No code or app release is required because the
   application reads `displayPrice` from StoreKit.

App Review notes should state that this is a one-time, non-renewing lifetime
unlock; the app itself grants a seven-day trial without requiring a purchase;
and Free mode remains usable on iPhone and Apple Watch. Provide a review account
only if the existing provider login flow otherwise prevents review of the UI.

## Trial persistence and limitations

The first app launch creates a trial record in the device Keychain. It stores
the start and greatest observed time, so moving the clock backwards does not
extend an already-observed trial. Keychain data normally survives deleting and
reinstalling the app on the same device; StoreKit current entitlements restore
verified purchases after reinstall.

Without a server or App Account Token backed by an account, an app-managed trial
cannot absolutely prevent a trial reset after a device erase, Keychain reset,
restore to another device, or other local-data manipulation. That limitation is
accepted to avoid adding a backend solely for trial enforcement.
