#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
opam_root="$repository_root/_build/ios/opam-root"
host_switch="$repository_root/_build/ios/switches/iphoneos"
implementation="$script_directory/eio_worker_provider_spike.ml"
test_source="$script_directory/eio_worker_provider_spike_test.ml"
build_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai_flutter_eio_provider_spike.XXXXXX")
data_directory="$build_directory/provider-root/confined"

cleanup() {
  rm -rf "$build_directory"
}

trap cleanup EXIT HUP INT TERM

if test ! -f "$implementation"; then
  printf '%s\n' \
    "Eio Worker provider spike test failure: provider spike is not implemented" >&2
  exit 1
fi

mkdir -p "$data_directory"

compile() {
  OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
    ocamlfind ocamlopt \
    -package eio_posix \
    -I "$build_directory" \
    "$@"
}

compile \
  -c \
  -o "$build_directory/eio_worker_provider_spike.cmx" \
  "$implementation"
compile \
  -c \
  -o "$build_directory/eio_worker_provider_spike_test.cmx" \
  "$test_source"
compile \
  -linkpkg \
  -o "$build_directory/eio_worker_provider_spike_test.exe" \
  "$build_directory/eio_worker_provider_spike.cmx" \
  "$build_directory/eio_worker_provider_spike_test.cmx"

"$build_directory/eio_worker_provider_spike_test.exe" "$data_directory"
