#!/bin/bash
set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_DISTRIBUTION_P12_BASE64:?APPLE_DISTRIBUTION_P12_BASE64 is required}"
: "${APPLE_DISTRIBUTION_P12_PASSWORD:?APPLE_DISTRIBUTION_P12_PASSWORD is required}"

profiles=(
  "PROFILE_QUOTAGLANCE_BASE64|com.songlabs.QuotaGlance|QuotaGlance App Store"
  "PROFILE_QUOTAGLANCE_WIDGET_BASE64|com.songlabs.QuotaGlance.widget|QuotaGlance Widget App Store"
  "PROFILE_QUOTAGLANCE_WATCH_BASE64|com.songlabs.QuotaGlance.watchkitapp|QuotaGlance Watch App Store"
  "PROFILE_QUOTAGLANCE_WATCH_WIDGET_BASE64|com.songlabs.QuotaGlance.watchkitapp.widget|QuotaGlance Watch Widget App Store"
)

signing_directory="$RUNNER_TEMP/distribution-signing"
keychain_path="$RUNNER_TEMP/quotaglance-signing.keychain-db"
keychain_password="$(openssl rand -hex 32)"
p12_path="$signing_directory/distribution.p12"
installed_profiles_file="$signing_directory/installed-profiles.txt"
profiles_directory="$HOME/Library/MobileDevice/Provisioning Profiles"

mkdir -p "$signing_directory" "$profiles_directory"
chmod 700 "$signing_directory"
printf '%s' "$APPLE_DISTRIBUTION_P12_BASE64" | base64 --decode > "$p12_path"
chmod 600 "$p12_path"

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$p12_path" -k "$keychain_path" -P "$APPLE_DISTRIBUTION_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path" login.keychain-db

identities="$(security find-identity -v -p codesigning "$keychain_path")"
printf '%s\n' "$identities"
distribution_identity_count="$(printf '%s\n' "$identities" | grep -c 'Apple Distribution:' || true)"
test "$distribution_identity_count" -eq 1 || {
  echo "Expected exactly one valid Apple Distribution identity, found $distribution_identity_count." >&2
  exit 1
}

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

for profile_definition in "${profiles[@]}"; do
  IFS='|' read -r secret_name expected_bundle_id expected_name <<< "$profile_definition"
  profile_base64="${!secret_name:-}"
  test -n "$profile_base64" || { echo "Missing $secret_name" >&2; exit 1; }

  encoded_profile="$signing_directory/$expected_bundle_id.mobileprovision"
  decoded_profile="$signing_directory/$expected_bundle_id.plist"
  printf '%s' "$profile_base64" | base64 --decode > "$encoded_profile"
  security cms -D -i "$encoded_profile" > "$decoded_profile"

  uuid="$(read_plist "$decoded_profile" UUID)"
  name="$(read_plist "$decoded_profile" Name)"
  team_identifier="$(read_plist "$decoded_profile" TeamIdentifier:0)"
  application_identifier="$(read_plist "$decoded_profile" Entitlements:application-identifier)"
  expiration_date="$(read_plist "$decoded_profile" ExpirationDate)"
  get_task_allow="$(read_plist "$decoded_profile" Entitlements:get-task-allow 2>/dev/null || printf 'false')"

  test "$name" = "$expected_name" || { echo "Profile for $expected_bundle_id must be named '$expected_name'." >&2; exit 1; }
  test "$team_identifier" = "$APPLE_TEAM_ID" || { echo "Wrong team in profile $uuid." >&2; exit 1; }
  test "$application_identifier" = "$APPLE_TEAM_ID.$expected_bundle_id" || { echo "Wrong Bundle ID in profile $uuid." >&2; exit 1; }
  test "$get_task_allow" = "false" || { echo "Development profile rejected for $expected_bundle_id." >&2; exit 1; }
  ! /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$decoded_profile" >/dev/null 2>&1 || {
    echo "Development or Ad Hoc profile rejected for $expected_bundle_id." >&2
    exit 1
  }
  ! /usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$decoded_profile" >/dev/null 2>&1 || {
    echo "Enterprise profile rejected for $expected_bundle_id." >&2
    exit 1
  }
  test "$(date -j -f '%a %b %d %T %Y' "$expiration_date" '+%s')" -gt "$(date '+%s')" || {
    echo "Expired profile rejected for $expected_bundle_id." >&2
    exit 1
  }

  installed_profile="$profiles_directory/$uuid.mobileprovision"
  cp "$encoded_profile" "$installed_profile"
  printf '%s\n' "$installed_profile" >> "$installed_profiles_file"
  printf 'Profile UUID: %s\nBundle ID: %s\nExpiration: %s\nSigning type: App Store distribution\n\n' \
    "$uuid" "$expected_bundle_id" "$expiration_date"
done

{
  echo "SIGNING_KEYCHAIN_PATH=$keychain_path"
  echo "SIGNING_P12_PATH=$p12_path"
  echo "INSTALLED_PROFILES_FILE=$installed_profiles_file"
} >> "$GITHUB_ENV"
