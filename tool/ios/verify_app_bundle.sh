#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
export_list="$repository_root/flutter/packages/bonsai_flutter_native/src/bonsai_flutter_exports.txt"

fail() {
  printf '%s\n' "iOS app-bundle verification failure: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

test "$#" -ge 1 && test "$#" -le 2 ||
  fail "usage: verify_app_bundle.sh <Runner.app> [framework.dSYM]"

app_path=$1
dsym_path=${2:-}
framework_name=bonsai_flutter_native
framework_path="$app_path/Frameworks/$framework_name.framework"
binary_path="$framework_path/$framework_name"
manifest_path="$app_path/Frameworks/App.framework/flutter_assets/NativeAssetsManifest.json"
privacy_manifest="$app_path/PrivacyInfo.xcprivacy"

for command_name in file jq nm plutil sed sort xcrun; do
  require_command "$command_name"
done

test -d "$app_path" || fail "application bundle does not exist: $app_path"
test -f "$binary_path" || fail "native framework does not exist: $binary_path"
test -f "$manifest_path" || fail "Native Assets manifest is missing"
test -f "$privacy_manifest" || fail "application privacy manifest is missing"

"$script_directory/verify_macho.sh" "$binary_path" IOS arm64 13.0

install_name=$(
  xcrun otool -D "$binary_path" |
    sed -n '2p' |
    sed 's/^[[:space:]]*//'
)
expected_install_name="@rpath/$framework_name.framework/$framework_name"
test "$install_name" = "$expected_install_name" ||
  fail "unexpected install name: $install_name"

xcrun otool -L "$binary_path" |
  sed -n '3,$p' |
  sed 's/^[[:space:]]*//' |
  while IFS= read -r dependency; do
    case "$dependency" in
      @* | /usr/lib/* | /System/Library/*) ;;
      '') ;;
      *) fail "prohibited framework dependency: $dependency" ;;
    esac
  done

actual_exports=$(
  nm -gU "$binary_path" |
    awk '{ print $3 }' |
    sort
)
expected_exports=$(sort "$export_list")
test "$actual_exports" = "$expected_exports" ||
  fail "framework exports differ from $export_list"

asset_path=$(
  jq -r \
    '."native-assets".ios_arm64[
      "package:bonsai_flutter_native/bonsai_flutter_native_bindings_generated.dart"
    ][1]' \
    "$manifest_path"
)
test "$asset_path" = "$framework_name.framework/$framework_name" ||
  fail "Native Assets manifest points at $asset_path"

prohibited_process_symbols=$(
  nm -u "$binary_path" |
    awk '{ print $1 }' |
    grep -E \
      '^_(fork|execv|execve|execvp|posix_spawn|posix_spawnp|popen|system)$' ||
    true
)
test -z "$prohibited_process_symbols" ||
  fail "framework references prohibited process APIs: $prohibited_process_symbols"

undefined_symbols=$(
  nm -u "$binary_path" |
    awk '{ print $1 }'
)
printf '%s\n' "$undefined_symbols" |
  grep -E '^_(fstat|lstat|stat)$' >/dev/null ||
  fail "file-timestamp reason is declared without a matching linked API"
printf '%s\n' "$undefined_symbols" |
  grep -E '^_(clock_gettime_nsec_np|mach_absolute_time)$' >/dev/null ||
  fail "system-boot-time reason is declared without a matching linked API"

plutil -lint "$privacy_manifest" >/dev/null ||
  fail "application privacy manifest is invalid"
privacy_json=$(
  plutil -convert json -o - "$privacy_manifest"
)
printf '%s\n' "$privacy_json" |
  jq -e '
    .NSPrivacyTracking == false
    and .NSPrivacyCollectedDataTypes == []
    and (
      .NSPrivacyAccessedAPITypes
      | length == 2
    )
    and any(
      .NSPrivacyAccessedAPITypes[];
      .NSPrivacyAccessedAPIType
        == "NSPrivacyAccessedAPICategoryFileTimestamp"
      and .NSPrivacyAccessedAPITypeReasons == ["C617.1"]
    )
    and any(
      .NSPrivacyAccessedAPITypes[];
      .NSPrivacyAccessedAPIType
        == "NSPrivacyAccessedAPICategorySystemBootTime"
      and .NSPrivacyAccessedAPITypeReasons == ["35F9.1"]
    )
  ' >/dev/null ||
  fail "application privacy manifest does not match linked required-reason APIs"

if test -n "$dsym_path"; then
  test -d "$dsym_path" || fail "dSYM does not exist: $dsym_path"
  binary_uuid=$(xcrun dwarfdump --uuid "$binary_path" | awk '{ print $2 }')
  dsym_uuid=$(xcrun dwarfdump --uuid "$dsym_path" | awk '{ print $2 }')
  test "$binary_uuid" = "$dsym_uuid" ||
    fail "framework and dSYM UUIDs do not match"
fi

printf '%s\n' "iOS app-bundle verification passed: $app_path"
