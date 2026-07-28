#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

fail() {
  printf '%s\n' "iOS native-object build failure: $1" >&2
  exit 1
}

test "$#" -eq 1 ||
  fail "usage: build_native_objects.sh iphoneos"

target=$1
test "$target" = iphoneos || fail "expected iphoneos"
expected_platform=IOS
minimum_version=13.0

switch="$repository_root/_build/ios/switches/$target"
opam_root="$repository_root/_build/ios/opam-root"
build_directory="$repository_root/_build/ios/app/$target-$minimum_version"
artifact_root="$repository_root/_build/native-artifacts"
sdk_version=$(xcrun --sdk "$target" --show-sdk-version)

"$script_directory/setup_toolchain.sh" "$target"
"$script_directory/setup_host_dependencies.sh" "$target"
"$script_directory/build_runtime_closure.sh" "$target"

targets=
for example in \
  counter \
  gallery \
  host_effects \
  host_navigation \
  mail \
  navigation \
  text_input \
  todo
do
  targets="$targets examples/$example/ocaml/native_embed.exe.o"
done
targets="$targets flutter/integration_test/ocaml/native_integration_embed.exe.o"

# BUILD_PATH_PREFIX_MAP removes checkout-specific paths from OCaml metadata.
OPAMROOT="$opam_root" \
  BUILD_PATH_PREFIX_MAP="$repository_root=." \
  OCAMLPARAM='_,keywords=4.14' \
  SDK="$sdk_version" \
  VER="$minimum_version" \
  BONSAI_FLUTTER_EMBED_OCAML=enabled \
  opam exec --switch="$switch" -- \
  dune build \
    --root="$repository_root" \
    --build-dir="$build_directory" \
    --profile=release \
    -j "${JOBS:-4}" \
    -x ios \
    $targets

for example in \
  counter \
  gallery \
  host_effects \
  host_navigation \
  mail \
  navigation \
  text_input \
  todo
do
  source_object="$build_directory/default.ios/examples/$example/ocaml/native_embed.exe.o"
  destination_directory="$artifact_root/$example/ios/$target/arm64"
  destination_object="$destination_directory/native_embed.exe.o"
  mkdir -p "$destination_directory"
  cp -f "$source_object" "$destination_object"
  "$script_directory/verify_complete_object.sh" \
    "$destination_object" \
    "$expected_platform" \
    "$minimum_version" \
    arm64
done

source_object="$build_directory/default.ios/flutter/integration_test/ocaml/native_integration_embed.exe.o"
destination_directory="$artifact_root/integration_test/ios/$target/arm64"
destination_object="$destination_directory/native_embed.exe.o"
mkdir -p "$destination_directory"
cp -f "$source_object" "$destination_object"
"$script_directory/verify_complete_object.sh" \
  "$destination_object" \
  "$expected_platform" \
  "$minimum_version" \
  arm64

printf '%s\n' \
  "iOS $target native-object build passed at minimum $minimum_version"
