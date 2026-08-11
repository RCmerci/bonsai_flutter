#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

fail() {
  printf '%s\n' "iPhoneOS SDK build failure: $1" >&2
  exit 1
}

test "$#" -eq 2 || fail "usage: build-installed-sdk.sh OPAM_SWITCH OPAM_SWITCH_PREFIX"
SDK_OPAM_SWITCH=$1
selected_prefix=$2
test -n "${OPAM_SWITCH_PREFIX:-}" || fail "OPAM_SWITCH_PREFIX is missing"
test "$selected_prefix" = "$OPAM_SWITCH_PREFIX" ||
  fail "selected opam prefix differs from OPAM_SWITCH_PREFIX"

for command in awk cp curl dune find grep mkdir opam patch rg sed shasum sort tar xcrun; do
  command -v "$command" >/dev/null 2>&1 || fail "required command is unavailable: $command"
done

work_root="$PWD/.bonsai_flutter_ios_sdk"
stage_root="$work_root/stage"
target_lib="$stage_root/ios-sysroot/lib"
package_work_root="$work_root/packages"
mkdir -p "$target_lib" "$package_work_root"

export SDK_ASSET_ROOT=$script_directory
export SDK_OPAM_SWITCH
export SDK_PACKAGE_WORK_ROOT=$package_work_root
export RUNTIME_CLOSURE_LOCK="$script_directory/supported-closure.lock"
export TARGET_LIB=$target_lib

sh "$script_directory/build-runtime-closure.sh" iphoneos

framework_source_sha256='c20edc77779c24c411854a19d234887615a6ba0a352784d35a970fb0a7d148a5'
framework_archive_source="$script_directory/bonsai_flutter.tar.gz"
framework_archive="$work_root/bonsai_flutter.tar.gz"
framework_source="$work_root/framework-source"
framework_build="$work_root/framework-build"

if test ! -f "$framework_archive"; then
  test -f "$framework_archive_source" ||
    fail "opam did not provide the Bonsai Flutter source archive"
  actual_sha256=$(shasum -a 256 "$framework_archive_source" | cut -d ' ' -f 1)
  test "$actual_sha256" = "$framework_source_sha256" ||
    fail "Bonsai Flutter source checksum mismatch"
  cp "$framework_archive_source" "$framework_archive"
fi

if test ! -d "$framework_source"; then
  mkdir -p "$framework_source"
  tar -xzf "$framework_archive" --strip-components=1 -C "$framework_source"
fi

findlib_conf="$work_root/findlib.conf"
standard_target_lib="$OPAM_SWITCH_PREFIX/ios-sysroot/lib/ocaml"
{
  cat "$OPAM_SWITCH_PREFIX/lib/findlib.conf"
  awk \
    -v target_lib="$target_lib" \
    -v standard_target_lib="$standard_target_lib" '
      /^path\(ios\)/ {
        printf "path(ios) = \"%s:%s\"\n", target_lib, standard_target_lib
        next
      }
      /^destdir\(ios\)/ {
        printf "destdir(ios) = \"%s\"\n", target_lib
        next
      }
      { print }
    ' "$OPAM_SWITCH_PREFIX/lib/findlib.conf.d/ios.conf"
} > "$findlib_conf"

sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
sdk_root=$(xcrun --sdk iphoneos --show-sdk-path)
(
  cd "$framework_source"
  OPAMROOT=${OPAMROOT:-$(opam var root)} \
    OCAMLFIND_CONF="$findlib_conf" \
    BONSAI_FLUTTER_EMBED_OCAML=enabled \
    BONSAI_FLUTTER_APPLE_SDK_ROOT="$sdk_root" \
    SDK="$sdk_version" \
    VER=15.0 \
    opam exec --switch="$SDK_OPAM_SWITCH" -- \
    dune build \
      --build-dir="$framework_build" \
      --profile=release \
      -x ios \
      -p bonsai_flutter

)

framework_install_root="$framework_build/install/default.ios"
test -d "$framework_install_root/lib/bonsai_flutter" ||
  fail "Dune did not produce the iPhoneOS framework install tree"
cp -RL "$framework_install_root/." "$stage_root/ios-sysroot/"

printf '%s\n' "iPhoneOS installed SDK build passed"
