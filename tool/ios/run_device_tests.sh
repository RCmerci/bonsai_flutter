#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
integration_root="$repository_root/flutter/integration_test"

fail() {
  printf '%s\n' "iOS physical-device test failure: $1" >&2
  exit 1
}

require_environment() {
  variable_name=$1
  eval "variable_value=\${$variable_name:-}"
  test -n "$variable_value" ||
    fail "required environment variable is unset: $variable_name"
}

command -v expect >/dev/null 2>&1 ||
  fail "required command is unavailable: expect"

if test "$#" -lt 2; then
  fail "usage: tool/ios/run_device_tests.sh <device-id> [--debug] [--profile] [--release]"
fi

device_id=$1
shift
run_debug=false
run_profile=false
run_release=false
for mode in "$@"; do
  case "$mode" in
    --debug)
      run_debug=true
      ;;
    --profile)
      run_profile=true
      ;;
    --release)
      run_release=true
      ;;
    *)
      fail "unknown mode: $mode"
      ;;
  esac
done

if test "$run_debug" = false &&
  test "$run_profile" = false &&
  test "$run_release" = false; then
  fail "at least one explicit build mode is required"
fi

require_environment IOS_DEVELOPMENT_TEAM
require_environment IOS_BUNDLE_IDENTIFIER
require_environment IOS_DEVELOPMENT_PROFILE_SPECIFIER
if test "$run_release" = true; then
  require_environment IOS_DISTRIBUTION_PROFILE_SPECIFIER
  require_environment IOS_EXPORT_OPTIONS_PLIST
fi

"$repository_root/tool/ci/ios_device_preflight.sh" \
  "$device_id" \
  --require-signing
"$repository_root/tool/ios/build_native_objects.sh" iphoneos

result_root="$repository_root/_build/ios/device-results"
mkdir -p "$result_root"
development_signing_xcconfig=$(
  mktemp "$result_root/development-signing.XXXXXX.xcconfig"
)
trap 'rm -f -- "$development_signing_xcconfig"' EXIT HUP INT TERM
printf '%s\n' \
  "DEVELOPMENT_TEAM = $IOS_DEVELOPMENT_TEAM" \
  "CODE_SIGN_STYLE = Manual" \
  "PROVISIONING_PROFILE_SPECIFIER = $IOS_DEVELOPMENT_PROFILE_SPECIFIER" \
  >"$development_signing_xcconfig"

if test "$run_debug" = true; then
  (
    cd "$integration_root"
    XCODE_XCCONFIG_FILE="$development_signing_xcconfig" \
      flutter test integration_test/ios_ffi_test.dart -d "$device_id"
  )
  (
    cd "$integration_root"
    XCODE_XCCONFIG_FILE="$development_signing_xcconfig" \
      "$repository_root/tool/ios/run_hot_restart_test.exp" \
        "$device_id" \
        integration_test/ios_ffi_test.dart
  )
fi

run_xctest_mode() {
  mode=$1
  configuration=$2
  derived_data="$result_root/$mode-derived-data"
  result_bundle="$result_root/$mode.xcresult"

  (
    cd "$integration_root"
    flutter build ios \
      "--$mode" \
      --no-codesign \
      --target integration_test/ios_ffi_test.dart
  )
  xcodebuild build-for-testing \
    -project "$integration_root/ios/Runner.xcodeproj" \
    -scheme Runner \
    -configuration "$configuration" \
    -destination "id=$device_id" \
    -derivedDataPath "$derived_data" \
    DEVELOPMENT_TEAM="$IOS_DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Manual \
    PROVISIONING_PROFILE_SPECIFIER="$IOS_DEVELOPMENT_PROFILE_SPECIFIER"
  xcodebuild test-without-building \
    -project "$integration_root/ios/Runner.xcodeproj" \
    -scheme Runner \
    -configuration "$configuration" \
    -destination "id=$device_id" \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$result_bundle" \
    DEVELOPMENT_TEAM="$IOS_DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Manual \
    PROVISIONING_PROFILE_SPECIFIER="$IOS_DEVELOPMENT_PROFILE_SPECIFIER"
}

if test "$run_profile" = true; then
  run_xctest_mode profile Profile
fi

if test "$run_release" = true; then
  run_xctest_mode release Release

  counter_root="$repository_root/examples/counter/flutter"
  archive_path="$result_root/Counter.xcarchive"
  export_path="$result_root/Counter-export"
  (
    cd "$counter_root"
    flutter build ios --release --no-codesign
  )
  xcodebuild archive \
    -project "$counter_root/ios/Runner.xcodeproj" \
    -scheme Runner \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$archive_path" \
    DEVELOPMENT_TEAM="$IOS_DEVELOPMENT_TEAM" \
    PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE_IDENTIFIER" \
    CODE_SIGN_STYLE=Manual \
    PROVISIONING_PROFILE_SPECIFIER="$IOS_DISTRIBUTION_PROFILE_SPECIFIER"
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$IOS_EXPORT_OPTIONS_PLIST"
  exported_ipa=$(
    find "$export_path" -maxdepth 1 -type f -name '*.ipa' -print -quit
  )
  test -n "$exported_ipa" ||
    fail "the Release archive did not export an IPA"
  unpacked_ipa="$result_root/exported-ipa"
  mkdir -p "$unpacked_ipa"
  ditto -x -k "$exported_ipa" "$unpacked_ipa"
  exported_app=$(
    find "$unpacked_ipa/Payload" \
      -maxdepth 1 \
      -type d \
      -name '*.app' \
      -print \
      -quit
  )
  test -n "$exported_app" ||
    fail "the exported IPA does not contain an application bundle"
  exported_bundle_identifier=$(
    plutil -extract CFBundleIdentifier raw -o - "$exported_app/Info.plist"
  )
  test "$exported_bundle_identifier" = "$IOS_BUNDLE_IDENTIFIER" ||
    fail "the exported application has an unexpected bundle identifier"
  "$repository_root/tool/ci/verify_ios_bundle.sh" \
    "$exported_app" \
    distribution \
    "$archive_path/dSYMs/bonsai_flutter_native.framework.dSYM"
  install_result="$result_root/release-install.json"
  launch_result="$result_root/release-launch.json"
  xcrun devicectl device install app \
    --device "$device_id" \
    --quiet \
    --json-output "$install_result" \
    "$exported_app"
  xcrun devicectl device process launch \
    --device "$device_id" \
    --terminate-existing \
    --quiet \
    --json-output "$launch_result" \
    "$IOS_BUNDLE_IDENTIFIER"
fi

printf '%s\n' "requested iOS physical-device mode matrix passed"
