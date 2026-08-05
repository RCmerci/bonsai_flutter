#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
opam_root="$repository_root/_build/ios/opam-root"
host_switch="$repository_root/_build/ios/switches/iphoneos"
build_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai_flutter_eio_worker_spike.XXXXXX")

cleanup() {
  rm -rf "$build_directory"
}

trap cleanup EXIT HUP INT TERM

implementation="$script_directory/eio_worker_backend_spike.ml"
interface="$script_directory/eio_worker_backend_spike.mli"

if test ! -f "$interface" || test ! -f "$implementation"; then
  printf '%s\n' "Eio Worker spike test failure: backend entrypoint is not implemented" >&2
  exit 1
fi

compile() {
  OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
    ocamlfind ocamlopt \
    -package eio_posix \
    -I "$build_directory" \
    "$@"
}

compile \
  -c \
  -o "$build_directory/bounded_mailbox.cmi" \
  "$repository_root/ocaml/runtime/bounded_mailbox.mli"
compile \
  -c \
  -o "$build_directory/bounded_mailbox.cmx" \
  "$repository_root/ocaml/runtime/bounded_mailbox.ml"
compile \
  -c \
  -o "$build_directory/eio_worker_backend_spike.cmi" \
  "$interface"
compile \
  -c \
  -o "$build_directory/eio_worker_backend_spike.cmx" \
  "$implementation"
compile \
  -c \
  -o "$build_directory/eio_worker_backend_spike_test.cmx" \
  "$script_directory/eio_worker_backend_spike_test.ml"
compile \
  -linkpkg \
  -o "$build_directory/eio_worker_backend_spike_test.exe" \
  "$build_directory/bounded_mailbox.cmx" \
  "$build_directory/eio_worker_backend_spike.cmx" \
  "$build_directory/eio_worker_backend_spike_test.cmx"

"$build_directory/eio_worker_backend_spike_test.exe"
"$script_directory/test_macos_provider_spike.sh"
