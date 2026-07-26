#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

fail() {
  printf '%s\n' "iOS device probe failure: $1" >&2
  exit 1
}

require_environment() {
  variable_name=$1
  eval "variable_value=\${$variable_name:-}"
  test -n "$variable_value" ||
    fail "required environment variable is unset: $variable_name"
}

require_environment IOS_DEVICE_ID
require_environment IOS_SIGNING_IDENTITY
require_environment IOS_PROVISIONING_PROFILE
require_environment IOS_BUNDLE_IDENTIFIER

test -f "$IOS_PROVISIONING_PROFILE" ||
  fail "provisioning profile does not exist: $IOS_PROVISIONING_PROFILE"

unsigned_app="$repository_root/_build/ios/probes/iphoneos/BonsaiFlutterProbe.app"
signed_root="$repository_root/_build/ios/probes/iphoneos/signed"

test -d "$unsigned_app" ||
  fail "unsigned probe is missing; run tool/ios/build_probe.sh iphoneos"

mkdir -p "$signed_root"
run_directory=$(mktemp -d "$signed_root/run.XXXXXX")
signed_app="$run_directory/BonsaiFlutterProbe.app"
decoded_profile="$run_directory/profile.plist"
entitlements="$run_directory/entitlements.plist"
device_details="$run_directory/device.json"
install_result="$run_directory/install.json"
launch_result="$run_directory/launch.json"
launch_log="$run_directory/launch.log"

ditto "$unsigned_app" "$signed_app"
plutil -replace CFBundleIdentifier \
  -string "$IOS_BUNDLE_IDENTIFIER" \
  "$signed_app/Info.plist"
cp "$IOS_PROVISIONING_PROFILE" "$signed_app/embedded.mobileprovision"

security cms -D -i "$IOS_PROVISIONING_PROFILE" > "$decoded_profile"
plutil -extract Entitlements xml1 -o "$entitlements" "$decoded_profile"

profile_application_identifier=$(
  plutil -extract Entitlements.application-identifier raw -o - "$decoded_profile"
)
case "$profile_application_identifier" in
  *."$IOS_BUNDLE_IDENTIFIER" | *.\*)
    ;;
  *)
    fail "provisioning profile does not cover $IOS_BUNDLE_IDENTIFIER"
    ;;
esac

plutil -p "$decoded_profile" |
  grep -F -- "$IOS_DEVICE_ID" >/dev/null ||
  fail "provisioning profile does not include the selected device"

xcrun devicectl device info details \
  --device "$IOS_DEVICE_ID" \
  --json-output "$device_details" >/dev/null
plutil -convert json -o - "$device_details" |
  grep -F -- "\"udid\":\"$IOS_DEVICE_ID\"" >/dev/null ||
  fail "selected physical device is unavailable"
plutil -convert json -o - "$device_details" |
  grep -F -- '"reality":"physical"' >/dev/null ||
  fail "selected target is not a physical device"

codesign \
  --force \
  --sign "$IOS_SIGNING_IDENTITY" \
  --entitlements "$entitlements" \
  --timestamp=none \
  "$signed_app"
codesign --verify --deep --strict "$signed_app"

xcrun devicectl device install app \
  --device "$IOS_DEVICE_ID" \
  --json-output "$install_result" \
  "$signed_app"

if ! xcrun devicectl device process launch \
  --device "$IOS_DEVICE_ID" \
  --terminate-existing \
  --console \
  --timeout 15 \
  --json-output "$launch_result" \
  "$IOS_BUNDLE_IDENTIFIER" > "$launch_log" 2>&1; then
  :
fi

grep -F -- "BONSAI_FLUTTER_IOS_PROBE_OK result=42" "$launch_log" >/dev/null ||
  fail "physical device did not execute the OCaml probe callback"

printf '%s\n' "iOS physical-device OCaml probe passed"
