#!/usr/bin/env bash
# macOS / Codemagic Workflow Editor. Never enable shell tracing here.
set +x
set -euo pipefail
umask 077

fail() { printf '%s\n' "[ios-firebase] ERROR: $1" >&2; exit 1; }
root="${CM_BUILD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
mode="${1:-prepare}"

read_key() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

validate_firebase() {
  local file="$1" value
  [[ -f "$file" ]] || fail 'GoogleService-Info.plist is missing.'
  /usr/bin/plutil -lint "$file" >/dev/null 2>&1 || fail 'Invalid plist format.'
  value="$(read_key "$file" BUNDLE_ID)" || fail 'BUNDLE_ID is missing.'
  [[ "$value" == 'com.okeyix.game' ]] || fail 'Unexpected Firebase BUNDLE_ID.'
  value="$(read_key "$file" GOOGLE_APP_ID)" || fail 'GOOGLE_APP_ID is missing.'
  [[ "$value" == '1:445431980577:ios:488f00b9d026798bc3f960' ]] || fail 'Unexpected Firebase GOOGLE_APP_ID.'
  value="$(read_key "$file" PROJECT_ID)" || fail 'PROJECT_ID is missing.'
  [[ "$value" == 'okeyix-cf7b4' ]] || fail 'Unexpected Firebase PROJECT_ID.'
  value="$(read_key "$file" GCM_SENDER_ID)" || fail 'GCM_SENDER_ID is missing.'
  [[ "$value" == '445431980577' ]] || fail 'Unexpected Firebase GCM_SENDER_ID.'
  value="$(read_key "$file" API_KEY)" || fail 'API_KEY is missing.'
  [[ "$value" =~ ^AIza[A-Za-z0-9_-]{35}$ ]] || fail 'Invalid Firebase API_KEY structure.'
}

case "$mode" in
  prepare)
    [[ -n "${IOS_GOOGLE_SERVICE_INFO_PLIST_B64:-}" ]] || fail 'IOS_GOOGLE_SERVICE_INFO_PLIST_B64 is missing or empty.'
    # Accept line-wrapped Base64; reject invalid alphabet, length and padding.
    encoded="$(printf '%s' "$IOS_GOOGLE_SERVICE_INFO_PLIST_B64" | tr -d '[:space:]')"
    [[ -n "$encoded" && "$encoded" =~ ^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$ ]] || fail 'Invalid Base64 encoding.'
    directory="$root/ios/Runner"
    [[ -d "$directory" ]] || fail 'ios/Runner directory was not found.'
    temporary="$(mktemp "$directory/.GoogleService-Info.XXXXXX")"
    trap 'rm -f -- "$temporary"' EXIT
    if ! printf '%s' "$encoded" | /usr/bin/base64 -D >"$temporary" 2>/dev/null; then
      fail 'Base64 decoding failed.'
    fi
    validate_firebase "$temporary"
    /usr/bin/plutil -lint "$root/ios/Runner.xcodeproj/project.pbxproj" >/dev/null 2>&1 || fail 'Invalid Xcode project format.'
    # Atomic replacement only after successful validation. Never edit plist keys.
    mv -f -- "$temporary" "$directory/GoogleService-Info.plist"
    unset encoded IOS_GOOGLE_SERVICE_INFO_PLIST_B64
    printf '%s\n' '[ios-firebase] Validated Firebase plist prepared for Runner resources.'
    ;;
  verify)
    app="${2:-$root/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app}"
    [[ -d "$app" ]] || fail 'Runner.app directory was not found; pass its actual path as the second argument.'
    validate_firebase "$app/GoogleService-Info.plist"
    /usr/bin/plutil -lint "$app/Info.plist" >/dev/null 2>&1 || fail 'Invalid Runner.app/Info.plist.'
    identifier="$(read_key "$app/Info.plist" CFBundleIdentifier)" || fail 'App CFBundleIdentifier is missing.'
    [[ "$identifier" == 'com.okeyix.game' ]] || fail 'Unexpected app CFBundleIdentifier.'
    if [[ -f "$root/ios/Runner/GoogleService-Info.plist" ]]; then
      # Xcode may convert the copied plist to binary; compare values, not bytes.
      for key in BUNDLE_ID GOOGLE_APP_ID PROJECT_ID GCM_SENDER_ID API_KEY STORAGE_BUCKET IS_ADS_ENABLED IS_ANALYTICS_ENABLED; do
        if source_value="$(read_key "$root/ios/Runner/GoogleService-Info.plist" "$key")"; then
          bundled_value="$(read_key "$app/GoogleService-Info.plist" "$key")" || fail "Bundled plist is missing $key."
          [[ "$source_value" == "$bundled_value" ]] || fail "Bundled plist differs from the prepared source at $key."
        fi
      done
    fi
    printf '%s\n' '[ios-firebase] Runner.app contains the expected valid Firebase plist.'
    ;;
  *) fail 'Usage: bash tool/codemagic_ios_firebase.sh prepare | verify [Runner.app path]' ;;
esac
