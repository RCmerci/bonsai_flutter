#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
opam_root="$repository_root/_build/ios/opam-root"
host_switch="$repository_root/_build/ios/switches/iphoneos"
build_directory="$repository_root/_build/eio-worker-spike/macos-build"
output_directory="$repository_root/_build/eio-worker-spike/macos/arm64"
complete_object="$output_directory/eio_worker_backend_spike.o"
probe_executable="$output_directory/eio_worker_backend_spike_probe"

mkdir -p "$build_directory" "$output_directory"

compile() {
  OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
    ocamlfind ocamlopt \
    -thread \
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
  "$script_directory/eio_worker_backend_spike.mli"
compile \
  -c \
  -o "$build_directory/eio_worker_backend_spike.cmx" \
  "$script_directory/eio_worker_backend_spike.ml"
compile \
  -linkpkg \
  -output-complete-obj \
  -o "$complete_object" \
  "$build_directory/bounded_mailbox.cmx" \
  "$build_directory/eio_worker_backend_spike.cmx"

"$repository_root/tool/ios/verify_macho.sh" \
  "$complete_object" \
  MACOS \
  arm64 \
  26.0

ocaml_standard_library=$(
  OPAMROOT="$opam_root" \
    opam exec --switch="$host_switch" -- ocamlc -where
)
xcrun clang \
  -I "$ocaml_standard_library" \
  "$script_directory/probe_host.c" \
  "$complete_object" \
  -lpthread \
  -o "$probe_executable"

"$repository_root/tool/ios/verify_macho.sh" \
  "$probe_executable" \
  MACOS \
  arm64 \
  26.0
"$probe_executable"

object_size=$(stat -f '%z' "$complete_object")
printf '%s\n' "Eio Worker macOS complete-object spike passed"
printf '%s\n' "complete object: $complete_object"
printf '%s\n' "complete object bytes: $object_size"
