#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
closure_lock="$repository_root/vendor/opam-ios/runtime-closure.lock"

fail() {
  printf '%s\n' "iOS runtime closure build failure: $1" >&2
  exit 1
}

test "$#" -eq 1 ||
  fail "usage: build_runtime_closure.sh iphoneos"

target=$1
test "$target" = iphoneos || fail "expected iphoneos"

awk -F '|' '!/^#/ && NF { print $1 }' "$closure_lock" |
  while IFS= read -r package_name; do
    "$script_directory/build_runtime_package.sh" "$target" "$package_name"
  done

printf '%s\n' "iOS $target runtime closure build passed"
