#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
source_root=${DUNE_BUILD_DIRECTORY:-"$repository_root/_build"}/default
artifact_root="$repository_root/_build/native-artifacts"

test "$#" -ge 3 && test "$#" -le 4 || {
  printf '%s\n' \
    "macOS native-object staging failure: usage: tool/macos/stage_native_objects.sh <minimum-version> <architecture> <examples|integration|example NAME>" >&2
  exit 1
}

minimum_version=$1
architecture=$2
shift 2

fail() {
  printf '%s\n' "macOS native-object staging failure: $1" >&2
  exit 1
}

stage_object() {
  artifact_name=$1
  source_object=$2
  variant=${3:-}
  destination_directory="$artifact_root/$artifact_name/macos/$architecture"
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
    "$minimum_version" \
    "$architecture"
}

stage_network_object() {
  source_object=$1
  command -v pkg-config >/dev/null 2>&1 ||
    fail "pkg-config is required to locate the static GMP archive"
  gmp_libdir=$(pkg-config --variable=libdir gmp 2>/dev/null) ||
    fail "pkg-config could not locate GMP"
  gmp_archive="$gmp_libdir/libgmp.a"
  test -f "$gmp_archive" ||
    fail "static GMP archive is missing: $gmp_archive"
  merge_directory=$(mktemp -d)
  merged_object="$merge_directory/native_embed.exe.o"
  sdk_root=$(xcrun --sdk macosx --show-sdk-path)
  clang \
    -r \
    -target "${architecture}-apple-macos${minimum_version}" \
    -mmacosx-version-min="$minimum_version" \
    -isysroot "$sdk_root" \
    "$source_object" \
    "$gmp_archive" \
    -o "$merged_object"
  if nm -u "$merged_object" | grep -Ei 'gmp|openssl|libssl|libcrypto|securetransport'; then
    fail "network complete object has unresolved GMP or prohibited TLS symbols"
  fi
  stage_object network "$merged_object"
  rm -rf "$merge_directory"
}

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
      network \
      sqlite_worker \
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
      elif test "$example" = network; then
        stage_network_object \
          "$source_root/examples/network/ocaml/native_embed.exe.o"
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
      network)
        stage_network_object \
          "$source_root/examples/network/ocaml/native_embed.exe.o"
        ;;
      clock | counter | gallery | host_effects | host_navigation | navigation | sqlite_worker | text_input | todo)
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
