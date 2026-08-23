#!/bin/bash
set -euo pipefail

archive_path=${1:?Usage: verify_distribution_archive.sh ARCHIVE_PATH}
shopt -s nullglob

app_candidates=("$archive_path"/Products/Applications/*.app)
if (( ${#app_candidates[@]} != 1 )); then
  echo "Expected exactly one Main App in the archive, found ${#app_candidates[@]}." >&2
  exit 1
fi
app="${app_candidates[0]}"

phone_widget_candidates=("$app"/PlugIns/*.appex)
if (( ${#phone_widget_candidates[@]} != 1 )); then
  echo "Expected exactly one iPhone Widget in the Main App, found ${#phone_widget_candidates[@]}." >&2
  exit 1
fi
phone_widget="${phone_widget_candidates[0]}"

watch_app_candidates=("$app"/Watch/*.app)
if (( ${#watch_app_candidates[@]} != 1 )); then
  echo "Expected exactly one Watch App in the Main App, found ${#watch_app_candidates[@]}." >&2
  exit 1
fi
watch_app="${watch_app_candidates[0]}"

watch_widget_candidates=("$watch_app"/PlugIns/*.appex)
if (( ${#watch_widget_candidates[@]} != 1 )); then
  echo "Expected exactly one Watch Widget in the Watch App, found ${#watch_widget_candidates[@]}." >&2
  exit 1
fi
watch_widget="${watch_widget_candidates[0]}"

assert_plist_value() {
  local plist=$1 key_path=$2 expected=$3
  local actual
  actual=$(/usr/libexec/PlistBuddy -c "Print :$key_path" "$plist")
  test "$actual" = "$expected" || {
    echo "Unexpected $key_path in $(basename "$plist"): expected '$expected', got '$actual'" >&2
    exit 1
  }
}

assert_plist_value "$app/Info.plist" CFBundleIdentifier com.songlabs.QuotaGlance
assert_plist_value "$phone_widget/Info.plist" CFBundleIdentifier com.songlabs.QuotaGlance.widget
assert_plist_value "$phone_widget/Info.plist" NSExtension:NSExtensionPointIdentifier com.apple.widgetkit-extension
assert_plist_value "$watch_app/Info.plist" CFBundleIdentifier com.songlabs.QuotaGlance.watchkitapp
assert_plist_value "$watch_app/Info.plist" WKCompanionAppBundleIdentifier com.songlabs.QuotaGlance
assert_plist_value "$watch_widget/Info.plist" CFBundleIdentifier com.songlabs.QuotaGlance.watchkitapp.widget
assert_plist_value "$watch_widget/Info.plist" NSExtension:NSExtensionPointIdentifier com.apple.widgetkit-extension

codesign --verify --deep --strict --verbose=2 "$app"
for bundle in "$app" "$phone_widget" "$watch_app" "$watch_widget"; do
  codesign --verify --strict --verbose=2 "$bundle"
  test -f "$bundle/embedded.mobileprovision" || {
    echo "Missing embedded provisioning profile: $bundle/embedded.mobileprovision" >&2
    exit 1
  }
done

entitlements_directory=$(mktemp -d)
trap 'rm -rf "$entitlements_directory"' EXIT

app_entitlements="$entitlements_directory/main-app.plist"
phone_widget_entitlements="$entitlements_directory/phone-widget.plist"
watch_app_entitlements="$entitlements_directory/watch-app.plist"
watch_widget_entitlements="$entitlements_directory/watch-widget.plist"

codesign -d --entitlements :- "$app" > "$app_entitlements"
codesign -d --entitlements :- "$phone_widget" > "$phone_widget_entitlements"
codesign -d --entitlements :- "$watch_app" > "$watch_app_entitlements"
codesign -d --entitlements :- "$watch_widget" > "$watch_widget_entitlements"

assert_plist_value "$app_entitlements" com.apple.security.application-groups:0 group.com.songlabs.QuotaGlance
assert_plist_value "$phone_widget_entitlements" com.apple.security.application-groups:0 group.com.songlabs.QuotaGlance
assert_plist_value "$watch_app_entitlements" com.apple.security.application-groups:0 group.com.songlabs.QuotaGlance.watch
assert_plist_value "$watch_widget_entitlements" com.apple.security.application-groups:0 group.com.songlabs.QuotaGlance.watch

echo "Archive structure, signatures, provisioning profiles, and required App Group entitlements are valid."
