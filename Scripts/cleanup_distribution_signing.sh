#!/bin/bash
set -u

installed_profiles_file="${INSTALLED_PROFILES_FILE:-${RUNNER_TEMP:-}/distribution-signing/installed-profiles.txt}"
keychain_path="${SIGNING_KEYCHAIN_PATH:-${RUNNER_TEMP:-}/quotaglance-signing.keychain-db}"

if [[ -f "$installed_profiles_file" ]]; then
  while IFS= read -r profile; do
    [[ -n "$profile" ]] && rm -f "$profile"
  done < "$installed_profiles_file"
fi

if [[ -n "$keychain_path" ]]; then
  security delete-keychain "$keychain_path" 2>/dev/null || true
fi

if [[ -n "${RUNNER_TEMP:-}" ]]; then
  rm -rf "$RUNNER_TEMP/distribution-signing"
fi
