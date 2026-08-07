#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
fixture_root="$script_directory/fixtures/application-closure"
build_root="$repository_root/_build/ios/datascript-worker-device"
application_root="$build_root/application"
application_source="$application_root/app"
application_opam="$application_root/bonsai_flutter_ios_closure_fixture.opam"
closure_lock="$application_root/runtime-closure.lock"
opam_root="$repository_root/_build/ios/opam-root"
switch="$repository_root/_build/ios/switches/iphoneos"
flutter_root="$repository_root/examples/sqlite_worker/flutter"
staged_object="$repository_root/_build/native-artifacts/sqlite_worker/ios/iphoneos/arm64/native_embed.exe.o"

fail() {
  printf '%s\n' "DataScript Worker physical-device failure: $1" >&2
  exit 1
}

require_environment() {
  variable_name=$1
  eval "variable_value=\${$variable_name:-}"
  test -n "$variable_value" || fail "required environment variable is unset: $variable_name"
}

require_environment IOS_DEVICE_ID
require_environment IOS_DEVELOPMENT_TEAM
require_environment IOS_BUNDLE_IDENTIFIER
IOS_SIGNING_IDENTITY=${IOS_SIGNING_IDENTITY:-${IOS_DEVELOPMENT_SIGNING_IDENTITY:-Apple Development}}
export IOS_SIGNING_IDENTITY

"$repository_root/tool/ci/ios_device_preflight.sh" \
  "$IOS_DEVICE_ID"

mkdir -p "$application_source" "$(dirname -- "$staged_object")"
cp "$fixture_root/app.dune" "$application_source/dune"
cp "$fixture_root/datascript_fixture.ml" "$application_source/datascript_fixture.ml"
cp "$fixture_root/datascript_worker_probe.ml" "$application_source/datascript_worker_probe.ml"
cp "$fixture_root/datascript_worker_native_embed.ml" \
  "$application_source/datascript_worker_native_embed.ml"
cp "$fixture_root/bonsai_flutter_ios_closure_fixture.opam" "$application_opam"

APPLICATION_OPAM_FILE="$application_opam" \
BONSAI_FLUTTER_FEATURES=core,sqlite \
SKIP_CLOSURE_VERIFY=true \
  "$script_directory/setup_toolchain.sh" iphoneos
APPLICATION_OPAM_FILE="$application_opam" \
BONSAI_FLUTTER_FEATURES=core,sqlite \
SKIP_CLOSURE_VERIFY=true \
  "$script_directory/setup_host_dependencies.sh" iphoneos

OPAMROOT="$opam_root" \
HOST_OCAML_SWITCH="$switch" \
APPLICATION_OPAM_FILE="$application_opam" \
BONSAI_FLUTTER_FEATURES=core,sqlite \
  "$script_directory/resolve_application_closure.sh" \
    iphoneos \
    "$application_root" \
    "$closure_lock"

sdk_identity=$(
  "$script_directory/resolve_application_closure.sh" \
    --identity \
    --lock "$closure_lock" \
    --features core,sqlite
)
target_lib="$repository_root/_build/ios/sdk-cache/$sdk_identity/lib"
findlib_conf="$repository_root/_build/ios/sdk-cache/$sdk_identity/findlib.conf"
mkdir -p "$target_lib"
RUNTIME_CLOSURE_LOCK="$closure_lock" \
TARGET_LIB="$target_lib" \
BONSAI_FLUTTER_FEATURES=core,sqlite \
BONSAI_FLUTTER_CLOSURE_DIGEST="$sdk_identity" \
  "$script_directory/build_runtime_closure.sh" iphoneos
"$script_directory/write_findlib_conf.sh" "$target_lib" "$findlib_conf"

external_key="datascript-worker-device-$$"
external_root="$repository_root/external_apps/$external_key"
external_link="$external_root/app"
launcher_pid=
cleanup() {
  if test -n "$launcher_pid"; then
    kill "$launcher_pid" 2>/dev/null || true
    wait "$launcher_pid" 2>/dev/null || true
  fi
  test ! -L "$external_link" || unlink "$external_link"
  rmdir "$external_root" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$external_root"
ln -s "$application_source" "$external_link"

sdk_root=$(xcrun --sdk iphoneos --show-sdk-path)
sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
dune_build="$build_root/dune"
external_target="external_apps/$external_key/app/datascript_worker_native_embed.exe.o"
OPAMROOT="$opam_root" \
OCAMLFIND_CONF="$findlib_conf" \
BUILD_PATH_PREFIX_MAP="$application_root=." \
BONSAI_FLUTTER_APPLE_SDK_ROOT="$sdk_root" \
BONSAI_FLUTTER_EMBED_OCAML=enabled \
SDK="$sdk_version" \
VER=15.0 \
  opam exec --switch="$switch" -- \
    dune build \
      --root="$repository_root" \
      --build-dir="$dune_build" \
      --profile=release \
      -x ios \
      "$external_target"

complete_object="$dune_build/default.ios/$external_target"
"$script_directory/verify_macho.sh" "$complete_object" IOS arm64 15.0
nm -u "$complete_object" | grep -F '_sqlite3_open' >/dev/null ||
  fail "complete object does not reference the iPhoneOS system sqlite3 library"
cp -f "$complete_object" "$staged_object"

signing_xcconfig="$build_root/development-signing.xcconfig"
{
  printf '%s\n' "DEVELOPMENT_TEAM = $IOS_DEVELOPMENT_TEAM"
  printf '%s\n' 'CODE_SIGN_STYLE = Automatic'
  printf '%s\n' "CODE_SIGN_IDENTITY = $IOS_SIGNING_IDENTITY"
  printf '%s\n' "PRODUCT_BUNDLE_IDENTIFIER = $IOS_BUNDLE_IDENTIFIER"
} >"$signing_xcconfig"

(
  cd "$flutter_root"
  flutter pub get
  XCODE_XCCONFIG_FILE="$signing_xcconfig" \
    flutter build ios \
      --profile \
      --target lib/datascript_worker_device.dart
)

app="$flutter_root/build/ios/iphoneos/Runner.app"
test -d "$app" || fail "signed DataScript Worker application was not produced"
"$script_directory/verify_app_bundle.sh" "$app" require-sqlite
codesign --verify --deep --strict "$app"

"$repository_root/tool/ci/ios_device_preflight.sh" \
  "$IOS_DEVICE_ID"

xcrun devicectl device uninstall app \
  --device "$IOS_DEVICE_ID" \
  "$IOS_BUNDLE_IDENTIFIER" >/dev/null 2>&1 || true
xcrun devicectl device install app \
  --device "$IOS_DEVICE_ID" \
  "$app" >/dev/null

wait_for_marker() {
  log=$1
  marker=$2
  deadline=$(( $(date +%s) + 45 ))
  while ! grep -F -- "$marker" "$log" >/dev/null 2>&1; do
    if test "$(date +%s)" -ge "$deadline"; then
      sed -n '1,260p' "$log" >&2
      fail "timed out waiting for physical-device marker: $marker"
    fi
    sleep 1
  done
}

launch_and_wait() {
  log=$1
  expected=$2
  xcrun devicectl device process launch \
    --device "$IOS_DEVICE_ID" \
    --terminate-existing \
    --console \
    --timeout 60 \
    "$IOS_BUNDLE_IDENTIFIER" >"$log" 2>&1 &
  launcher_pid=$!
  wait_for_marker "$log" "$expected"
  wait_for_marker "$log" 'BONSAI_DATASCRIPT_WORKER_SHUTDOWN'
  wait_for_marker "$log" 'BONSAI_DATASCRIPT_HOST_RUNTIME_DISPOSED'
  kill "$launcher_pid" 2>/dev/null || true
  wait "$launcher_pid" 2>/dev/null || true
  launcher_pid=
}

launch_and_wait "$build_root/first-launch.log" 'BONSAI_DATASCRIPT_WORKER_PERSISTED'
launch_and_wait "$build_root/second-launch.log" 'BONSAI_DATASCRIPT_WORKER_RESTORED'

printf '%s\n' \
  "DataScript Worker signed physical-iPhone persistence slice passed: $IOS_DEVICE_ID"
