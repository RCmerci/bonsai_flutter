#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

fail() {
  printf '%s\n' "ci contract failure: $1" >&2
  exit 1
}

"$repository_root/tool/test_ios_deployment_target_contract.sh"
"$repository_root/tool/test_network_ios_contract.sh"

require_file() {
  test -f "$1" || fail "missing $1"
}

require_text() {
  haystack=$1
  needle=$2
  label=$3
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null ||
    fail "$label does not contain: $needle"
}

reject_text() {
  haystack=$1
  needle=$2
  label=$3
  if printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null; then
    fail "$label contains forbidden text: $needle"
  fi
}

reject_pattern() {
  haystack=$1
  pattern=$2
  label=$3
  if printf '%s' "$haystack" | grep -Ei -- "$pattern" >/dev/null; then
    fail "$label contains forbidden pattern: $pattern"
  fi
}

require_exact_installed_version() {
  package=$1
  expected=$2
  actual=$(opam list --installed --short --columns=version "$package" 2>/dev/null) ||
    fail "$package is not installed"
  test "$actual" = "$expected" ||
    fail "$package version is $actual, expected $expected"
}

require_opam_release_source() {
  package=$1
  version=$2
  metadata=$(opam show --raw "$package.$version" 2>/dev/null) ||
    fail "unable to read opam metadata for $package.$version"
  require_text \
    "$metadata" \
    "https://github.com/janestreet/$package/archive/refs/tags/$version.tar.gz" \
    "$package source metadata"
}

require_sha256() {
  path=$1
  expected=$2
  actual=$(shasum -a 256 "$path" | awk '{ print $1 }')
  test "$actual" = "$expected" ||
    fail "$path SHA-256 is $actual, expected $expected"
}

test "$(ocamlc -version)" = "5.1.1" ||
  fail "OCaml version is $(ocamlc -version), expected 5.1.1"

require_exact_installed_version base v0.17.3
require_exact_installed_version bonsai v0.17.0
require_exact_installed_version core v0.17.2
require_exact_installed_version incr_dom v0.17.0
require_exact_installed_version incremental v0.17.0
require_exact_installed_version sqlite3 5.4.0
require_exact_installed_version tls 2.1.2
require_exact_installed_version tls-eio 2.1.2
require_exact_installed_version ca-certs-nss 3.126
require_exact_installed_version httpun 0.2.0
require_exact_installed_version httpun-eio 0.2.0
require_exact_installed_version httpun-ws 0.2.0
require_exact_installed_version gluten-eio 0.5.2
require_exact_installed_version virtual_dom v0.17.0
for package in bonsai incr_dom incremental virtual_dom; do
  require_opam_release_source "$package" v0.17.0
done
require_opam_release_source core v0.17.2
require_opam_release_source base v0.17.3

unexpected_release_train_versions=$(
  opam list --installed --short --columns=name,version |
    awk \
      '$2 ~ /^v0[.]/ &&
       $1 != "ocaml-compiler-libs" &&
       $2 !~ /^v0[.]17([.-]|$)/ { print }'
)
test -z "$unexpected_release_train_versions" ||
  fail "installed Jane Street release-train packages are not v0.17.x:
$unexpected_release_train_versions"

flutter_metadata=$(flutter --version --machine)
require_text "$flutter_metadata" '"frameworkVersion": "3.44.8"' "Flutter metadata"
require_text \
  "$flutter_metadata" \
  '"frameworkRevision": "058e0af2c2b57e369d905a03ac9748b0ebf543c6"' \
  "Flutter metadata"

upstream_baseline=$(cat docs/upstream-baseline.md)
for version in \
  "OCaml | 5.1.1" \
  "Bonsai | v0.17.0" \
  "Core | v0.17.2" \
  "Base | v0.17.3" \
  058e0af2c2b57e369d905a03ac9748b0ebf543c6
do
  require_text "$upstream_baseline" "$version" "upstream baseline"
done

patch_files=$(
  find . \
    -path './.git' -prune -o \
    -path './_build' -prune -o \
    -path './_build-v017' -prune -o \
    -type f \( -name '*.patch' -o -name '*.diff' \) -print |
    LC_ALL=C sort
)
expected_patch_files='./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_sdk/bonsai_flutter_ios_sdk.0.1.0~dev/files/patches/base-host-generator.patch
./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_sdk/bonsai_flutter_ios_sdk.0.1.0~dev/files/patches/eio-posix-darwin-protocol-zero.patch
./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_sdk/bonsai_flutter_ios_sdk.0.1.0~dev/files/patches/eio-posix-darwin-socktype-hints.patch
./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_sdk/bonsai_flutter_ios_sdk.0.1.0~dev/files/patches/jst-config-host-discover.patch
./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_sdk/bonsai_flutter_ios_sdk.0.1.0~dev/files/patches/mirage-crypto-rng-apple-entropy.patch
./tool/ios/opam-repository/0.1.0/packages/ocaml-ios64/ocaml-ios64.5.1.1/files/ocamlmklib-failsafe.patch
./tool/ios/opam-repository/0.1.0/packages/ocaml-ios64/ocaml-ios64.5.1.1/files/sys.patch
./vendor/opam-ios/ocaml-ios64.5.1.1/files/ocamlmklib-failsafe.patch
./vendor/patches/basement-macos.patch
./vendor/patches/ios/base-host-generator.patch
./vendor/patches/ios/eio-posix-darwin-protocol-zero.patch
./vendor/patches/ios/eio-posix-darwin-socktype-hints.patch
./vendor/patches/ios/jst-config-host-discover.patch
./vendor/patches/ios/mirage-crypto-rng-apple-entropy.patch'
test "$patch_files" = "$expected_patch_files" ||
  fail "upstream patch allowlist changed:
$patch_files"
require_sha256 \
  vendor/opam-ios/ocaml-ios64.5.1.1/files/ocamlmklib-failsafe.patch \
  2e087a1cccc6514af07559a688ffc17c651a2bb5b2a67d115cc28051f2e89767
require_sha256 \
  vendor/patches/basement-macos.patch \
  1c97bd1e3ad6eeefe30fce6a81a06ed4685fdef95efb53e67cd9389b6201327b
require_sha256 \
  vendor/patches/ios/base-host-generator.patch \
  e919f3c5ec1e6a546a6e499ed262d309055fd0c856d7c216d3609b7d64ca47b5
require_sha256 \
  vendor/patches/ios/eio-posix-darwin-protocol-zero.patch \
  b6a158f56db6bc1c1e19ad2412625f2d7941a5004274e3a45fe58f6c89e5b963
require_sha256 \
  vendor/patches/ios/eio-posix-darwin-socktype-hints.patch \
  8b5eb1ecc716afeac54f6ebc0792f14df5107dbdac5ebb81da3ea0a31e187e17
require_sha256 \
  vendor/patches/ios/jst-config-host-discover.patch \
  d1d9fbbf8df8f8e315fad1a834352a5a80e948e62012a104d5362461f195df78
require_sha256 \
  vendor/patches/ios/mirage-crypto-rng-apple-entropy.patch \
  898002b98bddd3a6f212441a7bba32a45ad26f0cb40ab175b2fe0f762e4adea2

if find vendor \
  -type d \
  \( \
    -name bonsai -o \
    -name incremental -o \
    -name incr_dom -o \
    -name flutter \
  \) |
  grep . >/dev/null; then
  fail "vendor contains a forbidden upstream source overlay"
fi

dependency_control_text=$(cat \
  bonsai_flutter.opam \
  bonsai_flutter_test.opam \
  dune-project \
  .github/workflows/*.yml \
  tool/ci/*.sh \
  tool/ios/*.sh \
  tool/macos/*.sh)
require_text \
  "$dependency_control_text" \
  'sqlite3' \
  "dependency controls"
require_text \
  "$dependency_control_text" \
  'eio_posix' \
  "dependency controls"
for dependency in httpun-eio tls-eio ca-certs-nss; do
  reject_text \
    "$(cat bonsai_flutter.opam)" \
    "$dependency" \
    "core package dependency controls"
done
for dependency in piaf eio-ssl cohttp-eio openssl-sys-ios; do
  reject_text \
    "$(cat bonsai_flutter.opam bonsai_flutter_network_example.opam dune-project)" \
    "$dependency" \
    "network dependency controls"
done
if find ocaml -type f -print | grep -F '/worker_http/' >/dev/null; then
  fail "framework still contains the legacy worker_http library"
fi

dune_package_metadata() {
  awk -v RS='' -v package_name="$1" \
    'index($0, "(name " package_name ")") { print; exit }' \
    dune-project
}

bonsai_flutter_dune_package=$(dune_package_metadata bonsai_flutter)
bonsai_flutter_test_dune_package=$(dune_package_metadata bonsai_flutter_test)
reject_text \
  "$bonsai_flutter_dune_package" \
  '(sqlite3 ' \
  "bonsai_flutter dune package dependencies"
require_text \
  "$bonsai_flutter_test_dune_package" \
  '(sqlite3 (= 5.4.0))' \
  "bonsai_flutter_test dune package dependencies"
reject_text \
  "$(cat bonsai_flutter.opam)" \
  '"sqlite3"' \
  "bonsai_flutter opam dependencies"
require_text \
  "$(cat bonsai_flutter_test.opam)" \
  '"sqlite3" {= "5.4.0"}' \
  "bonsai_flutter_test opam dependencies"
require_text \
  "$(cat vendor/opam-ios/runtime-closure.lock)" \
  'sqlite3|5.4.0|target-package|System_sqlite|dune|https://github.com/mmottl/sqlite3-ocaml/releases/download/5.4.0/sqlite3-5.4.0.tbz|f0069532f78ac24f16d79262af01434952d0481f8bf80ae541dff4a56cc4e9ff|sqlite3|-' \
  "iOS runtime closure lock"
require_text \
  "$(cat tool/ios/toolchain.lock)" \
  "SQLITE3_VERSION='5.4.0'" \
  "iOS toolchain lock"
require_text \
  "$(cat tool/ios/toolchain.lock)" \
  "EIO_VERSION='1.2'" \
  "iOS Eio toolchain lock"
require_text \
  "$(cat vendor/opam-ios/runtime-closure.lock)" \
  'eio_posix|1.2|target-package|Filesystem|dune|https://github.com/ocaml-multicore/eio/releases/download/v1.2/eio-1.2.tbz|3792e912bd8d494bb2e38f73081825e4d212b1970cf2c1f1b2966caa9fd6bc40|eio_posix|' \
  "iOS Eio runtime closure lock"
ios_closure_verifier=$(cat tool/ios/verify_runtime_closure.sh)
require_text \
  "$ios_closure_verifier" \
  'metadata package-count' \
  "lock-derived iOS closure package count"
require_text \
  "$ios_closure_verifier" \
  'metadata component-count' \
  "lock-derived iOS closure component count"
require_text "$ios_closure_verifier" 'System_sqlite)' "iOS SQLite capability gate"
require_text "$ios_closure_verifier" 'Filesystem)' "iOS filesystem capability gate"
reject_text \
  "$(cat tool/ios/setup_host_dependencies.sh)" \
  'sqlite3.$SQLITE3_VERSION' \
  "application-owned iOS host SQLite dependency setup"
require_text \
  "$(cat tool/ios/setup_host_dependencies.sh)" \
  'eio_posix.$EIO_VERSION' \
  "iOS host Eio dependency setup"
runtime_events_installer=$(cat \
  vendor/opam-ios/ocaml-ios64.5.1.1/files/install.sh)
require_text \
  "$runtime_events_installer" \
  'runtime_events' \
  "iOS OCaml 5 runtime-events metadata staging"
require_text \
  "$runtime_events_installer" \
  'ios-sysroot/lib/ocaml/runtime_events/' \
  "iOS OCaml 5 runtime-events target archive staging"
ios_toolchain_setup=$(cat tool/ios/setup_toolchain.sh)
require_text \
  "$ios_toolchain_setup" \
  'recipe_identity="$OCAML_IOS_RECIPE_REVISION-$IOS_DEPLOYMENT_TARGET"' \
  "iOS toolchain recipe identity"
require_text \
  "$ios_toolchain_setup" \
  'conf-ios.4' \
  "iOS deployment-target toolchain reinstall"
require_text \
  "$ios_toolchain_setup" \
  'miphoneos-version-min=$IOS_DEPLOYMENT_TARGET' \
  "iOS cross-compiler deployment-target verification"
ios_metadata_stager=$(cat tool/ios/stage_host_metadata.sh)
require_text \
  "$ios_metadata_stager" \
  'target_standard_library="$target_lib/ocaml"' \
  "iOS target standard-library staging"
require_text \
  "$ios_metadata_stager" \
  "-name '*.cmxa'" \
  "iOS target standard-library native archives"
ios_runtime_package_builder=$(cat tool/ios/build_runtime_package.sh)
require_text \
  "$ios_runtime_package_builder" \
  'libsqlite3_stubs.a' \
  "iOS target SQLite stubs"
require_text \
  "$ios_runtime_package_builder" \
  '-lsqlite3' \
  "iOS target system SQLite dependency"
require_text \
  "$ios_runtime_package_builder" \
  'test ! -f "$target_package_root/libsqlite3.a"' \
  "iOS bundled SQLite rejection"
reject_pattern \
  "$dependency_control_text" \
  'opam[[:space:]]+pin[[:space:]]+add[[:space:]]+(bonsai|incremental|incr_dom)' \
  "dependency controls"
reject_pattern \
  "$dependency_control_text" \
  'file://[^[:space:]]*(bonsai|incremental|incr_dom)' \
  "dependency controls"

runtime_source=$(cat \
  ocaml/runtime/*.ml \
  ocaml/runtime/*.mli \
  ocaml/ffi/*.ml \
  ocaml/ffi/*.mli \
  flutter/packages/bonsai_flutter/lib/src/runtime/*.dart \
  flutter/packages/bonsai_flutter/lib/src/root/*.dart)
reject_pattern \
  "$runtime_source" \
  'Time_source[.]Private|Obj[.]magic' \
  "runtime source"
reject_pattern \
  "$runtime_source" \
  'Timer[.]periodic|scheduleForcedFrame|scheduleWarmUpFrame|forceFrames|Ticker[.]forceFrames' \
  "runtime source"

dry_run_target() {
  target=$1
  if ! output=$(make -n "$target" 2>&1); then
    printf '%s\n' "$output" >&2
    fail "make target $target is unavailable"
  fi
  printf '%s' "$output"
}

ocaml_commands=$(dry_run_target ci-ocaml)
require_text "$ocaml_commands" "opam install . --deps-only --with-test" "ci-ocaml"
require_text "$ocaml_commands" "dune build @all" "ci-ocaml"
require_text "$ocaml_commands" "dune runtest" "ci-ocaml"
require_text "$ocaml_commands" "dune build @fmt" "ci-ocaml"
require_text "$ocaml_commands" "generate.exe -- --check" "ci-ocaml"
require_text "$ocaml_commands" "generate_fixtures.exe -- --check" "ci-ocaml"
require_text "$ocaml_commands" "dune build --profile release ocaml/bench/runtime_bench.exe" "ci-ocaml"

flutter_commands=$(dry_run_target ci-flutter)
require_text "$flutter_commands" "dart format --output=none --set-exit-if-changed" "ci-flutter"
require_text "$flutter_commands" "flutter analyze" "ci-flutter"
require_text "$flutter_commands" "flutter test" "ci-flutter"
require_text \
  "$flutter_commands" \
  "find test -type f -name '*_test.dart'" \
  "ci-flutter example test discovery"
require_text "$flutter_commands" "dart run tool/generate_input_fixtures.dart --check" "ci-flutter"
require_text "$flutter_commands" "dart run ffigen --config ffigen.yaml" "ci-flutter"
require_text "$flutter_commands" "git diff --exit-code" "ci-flutter"
require_text \
  "$flutter_commands" \
  "dart format --output=none --set-exit-if-changed benchmark integration_test lib test" \
  "ci-flutter"
require_text "$flutter_commands" "cd flutter/integration_test && flutter analyze" "ci-flutter"
require_text "$flutter_commands" "clock counter todo text_input host_effects navigation gallery host_navigation mail sqlite_worker network" "ci-flutter network example"

fixture_commands=$(dry_run_target protocol-fixtures-check)
require_text "$fixture_commands" "dune exec protocol/generator/generate_fixtures.exe -- --check" "protocol-fixtures-check"
require_text "$fixture_commands" "cd flutter/packages/bonsai_flutter && dart run tool/generate_input_fixtures.dart --check" "protocol-fixtures-check"

macos_commands=$(dry_run_target ci-macos)
require_text "$macos_commands" "make native-objects" "ci-macos"
require_text "$macos_commands" "flutter build macos --debug" "ci-macos"
require_text "$macos_commands" "flutter build macos --profile" "ci-macos"
require_text "$macos_commands" "flutter build macos --release" "ci-macos"
require_text "$macos_commands" "make integration-native-object" "ci-macos"
require_text "$macos_commands" "flutter test" "ci-macos"
require_text "$macos_commands" "examples/network/flutter" "ci-macos network example"

ios_device_object_commands=$(dry_run_target ios-device-native-objects)
require_text \
  "$ios_device_object_commands" \
  "tool/ios/build_native_objects.sh iphoneos" \
  "ios-device-native-objects"
ios_commands=$(dry_run_target ci-ios)
require_text "$ios_commands" "make ios-device-native-objects" "ci-ios"
require_text "$ios_commands" "flutter build ios --debug --no-codesign" "ci-ios"
require_text "$ios_commands" "flutter build ios --profile --no-codesign" "ci-ios"
require_text "$ios_commands" "flutter build ios --release --no-codesign" "ci-ios"
require_text "$ios_commands" "tool/ios/verify_app_bundle.sh" "ci-ios"
require_text "$ios_commands" "examples/sqlite_worker/flutter" "ci-ios"
require_text "$ios_commands" "examples/network/flutter" "ci-ios network example"
require_text "$ios_commands" "verify_app_bundle.sh" "ci-ios SQLite bundle audit"
require_text "$ios_commands" "require-sqlite" "ci-ios SQLite bundle audit"
reject_text "$ios_commands" "simulator" "ci-ios"

native_hook_source=$(tr -d '[:space:]' < flutter/packages/bonsai_flutter_native/hook/build.dart)
require_text "$native_hook_source" "'-framework','Security'" "iOS native hook"
require_text "$native_hook_source" "'link_system_sqlite3'" "conditional SQLite native hook"
require_text "$native_hook_source" "'-lsqlite3'" "conditional SQLite native hook"
ios_probe_source=$(cat tool/ios/build_probe.sh)
require_text "$ios_probe_source" "-framework Security" "iOS cross probe"
ios_bundle_verifier_source=$(cat tool/ios/verify_app_bundle.sh)
require_text \
  "$ios_bundle_verifier_source" \
  "mach_absolute_time" \
  "iOS app-bundle privacy verifier"
require_text \
  "$ios_bundle_verifier_source" \
  "require-sqlite" \
  "iOS app-bundle SQLite verifier mode"
require_text \
  "$ios_bundle_verifier_source" \
  "libsqlite3" \
  "iOS app-bundle SQLite dependency verifier"
require_text \
  "$ios_bundle_verifier_source" \
  "sqlite3_" \
  "iOS app-bundle SQLite export rejection"

ios_device_commands=$(dry_run_target ci-ios-device)
require_text "$ios_device_commands" "IOS_DEVICE_ID" "ci-ios-device"
require_text "$ios_device_commands" "tool/ios/run_device_tests.sh" "ci-ios-device"
require_text \
  "$ios_device_commands" \
  "tool/network_spike/test_ios_device_probe.sh" \
  "ci-ios-device network probe"
require_text "$ios_device_commands" "--debug" "ci-ios-device"
require_text "$ios_device_commands" "--profile" "ci-ios-device"
require_text "$ios_device_commands" "--release" "ci-ios-device"
reject_text "$ios_device_commands" "_build/default" "ci-ios-device"
reject_pattern \
  "$ios_device_commands" \
  "simulator.{0,40}(physical|device)|physical.{0,40}simulator" \
  "ci-ios-device"

native_object_commands=$(dry_run_target native-objects)
require_text \
  "$native_object_commands" \
  'tool/macos/stage_native_objects.sh "26.0" "arm64" examples' \
  "native-objects"
single_native_object_commands=$(make -n native-object EXAMPLE=mail)
require_text \
  "$single_native_object_commands" \
  'tool/macos/stage_native_objects.sh "26.0" "arm64" example mail' \
  "native-object"
require_text \
  "$native_object_commands" \
  "examples/network/ocaml/native_embed.exe.o" \
  "native-objects network example"
network_stager=$(cat tool/macos/stage_native_objects.sh)
require_text "$network_stager" "libgmp.a" "network macOS static GMP staging"
require_text "$network_stager" "nm -u" "network macOS unresolved symbol audit"
require_text "$network_stager" "openssl" "network macOS prohibited TLS audit"
require_file bonsai_flutter_network_example.opam
require_file examples/network/README.md
require_file examples/network/ocaml/network_example.ml
require_file examples/network/ocaml/network_service.ml
require_file examples/network/ocaml/network_http.ml
require_file examples/network/ocaml/network_websocket.ml
require_file examples/network/ocaml/network_smoke_cli.ml
require_file examples/network/ocaml/native_embed.ml
require_file examples/network/flutter/lib/main.dart
require_file examples/network/flutter/test/network_host_test.dart
require_file examples/network/flutter/ios/Runner/PrivacyInfo.xcprivacy
network_readme=$(cat examples/network/README.md)
require_text \
  "$network_readme" \
  "dune exec examples/network/ocaml/network_smoke_cli.exe" \
  "network manual public smoke documentation"
reject_text \
  "$(dry_run_target ci-ocaml)$(dry_run_target ci-flutter)$(dry_run_target ci-macos)" \
  "network_smoke_cli" \
  "network public smoke CI isolation"
network_manifest=$(cat bonsai_flutter_network_example.opam)
for dependency in \
  '"tls" {= "2.1.2"}' \
  '"tls-eio" {= "2.1.2"}' \
  '"ca-certs-nss" {= "3.126"}' \
  '"httpun" {= "0.2.0"}' \
  '"httpun-eio" {= "0.2.0"}' \
  '"httpun-ws" {= "0.2.0"}' \
  '"gluten-eio" {= "0.5.2"}'
do
  require_text "$network_manifest" "$dependency" "network example opam dependencies"
done
network_source=$(cat examples/network/ocaml/*.ml examples/network/flutter/lib/*.dart)
reject_pattern \
  "$network_source" \
  'allow_insecure|certificate[^[:space:]]*bypass|badCertificateCallback' \
  "network example source"
network_dart_source=$(cat examples/network/flutter/lib/*.dart)
reject_pattern \
  "$network_dart_source" \
  'SecurityContext|HttpClient|dart:io|dart:html|WebSocket[.]connect' \
  "network Flutter source"
network_debug_entitlements=$(cat examples/network/flutter/macos/Runner/DebugProfile.entitlements)
network_release_entitlements=$(cat examples/network/flutter/macos/Runner/Release.entitlements)
require_text \
  "$network_debug_entitlements" \
  "com.apple.security.network.client" \
  "network macOS Debug entitlements"
require_text \
  "$network_release_entitlements" \
  "com.apple.security.network.client" \
  "network macOS Release entitlements"
require_file examples/clock/README.md
require_file examples/clock/ocaml/clock.ml
require_file examples/clock/ocaml/clock.mli
require_file examples/clock/ocaml/dune
require_file examples/clock/ocaml/native_embed.ml
require_file examples/clock/flutter/lib/main.dart
require_file examples/clock/flutter/pubspec.yaml
require_file ocaml/trace/trace.mli
require_file ocaml/trace/debug/trace.ml
require_file ocaml/trace/release/trace.ml
trace_library_dune=$(cat ocaml/trace/dune)
trace_debug_library_dune=$(cat ocaml/trace/debug/dune)
trace_release_library_dune=$(cat ocaml/trace/release/dune)
reject_text "$trace_library_dune" "(public_name" "internal trace virtual library"
reject_text "$trace_debug_library_dune" "(public_name" "internal trace debug library"
reject_text "$trace_release_library_dune" "(public_name" "internal trace release library"
native_backend_test_source=$(cat ocaml/test/native_backend_tests.ml)
for example_marker in \
  "Mail.component" \
  "mail-debug" \
  "Bonsai Mail" \
  "mail-list-page" \
  "mail-row-1"
do
  reject_text \
    "$native_backend_test_source" \
    "$example_marker" \
    "generic native backend test"
done
reject_pattern \
  "$native_backend_test_source" \
  '(^|[^[:alnum:]_])mail([^[:alnum:]_]|$)' \
  "generic native backend test"
native_backend_test_dune=$(
  sed -n '/(name native_backend_tests)/,/(name mail_example_tests)/p' ocaml/test/dune
)
reject_text \
  "$native_backend_test_dune" \
  "bonsai_flutter_mail_example" \
  "generic native backend test dependencies"
for example in clock counter gallery host_effects host_navigation mail navigation network sqlite_worker text_input todo; do
  require_file "examples/$example/ocaml/native_embed.ml"
  if test "$example" = mail; then
    require_text \
      "$native_object_commands" \
      "examples/mail/ocaml/native_embed_debug.exe.o" \
      "native-objects"
    require_text \
      "$native_object_commands" \
      "examples/mail/ocaml/native_embed_release.exe.o" \
      "native-objects"
  else
    require_text \
      "$native_object_commands" \
      "examples/$example/ocaml/native_embed.exe.o" \
      "native-objects"
  fi
  example_pubspec=$(cat "examples/$example/flutter/pubspec.yaml")
  require_text \
    "$example_pubspec" \
    "native_artifact_root: ../../../_build/native-artifacts/$example/" \
    "$example Flutter build hook"
  require_text \
    "$example_pubspec" \
    "require_ocaml_backend: true" \
    "$example Flutter build hook"
  require_text \
    "$example_pubspec" \
    "macos_deployment_target: '26.0'" \
    "$example Flutter build hook"
  if test "$example" = sqlite_worker; then
    require_text \
      "$example_pubspec" \
      "link_system_sqlite3: true" \
      "$example Flutter build hook"
  else
    reject_text \
      "$example_pubspec" \
      "link_system_sqlite3" \
      "$example Flutter build hook"
  fi
  macos_config=$(cat "examples/$example/flutter/macos/Runner/Configs/BonsaiFlutter.xcconfig")
  require_text "$macos_config" "MACOSX_DEPLOYMENT_TARGET = 26.0" "$example macOS configuration"
  require_text "$macos_config" "ARCHS = arm64" "$example macOS configuration"
  for configuration in Debug Release AppInfo; do
    macos_consumer=$(cat "examples/$example/flutter/macos/Runner/Configs/$configuration.xcconfig")
    require_text \
      "$macos_consumer" \
      '#include "BonsaiFlutter.xcconfig"' \
      "$example macOS $configuration configuration"
  done
  reject_text \
    "$(cat "examples/$example/flutter/macos/Runner.xcodeproj/project.pbxproj")" \
    "MACOSX_DEPLOYMENT_TARGET = 10.15" \
    "$example macOS project"
  require_file "examples/$example/flutter/ios/Runner/PrivacyInfo.xcprivacy"
  ios_project=$(cat "examples/$example/flutter/ios/Runner.xcodeproj/project.pbxproj")
  require_text \
    "$ios_project" \
    "PrivacyInfo.xcprivacy in Resources" \
    "$example iOS project"
done
integration_object_commands=$(dry_run_target integration-native-object)
require_text \
  "$integration_object_commands" \
  'tool/macos/stage_native_objects.sh "26.0" "arm64" integration' \
  "integration-native-object"

integration_pubspec=$(cat flutter/integration_test/pubspec.yaml)
require_text \
  "$integration_pubspec" \
  "native_artifact_root: ../../_build/native-artifacts/integration_test/" \
  "integration Flutter build hook"
require_text \
  "$integration_pubspec" \
  "require_ocaml_backend: true" \
  "integration Flutter build hook"
require_text \
  "$integration_pubspec" \
  "macos_deployment_target: '26.0'" \
  "integration Flutter build hook"
require_text \
  "$integration_pubspec" \
  "link_system_sqlite3: true" \
  "integration Flutter build hook"
require_file flutter/integration_test/ios/Runner/PrivacyInfo.xcprivacy
integration_ios_project=$(
  cat flutter/integration_test/ios/Runner.xcodeproj/project.pbxproj
)
require_text \
  "$integration_ios_project" \
  "PrivacyInfo.xcprivacy in Resources" \
  "integration iOS project"

ffi_dune=$(cat ocaml/ffi/dune)
for example_library in \
  bonsai_flutter_clock_example \
  bonsai_flutter_counter_example \
  bonsai_flutter_gallery \
  bonsai_flutter_host_effects_example \
  bonsai_flutter_host_navigation_example \
  bonsai_flutter_mail_example \
  bonsai_flutter_navigation_example \
  bonsai_flutter_sqlite_worker_example \
  bonsai_flutter_text_input_example \
  bonsai_flutter_todo_example
do
  reject_text "$ffi_dune" "$example_library" "generic FFI library"
done

sanitizer_commands=$(dry_run_target ci-sanitizers)
require_text "$sanitizer_commands" "-fsanitize=address,undefined" "ci-sanitizers"
require_text "$sanitizer_commands" "ASAN_OPTIONS=detect_leaks=1" "ci-sanitizers"
require_text "$sanitizer_commands" "binary_codec_test.dart" "ci-sanitizers"
require_text "$sanitizer_commands" "native_resource_store_test.dart" "ci-sanitizers"

require_file .github/workflows/ocaml.yml
require_file .github/workflows/flutter.yml
require_file .github/workflows/macos.yml
require_file .github/workflows/ios.yml
require_file .github/workflows/ios-device.yml
require_file tool/ci/install_ios_signing.sh
require_file tool/ci/ios_device_preflight.sh
require_file tool/ci/verify_ios_bundle.sh
require_file tool/ios/run_device_tests.sh
ios_device_preflight=$(cat tool/ci/ios_device_preflight.sh)
require_text \
  "$ios_device_preflight" \
  ".result.passcodeRequired == false" \
  "currently unlocked physical iOS device preflight"
ios_signing_installer=$(cat tool/ci/install_ios_signing.sh)
require_text \
  "$ios_signing_installer" \
  "Library/Developer/Xcode/UserData/Provisioning Profiles" \
  "iOS signing installer"

ios_device_runner=$(cat tool/ios/run_device_tests.sh)
require_text \
  "$ios_device_runner" \
  "XCODE_XCCONFIG_FILE" \
  "physical-device runner"
require_text \
  "$ios_device_runner" \
  "flutter build ios \\" \
  "physical-device runner"
require_text \
  "$ios_device_runner" \
  "--no-codesign" \
  "physical-device runner"

ios_bundle_verifier=$(cat tool/ios/verify_app_bundle.sh)
require_text \
  "$ios_bundle_verifier" \
  "NSPrivacyAccessedAPICategoryFileTimestamp" \
  "iOS bundle verifier"
require_text \
  "$ios_bundle_verifier" \
  "NSPrivacyAccessedAPICategorySystemBootTime" \
  "iOS bundle verifier"

workflow_text=$(cat \
  .github/workflows/ocaml.yml \
  .github/workflows/flutter.yml \
  .github/workflows/macos.yml \
  .github/workflows/ios.yml \
  .github/workflows/ios-device.yml)

ios_workflow_text=$(cat \
  .github/workflows/ios.yml \
  .github/workflows/ios-device.yml)
ios_hosted_workflow_text=$(cat .github/workflows/ios.yml)
ios_device_workflow_text=$(cat .github/workflows/ios-device.yml)

require_text "$workflow_text" "ocaml-compiler: 5.1.1" "workflows"
require_text "$workflow_text" "make ci-ocaml" "workflows"
require_text "$workflow_text" "make ci-flutter" "workflows"
require_text "$workflow_text" "make ci-macos" "workflows"
require_text "$workflow_text" "make ci-sanitizers" "workflows"
require_text "$ios_workflow_text" "make ci-ios" "iOS workflows"
require_text "$ios_workflow_text" "make ci-ios-device" "iOS workflows"
require_text "$ios_hosted_workflow_text" "runs-on: macos-26" "hosted iOS workflow"
require_text \
  "$ios_device_workflow_text" \
  "runs-on: [self-hosted, macOS, arm64, ios-device]" \
  "physical-device workflow"
require_text \
  "$ios_device_workflow_text" \
  "environment: ios-device" \
  "physical-device workflow"
require_text \
  "$ios_device_workflow_text" \
  "group: ios-device-hardware" \
  "physical-device workflow"
require_text \
  "$ios_device_workflow_text" \
  "tool/ci/install_ios_signing.sh cleanup" \
  "physical-device workflow"
require_text \
  "$ios_device_workflow_text" \
  "if: always()" \
  "physical-device workflow"
reject_text "$workflow_text" "continue-on-error: true" "workflows"
reject_text "$workflow_text" "OCAMLPARAM" "workflows"
reject_text "$workflow_text" "janestreet-bleeding" "workflows"
reject_text "$workflow_text" "ocaml-compiler: 5.3.0" "workflows"
reject_text "$ios_workflow_text" "_build/default" "iOS workflows"
reject_text "$ios_device_workflow_text" "pull_request_target" "physical-device workflow"
reject_text "$ios_device_workflow_text" "pull_request:" "physical-device workflow"
reject_pattern \
  "$ios_workflow_text" \
  "simulator.{0,40}(physical|device)|physical.{0,40}simulator" \
  "iOS workflows"

printf '%s\n' "CI contract tests passed"
