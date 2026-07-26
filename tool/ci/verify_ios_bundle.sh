#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

fail() {
  printf '%s\n' "signed iOS bundle verification failure: $1" >&2
  exit 1
}

if test "$#" -lt 2 || test "$#" -gt 3; then
  fail "usage: tool/ci/verify_ios_bundle.sh <app> <development|distribution> [dSYM]"
fi

app_bundle=$1
signing_kind=$2
dsym=${3:-}

case "$signing_kind" in
  development | distribution)
    ;;
  *)
    fail "signing kind must be development or distribution"
    ;;
esac

if test -n "$dsym"; then
  "$repository_root/tool/ios/verify_app_bundle.sh" "$app_bundle" "$dsym"
else
  "$repository_root/tool/ios/verify_app_bundle.sh" "$app_bundle"
fi

framework="$app_bundle/Frameworks/bonsai_flutter_native.framework"
profile="$app_bundle/embedded.mobileprovision"
test -f "$profile" || fail "embedded provisioning profile is missing"

codesign --verify --deep --strict "$app_bundle" >/dev/null 2>&1 ||
  fail "application code signature is invalid"
codesign --verify --strict "$framework" >/dev/null 2>&1 ||
  fail "native framework code signature is invalid"

work_root="$repository_root/_build/ios/signed-bundle-audit"
mkdir -p "$work_root"
work_directory=$(mktemp -d "$work_root/run.XXXXXX")
decoded_profile="$work_directory/profile.plist"
app_entitlements="$work_directory/app-entitlements.plist"

security cms -D -i "$profile" >"$decoded_profile"
codesign -d --entitlements :- "$app_bundle" >"$app_entitlements" 2>/dev/null

profile_team=$(
  plutil -extract TeamIdentifier.0 raw -o - "$decoded_profile"
)
profile_app_id=$(
  plutil -extract Entitlements.application-identifier raw -o - "$decoded_profile"
)
app_team=$(
  plutil -extract com.apple.developer.team-identifier raw -o - \
    "$app_entitlements"
)
app_id=$(
  plutil -extract application-identifier raw -o - "$app_entitlements"
)

test "$profile_team" = "$app_team" ||
  fail "application and provisioning-profile Team IDs differ"
case "$app_id" in
  "$profile_app_id")
    ;;
  *)
    fail "application and provisioning-profile App IDs differ"
    ;;
esac

profile_debuggable=$(
  plutil -extract Entitlements.get-task-allow raw -o - "$decoded_profile"
)
app_debuggable=$(
  plutil -extract get-task-allow raw -o - "$app_entitlements"
)
test "$profile_debuggable" = "$app_debuggable" ||
  fail "application and provisioning-profile debug entitlements differ"

case "$signing_kind:$app_debuggable" in
  development:true | distribution:false)
    ;;
  *)
    fail "get-task-allow does not match the required signing kind"
    ;;
esac

printf '%s\n' "signed iOS application bundle verification passed"
