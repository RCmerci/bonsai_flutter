#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

fail() {
  printf '%s\n' "ci contract failure: $1" >&2
  exit 1
}

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
require_text "$flutter_commands" "dart run tool/generate_input_fixtures.dart --check" "ci-flutter"
require_text "$flutter_commands" "dart run ffigen --config ffigen.yaml" "ci-flutter"
require_text "$flutter_commands" "git diff --exit-code" "ci-flutter"
require_text \
  "$flutter_commands" \
  "dart format --output=none --set-exit-if-changed benchmark integration_test lib test" \
  "ci-flutter"
require_text "$flutter_commands" "cd flutter/integration_test && flutter analyze" "ci-flutter"

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
reject_text "$ios_commands" "simulator" "ci-ios"

ios_device_commands=$(dry_run_target ci-ios-device)
require_text "$ios_device_commands" "IOS_DEVICE_ID" "ci-ios-device"
require_text "$ios_device_commands" "tool/ios/run_device_tests.sh" "ci-ios-device"
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
  "tool/macos/stage_native_objects.sh examples" \
  "native-objects"
for example in counter gallery host_effects host_navigation navigation text_input todo; do
  require_file "examples/$example/ocaml/native_embed.ml"
  require_text \
    "$native_object_commands" \
    "examples/$example/ocaml/native_embed.exe.o" \
    "native-objects"
  example_pubspec=$(cat "examples/$example/flutter/pubspec.yaml")
  require_text \
    "$example_pubspec" \
    "native_artifact_root: ../../../_build/native-artifacts/$example/" \
    "$example Flutter build hook"
  require_text \
    "$example_pubspec" \
    "require_ocaml_backend: true" \
    "$example Flutter build hook"
  macos_debug_config=$(cat "examples/$example/flutter/macos/Runner/Configs/Debug.xcconfig")
  macos_release_config=$(cat "examples/$example/flutter/macos/Runner/Configs/Release.xcconfig")
  require_text "$macos_debug_config" "ARCHS = arm64" "$example macOS Debug configuration"
  require_text "$macos_release_config" "ARCHS = arm64" "$example macOS Release configuration"
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
  "tool/macos/stage_native_objects.sh integration" \
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
  bonsai_flutter_counter_example \
  bonsai_flutter_gallery \
  bonsai_flutter_host_effects_example \
  bonsai_flutter_host_navigation_example \
  bonsai_flutter_navigation_example \
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

require_text "$workflow_text" "ocaml-compiler: 5.3.0" "workflows"
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
reject_text "$ios_workflow_text" "_build/default" "iOS workflows"
reject_text "$ios_device_workflow_text" "pull_request_target" "physical-device workflow"
reject_text "$ios_device_workflow_text" "pull_request:" "physical-device workflow"
reject_pattern \
  "$ios_workflow_text" \
  "simulator.{0,40}(physical|device)|physical.{0,40}simulator" \
  "iOS workflows"

printf '%s\n' "CI contract tests passed"
