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
"$repository_root/tool/test_ios_sdk_layering.sh"

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

assert_consumer_root() {
  root=$1
  package=$2
  mode=$3
  feature=${4:-}

  for path in \
    "$root/dune-project" \
    "$root/.ocamlformat" \
    "$root/bonsai-flutter.sexp" \
    "$root/$package.opam" \
    "$root/$package.opam.locked"
  do
    require_file "$path"
  done

  config=$(cat "$root/bonsai-flutter.sexp")
  require_text "$config" '(lang 2)' "$root config"
  require_text "$config" "(name $package)" "$root package identity"
  require_text "$config" '(native_target ocaml/native_embed.exe.o)' "$root config"
  require_text "$config" "(mode $mode)" "$root config"
  if test -n "$feature"; then
    require_text "$config" "(features $feature)" "$root config"
  fi

  pubspec=$(cat "$root/flutter/pubspec.yaml")
  require_text "$pubspec" '# bonsai-flutter:begin packages' "$root pubspec"
  require_text "$pubspec" '# bonsai-flutter:end packages' "$root pubspec"
  require_text "$pubspec" '# bonsai-flutter:begin native-hook' "$root pubspec"
  require_text "$pubspec" '# bonsai-flutter:end native-hook' "$root pubspec"
  if test "$mode" = managed_adapter; then
    require_text "$pubspec" 'flutter_test:' "$root managed-host test dependency"
    require_text \
      "$(cat "$root/flutter/test/widget_test.dart")" \
      '// ignore_for_file: avoid_relative_lib_imports' \
      "$root generated widget test"
  fi
  reject_text "$pubspec" '../../../flutter/packages/' "$root pubspec"
  reject_text "$pubspec" '../../../_build/native-artifacts/' "$root pubspec"

  dune=$(cat "$root/ocaml/dune")
  require_text "$dune" '(name bonsai-flutter-macos)' "$root Dune aliases"
  require_text "$dune" '(name bonsai-flutter-ios)' "$root Dune aliases"
  require_text "$dune" '(deps native_embed.exe.o)' "$root Dune aliases"
}

assert_consumer_root examples/clock bonsai_flutter_clock_example managed_adapter
assert_consumer_root examples/counter bonsai_flutter_counter_example managed_adapter
assert_consumer_root examples/gallery bonsai_flutter_gallery custom
assert_consumer_root examples/host_effects bonsai_flutter_host_effects_example managed_adapter
assert_consumer_root examples/host_navigation bonsai_flutter_host_navigation_example managed_adapter
assert_consumer_root examples/mail bonsai_flutter_mail_example managed_adapter
assert_consumer_root examples/navigation bonsai_flutter_navigation_example managed_adapter
assert_consumer_root examples/network bonsai_flutter_network_example custom network
assert_consumer_root examples/sqlite_worker bonsai_flutter_sqlite_worker_example custom sqlite
assert_consumer_root examples/text_input bonsai_flutter_text_input_example managed_adapter
assert_consumer_root examples/todo bonsai_flutter_todo_example managed_adapter
integration_root=flutter/integration_test
for integration_path in \
  "$integration_root/dune-project" \
  "$integration_root/.ocamlformat" \
  "$integration_root/bonsai-flutter.sexp" \
  "$integration_root/bonsai_flutter_integration_test.opam" \
  "$integration_root/bonsai_flutter_integration_test.opam.locked"
do
  require_file "$integration_path"
done
integration_config=$(cat "$integration_root/bonsai-flutter.sexp")
require_text "$integration_config" '(lang 2)' "integration config"
require_text \
  "$integration_config" \
  '(name bonsai_flutter_integration_test)' \
  "integration package identity"
require_text "$integration_config" '(native_target ocaml/native_embed.exe.o)' "integration config"
require_text "$integration_config" '(mode custom)' "integration config"
require_text "$integration_config" '(features network sqlite)' "integration config"
integration_pubspec=$(cat "$integration_root/pubspec.yaml")
require_text "$integration_pubspec" '# bonsai-flutter:begin packages' "integration pubspec"
require_text "$integration_pubspec" '# bonsai-flutter:begin native-hook' "integration pubspec"
reject_text "$integration_pubspec" 'bonsai_flutter_sqlite_worker_example' "integration pubspec"

makefile=$(cat Makefile)
require_text "$makefile" 'BONSAI_FLUTTER :=' "Makefile local tool"
require_text "$makefile" '$(BONSAI_FLUTTER) exec' "Makefile consumer exec"
require_text "$makefile" '$(BONSAI_FLUTTER) build macos' "Makefile consumer macOS build"
require_text "$makefile" '$(BONSAI_FLUTTER) build ios' "Makefile consumer iOS build"
require_text "$makefile" 'ci-install-framework:' "Makefile framework installation"
require_text \
  "$makefile" \
  'ci-install-consumers: ci-install-framework' \
  "Makefile consumer installation"
require_text "$makefile" 'opam install . --yes' "Makefile framework installation"
require_text \
  "$makefile" \
  'opam install $(CONSUMER_ROOTS) --yes' \
  "Makefile consumer installation"
require_text "$makefile" 'ci-ocaml: ci-install-consumers' "Makefile OCaml CI"
require_text "$makefile" 'ci-flutter: ci-install-consumers' "Makefile Flutter CI"
require_text "$makefile" 'ci-macos: ci-ocaml' "Makefile macOS CI"
require_text \
  "$makefile" \
  'ci-install-ios-toolchain:' \
  "Makefile iPhoneOS toolchain installation"
require_text \
  "$makefile" \
  'ios-sdk-repository:' \
  "Makefile reproducible iPhoneOS SDK repository generation"
require_text \
  "$makefile" \
  'tool/ios/regenerate_sdk_repository.sh' \
  "Makefile reproducible iPhoneOS SDK repository generation"
require_text \
  "$makefile" \
  '$(BONSAI_FLUTTER) toolchain install iphoneos' \
  "Makefile iPhoneOS toolchain installation"
require_text \
  "$makefile" \
  '$(BONSAI_FLUTTER) toolchain verify iphoneos' \
  "Makefile iPhoneOS toolchain verification"
require_text "$makefile" 'ci-ios: ci-install-ios-toolchain' "Makefile iOS CI"
require_text \
  "$makefile" \
  'ci-ios-device: ci-install-consumers ci-install-ios-toolchain' \
  "Makefile physical-device CI"
reject_text "$makefile" 'stage_native_objects.sh' "Makefile"
reject_text "$makefile" 'build_native_objects.sh' "Makefile"
reject_pattern "$makefile" 'cd examples/[^ ]+/flutter && flutter (test|analyze|build)' "Makefile"
reject_text "$makefile" 'native-objects:' "Makefile"
reject_text "$makefile" 'integration-native-object:' "Makefile"
reject_text "$makefile" 'ios-device-native-objects:' "Makefile"
test ! -e tool/macos/stage_native_objects.sh || fail "obsolete macOS staging script exists"

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
expected_patch_files='./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_runtime_sdk/bonsai_flutter_ios_runtime_sdk.0.1.0~dev.4/files/patches/base-host-generator.patch
./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_runtime_sdk/bonsai_flutter_ios_runtime_sdk.0.1.0~dev.4/files/patches/datascript-system-sqlite.patch
./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_runtime_sdk/bonsai_flutter_ios_runtime_sdk.0.1.0~dev.4/files/patches/eio-posix-darwin-protocol-zero.patch
./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_runtime_sdk/bonsai_flutter_ios_runtime_sdk.0.1.0~dev.4/files/patches/eio-posix-darwin-socktype-hints.patch
./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_runtime_sdk/bonsai_flutter_ios_runtime_sdk.0.1.0~dev.4/files/patches/jst-config-host-discover.patch
./tool/ios/opam-repository/0.1.0/packages/bonsai_flutter_ios_runtime_sdk/bonsai_flutter_ios_runtime_sdk.0.1.0~dev.4/files/patches/mirage-crypto-rng-apple-entropy.patch
./tool/ios/opam-repository/0.1.0/packages/ocaml-ios64/ocaml-ios64.5.1.1/files/ocamlmklib-failsafe.patch
./tool/ios/opam-repository/0.1.0/packages/ocaml-ios64/ocaml-ios64.5.1.1/files/sys.patch
./vendor/opam-ios/ocaml-ios64.5.1.1/files/ocamlmklib-failsafe.patch
./vendor/patches/basement-macos.patch
./vendor/patches/ios/base-host-generator.patch
./vendor/patches/ios/datascript-system-sqlite.patch
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
  vendor/patches/ios/datascript-system-sqlite.patch \
  25671b3a84772c8a6b6c9fae3c8c2e0efa1b7d88c9ca2edb274b2ce40de481a4
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
  tool/ci/*.sh \
  tool/ios/*.sh)
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
    "$(cat bonsai_flutter.opam examples/network/bonsai_flutter_network_example.opam dune-project)" \
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
require_text "$flutter_commands" 'bonsai_flutter_tool/bin/main.exe exec --profile=debug -- flutter analyze' "ci-flutter"
require_text "$flutter_commands" "clock counter gallery host_effects host_navigation mail navigation network sqlite_worker text_input todo" "ci-flutter example matrix"

fixture_commands=$(dry_run_target protocol-fixtures-check)
require_text "$fixture_commands" "dune exec protocol/generator/generate_fixtures.exe -- --check" "protocol-fixtures-check"
require_text "$fixture_commands" "cd flutter/packages/bonsai_flutter && dart run tool/generate_input_fixtures.dart --check" "protocol-fixtures-check"

macos_commands=$(dry_run_target ci-macos)
require_text "$macos_commands" 'bonsai_flutter_tool/bin/main.exe build macos --profile debug' "ci-macos"
require_text "$macos_commands" 'bonsai_flutter_tool/bin/main.exe build macos --profile profile' "ci-macos"
require_text "$macos_commands" 'bonsai_flutter_tool/bin/main.exe build macos --profile release' "ci-macos"
require_text "$macos_commands" 'cd examples/network' "ci-macos network consumer"
require_text "$macos_commands" 'cd flutter/integration_test' "ci-macos integration consumer"
reject_text "$macos_commands" 'stage_native_objects.sh' "ci-macos"

ios_commands=$(dry_run_target ci-ios)
require_text "$ios_commands" 'bonsai_flutter_tool/bin/main.exe build ios --profile debug --no-codesign' "ci-ios"
require_text "$ios_commands" 'bonsai_flutter_tool/bin/main.exe build ios --profile profile --no-codesign' "ci-ios"
require_text "$ios_commands" 'bonsai_flutter_tool/bin/main.exe build ios --profile release --no-codesign' "ci-ios"
require_text "$ios_commands" 'cd examples/sqlite_worker' "ci-ios SQLite consumer"
require_text "$ios_commands" 'cd examples/network' "ci-ios Network consumer"
require_text "$ios_commands" 'cd flutter/integration_test' "ci-ios integration consumer"
reject_text "$ios_commands" 'build_native_objects.sh' "ci-ios"
reject_text "$ios_commands" 'SDK_OPAM_SWITCH' "ci-ios"
reject_text "$ios_commands" 'simulator' "ci-ios"

native_object_commands=$(make -n native-object EXAMPLE=mail)
require_text "$native_object_commands" 'cd examples/mail && ' "native-object"
require_text "$native_object_commands" 'bonsai_flutter_tool/bin/main.exe build macos --profile debug' "native-object"
reject_text "$native_object_commands" 'native_embed_debug' "native-object"
reject_text "$native_object_commands" 'native_embed_release' "native-object"

native_hook_source=$(tr -d '[:space:]' < flutter/packages/bonsai_flutter_native/hook/build.dart)
require_text "$native_hook_source" "'-framework','Security'" "iOS native hook"
require_text "$native_hook_source" "'link_system_sqlite3'" "conditional SQLite native hook"
require_text "$native_hook_source" "'-lsqlite3'" "conditional SQLite native hook"
ios_bundle_verifier_source=$(cat tool/ios/verify_app_bundle.sh)
require_text "$ios_bundle_verifier_source" "require-sqlite" "iOS app-bundle SQLite verifier mode"
require_text "$ios_bundle_verifier_source" "libsqlite3" "iOS app-bundle SQLite dependency verifier"

require_file examples/network/bonsai_flutter_network_example.opam
network_manifest=$(cat examples/network/bonsai_flutter_network_example.opam)
for dependency in \
  '"tls" {= "2.1.2"}' \
  '"tls-eio" {= "2.1.2"}' \
  '"ca-certs-nss" {= "3.126"}' \
  '"httpun-eio" {= "0.2.0"}' \
  '"httpun-ws" {= "0.2.0"}'
do
  require_text "$network_manifest" "$dependency" "network example opam dependencies"
done
network_source=$(cat examples/network/ocaml/*.ml examples/network/flutter/lib/*.dart)
reject_pattern "$network_source" 'allow_insecure|certificate[^[:space:]]*bypass|badCertificateCallback' "network example source"
network_dart_source=$(cat examples/network/flutter/lib/*.dart)
reject_pattern "$network_dart_source" 'SecurityContext|HttpClient|dart:io|dart:html|WebSocket[.]connect' "network Flutter source"

for example in clock counter gallery host_effects host_navigation mail navigation network sqlite_worker text_input todo; do
  require_file "examples/$example/ocaml/native_embed.ml"
  example_config=$(cat "examples/$example/bonsai-flutter.sexp")
  require_text "$example_config" '(lang 2)' "$example config"
  require_text "$example_config" '(native_target ocaml/native_embed.exe.o)' "$example config"
  example_pubspec=$(cat "examples/$example/flutter/pubspec.yaml")
  require_text "$example_pubspec" '# bonsai-flutter:begin packages' "$example Flutter package region"
  require_text "$example_pubspec" '# bonsai-flutter:begin native-hook' "$example Flutter native-hook region"
  require_text "$example_pubspec" 'native_artifact_root: ../_build/bonsai-flutter/artifacts/' "$example artifact root"
  reject_text "$example_pubspec" '../../../flutter/packages' "$example Flutter package paths"
  reject_text "$example_pubspec" '../../../_build/native-artifacts' "$example artifact root"
  require_text "$(cat "examples/$example/ocaml/dune")" '(name bonsai-flutter-macos)' "$example Dune aliases"
  require_text "$(cat "examples/$example/ocaml/dune")" '(name bonsai-flutter-ios)' "$example Dune aliases"
  require_file "examples/$example/flutter/ios/Runner/PrivacyInfo.xcprivacy"
done
reject_text "$(cat examples/mail/ocaml/dune)" 'bonsai_flutter_trace_' "Mail consumer closure"
reject_text "$(cat examples/mail/ocaml/dune)" 'native_embed_debug' "Mail consumer target"
reject_text "$(cat examples/mail/ocaml/dune)" 'native_embed_release' "Mail consumer target"

integration_pubspec=$(cat flutter/integration_test/pubspec.yaml)
require_text "$integration_pubspec" '# bonsai-flutter:begin packages' "integration package region"
require_text "$integration_pubspec" '# bonsai-flutter:begin native-hook' "integration native-hook region"
require_text "$integration_pubspec" 'native_artifact_root: ./_build/bonsai-flutter/artifacts/' "integration artifact root"
reject_text "$integration_pubspec" 'bonsai_flutter_sqlite_worker_example' "integration package ownership"
require_file flutter/integration_test/ocaml/native_embed.ml
integration_dune=$(cat flutter/integration_test/ocaml/dune)
integration_opam=$(cat flutter/integration_test/bonsai_flutter_integration_test.opam)
require_text "$(cat flutter/integration_test/dune-project)" '(allow_empty)' "integration package ownership"
require_text "$integration_dune" '(name bonsai-flutter-macos)' "integration Dune aliases"
require_text "$integration_dune" '(name integration_consumer_fixtures)' "integration-owned OCaml fixtures"
require_file flutter/integration_test/ocaml/sqlite_worker_example.ml
reject_pattern \
  "$integration_dune$integration_opam" \
  'bonsai_flutter_(counter|gallery|host_navigation|mail|sqlite_worker|text_input|todo)_example' \
  "integration sibling example dependencies"

readme=$(cat README.md)
require_text "$readme" '(mode managed_adapter)' "managed host documentation"
require_text "$readme" '(mode custom)' "custom host documentation"
require_text "$readme" 'bonsai-flutter exec --profile=debug -- flutter test --no-pub' "exec documentation"
reject_text "$readme" 'make native-objects' "public documentation"
packaging_documentation=$(cat docs/packaging.md)
require_text "$packaging_documentation" '# bonsai-flutter:begin packages' "pubspec ownership documentation"
reject_text "$packaging_documentation" 'make integration-native-object' "packaging documentation"

ios_device_commands=$(dry_run_target ci-ios-device)
require_text "$ios_device_commands" "IOS_DEVICE_ID" "ci-ios-device"
require_text "$ios_device_commands" 'bonsai_flutter_tool/bin/main.exe run ios --profile debug --device' "ci-ios-device"
require_text "$ios_device_commands" 'tool/ci/ios_device_preflight.sh' "ci-ios-device"
reject_text "$ios_device_commands" 'run_device_tests.sh' "ci-ios-device"
reject_text "$ios_device_commands" 'build_native_objects.sh' "ci-ios-device"

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

require_file tool/ci/install_ios_signing.sh
require_file tool/ci/ios_device_preflight.sh
require_file tool/ci/verify_ios_bundle.sh
require_file tool/ios/sdk_repository.lock
require_file tool/ios/regenerate_sdk_repository.sh
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

ios_bundle_verifier=$(cat tool/ios/verify_app_bundle.sh)
require_text \
  "$ios_bundle_verifier" \
  "NSPrivacyAccessedAPICategoryFileTimestamp" \
  "iOS bundle verifier"
require_text \
  "$ios_bundle_verifier" \
  "NSPrivacyAccessedAPICategorySystemBootTime" \
  "iOS bundle verifier"

printf '%s\n' "CI contract tests passed"
