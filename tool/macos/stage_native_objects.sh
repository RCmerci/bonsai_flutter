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
  variant=${3:-}
  destination_directory="$artifact_root/$artifact_name/macos/arm64"
  if test -n "$variant"; then
    destination_directory="$destination_directory/$variant"
  fi
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

test "$#" -ge 1 && test "$#" -le 2 ||
  fail "usage: tool/macos/stage_native_objects.sh <examples|integration|example NAME>"

case "$1" in
  examples)
    test "$#" -eq 1 ||
      fail "examples does not accept an additional argument"
    for example in \
      clock \
      counter \
      gallery \
      host_effects \
      host_navigation \
      mail \
      navigation \
      text_input \
      todo
    do
      if test "$example" = mail; then
        stage_object \
          mail \
          "$source_root/examples/mail/ocaml/native_embed_debug.exe.o" \
          debug
        stage_object \
          mail \
          "$source_root/examples/mail/ocaml/native_embed_release.exe.o" \
          release
      else
        stage_object \
          "$example" \
          "$source_root/examples/$example/ocaml/native_embed.exe.o"
      fi
    done
    ;;
  integration)
    test "$#" -eq 1 ||
      fail "integration does not accept an additional argument"
    stage_object \
      integration_test \
      "$source_root/flutter/integration_test/ocaml/native_integration_embed.exe.o"
    ;;
  example)
    test "$#" -eq 2 ||
      fail "example requires an example name"
    case "$2" in
      mail)
        stage_object \
          mail \
          "$source_root/examples/mail/ocaml/native_embed_debug.exe.o" \
          debug
        stage_object \
          mail \
          "$source_root/examples/mail/ocaml/native_embed_release.exe.o" \
          release
        ;;
      clock | counter | gallery | host_effects | host_navigation | navigation | text_input | todo)
        stage_object \
          "$2" \
          "$source_root/examples/$2/ocaml/native_embed.exe.o"
        ;;
      *)
        fail "unknown example: $2"
        ;;
    esac
    ;;
  *)
    fail "expected examples, integration, or example NAME"
    ;;
esac

printf '%s\n' "macOS native-object staging passed"
