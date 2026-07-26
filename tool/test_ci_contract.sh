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

fixture_commands=$(dry_run_target protocol-fixtures-check)
require_text "$fixture_commands" "dune exec protocol/generator/generate_fixtures.exe -- --check" "protocol-fixtures-check"
require_text "$fixture_commands" "cd flutter/packages/bonsai_flutter && dart run tool/generate_input_fixtures.dart --check" "protocol-fixtures-check"

macos_commands=$(dry_run_target ci-macos)
require_text "$macos_commands" "make native-objects" "ci-macos"
require_text "$macos_commands" "flutter build macos --debug" "ci-macos"
require_text "$macos_commands" "flutter build macos --profile" "ci-macos"
require_text "$macos_commands" "flutter build macos --release" "ci-macos"
require_text "$macos_commands" "flutter test" "ci-macos"

native_object_commands=$(dry_run_target native-objects)
for example in counter gallery host_effects host_navigation navigation text_input todo; do
  require_file "examples/$example/ocaml/native_embed.ml"
  require_text \
    "$native_object_commands" \
    "examples/$example/ocaml/native_embed.exe.o" \
    "native-objects"
  example_pubspec=$(cat "examples/$example/flutter/pubspec.yaml")
  require_text \
    "$example_pubspec" \
    "_build/default/examples/$example/ocaml/native_embed.exe.o" \
    "$example Flutter build hook"
done
reject_text "$native_object_commands" "ocaml/ffi/native_counter_embed" "native-objects"

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

workflow_text=$(cat \
  .github/workflows/ocaml.yml \
  .github/workflows/flutter.yml \
  .github/workflows/macos.yml)

require_text "$workflow_text" "ocaml-compiler: 5.3.0" "workflows"
require_text "$workflow_text" "make ci-ocaml" "workflows"
require_text "$workflow_text" "make ci-flutter" "workflows"
require_text "$workflow_text" "make ci-macos" "workflows"
require_text "$workflow_text" "make ci-sanitizers" "workflows"
reject_text "$workflow_text" "continue-on-error: true" "workflows"

printf '%s\n' "CI contract tests passed"
