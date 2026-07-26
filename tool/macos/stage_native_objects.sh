#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
source_root=${DUNE_BUILD_DIRECTORY:-"$repository_root/_build"}/default
artifact_root="$repository_root/_build/native-artifacts"

fail() {
  printf '%s\n' "macOS native-object staging failure: $1" >&2
  exit 1
}

stage_object() {
  artifact_name=$1
  source_object=$2
  destination_directory="$artifact_root/$artifact_name/macos/arm64"
  destination_object="$destination_directory/native_embed.exe.o"

  test -f "$source_object" ||
    fail "complete object is missing: $source_object"
  mkdir -p "$destination_directory"
  cp -f "$source_object" "$destination_object"
  "$repository_root/tool/ios/verify_complete_object.sh" \
    "$destination_object" \
    MACOS \
    26.0 \
    arm64
}

test "$#" -eq 1 ||
  fail "usage: tool/macos/stage_native_objects.sh <examples|integration>"

case "$1" in
  examples)
    for example in \
      counter \
      gallery \
      host_effects \
      host_navigation \
      navigation \
      text_input \
      todo
    do
      stage_object \
        "$example" \
        "$source_root/examples/$example/ocaml/native_embed.exe.o"
    done
    ;;
  integration)
    stage_object \
      integration_test \
      "$source_root/flutter/integration_test/ocaml/native_integration_embed.exe.o"
    ;;
  *)
    fail "expected examples or integration"
    ;;
esac

printf '%s\n' "macOS native-object staging passed"
