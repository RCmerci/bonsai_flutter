#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

# shellcheck source=tool/ios/toolchain.lock
. "$script_directory/toolchain.lock"

opam_root="$repository_root/_build/ios/opam-root"
switch_root="$repository_root/_build/ios/switches"
source_root="$repository_root/_build/ios/sources/host"
basement_source="$source_root/basement"
basement_patch="$repository_root/vendor/patches/basement-macos.patch"

fail() {
  printf '%s\n' "iOS host dependency setup failure: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

opam_command() {
  OPAMROOT="$opam_root" opam "$@"
}

switch_path() {
  printf '%s/%s\n' "$switch_root" "$1"
}

prepare_basement_source() {
  mkdir -p "$source_root"
  if test ! -d "$basement_source/.git"; then
    git clone https://github.com/janestreet/basement.git "$basement_source"
    git -C "$basement_source" checkout --detach "$BASEMENT_COMMIT"
    git -C "$basement_source" apply "$basement_patch"
  fi

  resolved_commit=$(git -C "$basement_source" rev-parse HEAD)
  test "$resolved_commit" = "$BASEMENT_COMMIT" ||
    fail "Basement checkout does not match $BASEMENT_COMMIT"
  git -C "$basement_source" apply --reverse --check "$basement_patch" ||
    fail "Basement portability patch is not applied exactly"

  unexpected_changes=$(
    git -C "$basement_source" status --porcelain |
      grep -Ev '^ M src/(blocking_mutex\.h|stubs\.c)$' || true
  )
  test -z "$unexpected_changes" ||
    fail "managed Basement checkout has unexpected local changes"
}

install_for_switch() {
  logical_name=$1
  switch=$(switch_path "$logical_name")
  test -x "$switch/_opam/bin/ocamlc" ||
    fail "missing $logical_name switch; run tool/ios/setup_toolchain.sh first"

  opam_command pin add \
    --switch="$switch" \
    basement \
    "file://$basement_source" \
    --with-version="$BONSAI_VERSION" \
    --no-action \
    --yes

  OCAMLPARAM='_,keywords=4.14' \
    opam_command install \
      --switch="$switch" \
      "dune.$DUNE_VERSION" \
      "ocamlfind.$OCAMLFIND_VERSION" \
      "bonsai.$BONSAI_VERSION" \
      "core.$BONSAI_VERSION" \
      --yes

  OPAMROOT="$opam_root" \
    HOST_OCAML_SWITCH="$switch" \
    "$script_directory/verify_runtime_closure.sh"

  if test "$logical_name" != host; then
    "$script_directory/stage_host_metadata.sh" "$logical_name"
  fi
}

require_command git
require_command grep
require_command opam

requested_target=${1:-all}
case "$requested_target" in
  host | iphoneos)
    prepare_basement_source
    install_for_switch "$requested_target"
    ;;
  all)
    prepare_basement_source
    install_for_switch host
    install_for_switch iphoneos
    ;;
  *)
    fail "expected host, iphoneos, or all"
    ;;
esac

printf '%s\n' "iOS $requested_target host dependency setup passed"
