#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ios_tool_directory="$repository_root/tool/ios"

# shellcheck source=tool/ios/toolchain.lock
. "$ios_tool_directory/toolchain.lock"

fail() {
  printf '%s\n' "iOS deployment-target contract failure: $1" >&2
  exit 1
}

expected_version=15.0
legacy_major=13
legacy_version_pattern="iOS[[:space:]-]?$legacy_major|ios$legacy_major|IPHONEOS_DEPLOYMENT_TARGET[[:space:]=:\"']*$legacy_major[.]0|ios_deployment_target[[:space:]=:\"']*$legacy_major[.]0|arm64-apple-ios$legacy_major[.]0|miphoneos-version-min=$legacy_major[.]0"

test "$IOS_DEPLOYMENT_TARGET" = "$expected_version" ||
  fail "toolchain target is $IOS_DEPLOYMENT_TARGET, expected $expected_version"
test "$IPHONEOS_TARGET_TRIPLE" = "arm64-apple-ios$expected_version" ||
  fail "target triple is $IPHONEOS_TARGET_TRIPLE"

probe_version=$(
  /usr/libexec/PlistBuddy \
    -c 'Print :MinimumOSVersion' \
    "$ios_tool_directory/probe/Info.plist"
)
test "$probe_version" = "$expected_version" ||
  fail "probe MinimumOSVersion is $probe_version, expected $expected_version"

project_files=$(
  find \
    "$repository_root/examples" \
    "$repository_root/flutter/integration_test" \
    -path '*/ios/*.xcodeproj/project.pbxproj' \
    -type f |
    LC_ALL=C sort
)
test -n "$project_files" || fail "no iOS Xcode projects were found"

printf '%s\n' "$project_files" |
  while IFS= read -r project_file; do
    target_versions=$(
      awk '
        /IPHONEOS_DEPLOYMENT_TARGET =/ {
          value = $3
          sub(/;$/, "", value)
          print value
        }
      ' "$project_file"
    )
    test -n "$target_versions" ||
      fail "$project_file does not declare IPHONEOS_DEPLOYMENT_TARGET"
    unexpected_versions=$(
      printf '%s\n' "$target_versions" |
        grep -Fvx "$expected_version" || true
    )
    test -z "$unexpected_versions" ||
      fail "$project_file has non-$expected_version targets: $unexpected_versions"
  done

native_asset_pubspecs=$(
  rg -l \
    'native_artifact_root:' \
    "$repository_root/examples" \
    "$repository_root/flutter/integration_test" \
    --glob 'pubspec.yaml' |
    LC_ALL=C sort
)
test -n "$native_asset_pubspecs" ||
  fail "no native-asset workspace pubspecs were found"

printf '%s\n' "$native_asset_pubspecs" |
  while IFS= read -r pubspec_file; do
    grep -F "ios_deployment_target: '$expected_version'" "$pubspec_file" >/dev/null ||
      fail "$pubspec_file does not pass iOS $expected_version to the build hook"
  done

grep -F 'ios_deployment_target' \
  "$repository_root/flutter/packages/bonsai_flutter_native/hook/build.dart" >/dev/null ||
  fail "the native build hook does not consume ios_deployment_target"

for script in \
  "$ios_tool_directory/verify_app_bundle.sh" \
  "$repository_root/tool/eio_worker_spike/build_ios_complete_object.sh" \
  "$repository_root/tool/eio_worker_spike/test_ios_complete_object.sh"
do
  grep -F 'toolchain.lock' "$script" >/dev/null ||
    fail "$script does not load the deployment-target lock"
  grep -F 'IOS_DEPLOYMENT_TARGET' "$script" >/dev/null ||
    fail "$script does not use IOS_DEPLOYMENT_TARGET"
done

legacy_hits=$(
  rg -n \
    --hidden \
    --glob '!_build/**' \
    --glob '!.git/**' \
    --glob '!tool/test_ios_deployment_target_contract.sh' \
    "$legacy_version_pattern" \
    "$repository_root" || true
)
test -z "$legacy_hits" ||
  fail "legacy iOS deployment-target references remain:\n$legacy_hits"

test ! -e \
  "$repository_root/vendor/patches/ios/eio-posix-ios${legacy_major}-positioned-io.patch" ||
  fail "the obsolete Eio positioned-I/O fallback still exists"

if rg -n \
  '__builtin_available\(iOS 14[.]0|preadv_ios|pwritev_ios' \
  "$ios_tool_directory" \
  "$repository_root/tool/eio_worker_spike" \
  "$repository_root/vendor/patches/ios" >/dev/null; then
  fail "legacy positioned-I/O fallback code remains"
fi

printf '%s\n' "iOS deployment-target contract passed: $expected_version"
