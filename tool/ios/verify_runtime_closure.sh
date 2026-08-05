#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
closure_lock="$repository_root/vendor/opam-ios/runtime-closure.lock"

fail() {
  printf '%s\n' "iOS runtime closure verification failure: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

require_command awk
require_command cmp
require_command comm
require_command grep
require_command mktemp
require_command opam
require_command sed
require_command sort
require_command tr
require_command wc

host_switch=${HOST_OCAML_SWITCH:-}
test -n "$host_switch" ||
  fail "HOST_OCAML_SWITCH must name the pinned native OCaml 5.1.1 switch"
test -f "$closure_lock" || fail "missing closure lock: $closure_lock"

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-flutter-ios-closure.XXXXXX")
locked_components="$temporary_directory/locked-components"
resolved_components="$temporary_directory/resolved-components"
locked_packages="$temporary_directory/locked-packages"
resolved_packages="$temporary_directory/resolved-packages"
component_difference="$temporary_directory/component-difference"

cleanup() {
  rm -f \
    "$locked_components" \
    "$resolved_components" \
    "$locked_packages" \
    "$resolved_packages" \
    "$component_difference"
  rmdir "$temporary_directory"
}

trap cleanup EXIT HUP INT TERM

awk -F '|' '
  /^#/ || NF == 0 { next }
  NF != 6 { exit 2 }
  $1 !~ /^[A-Za-z0-9_.+-]+$/ { exit 3 }
  $3 != "target" && $3 != "dual" && $3 != "target-build" { exit 4 }
  $4 !~ /^https:\/\// { exit 5 }
  $5 !~ /^[0-9a-f]{64}$/ { exit 6 }
  {
    print $1 "|" $2
    if ($3 != "target-build") {
      count = split($6, components, ",")
      for (component_index = 1; component_index <= count; component_index++) {
        print components[component_index] > components_file
      }
    }
  }
' components_file="$locked_components" "$closure_lock" >"$locked_packages" ||
  fail "closure lock has an invalid row"

test "$(wc -l <"$locked_packages" | tr -d ' ')" = 57 ||
  fail "closure lock must contain 56 runtime and one target-build package"
test "$(sort -u "$locked_packages" | wc -l | tr -d ' ')" = 57 ||
  fail "closure lock contains a duplicate source package"
test "$(sort -u "$locked_components" | wc -l | tr -d ' ')" = 90 ||
  fail "closure lock must contain exactly 90 package findlib components"

opam exec --switch="$host_switch" -- \
  ocamlfind query -recursive -p-format \
  bonsai \
  bonsai.driver \
  incr_dom.ui_incr \
  incr_dom.ui_time_source \
  virtual_dom.ui_effect \
  core \
  sqlite3 \
  eio_posix \
  threads \
  unix |
  grep -Ev '^(runtime_events|seq|threads(\.posix)?|unix)$' |
  sort -u >"$resolved_components"
sort -u "$locked_components" -o "$locked_components"

if ! comm -3 "$locked_components" "$resolved_components" \
  >"$component_difference"; then
  fail "could not compare findlib components"
fi
if test -s "$component_difference"; then
  sed -n '1,40p' "$component_difference" >&2
  fail "locked findlib components differ from the resolved runtime closure"
fi

while IFS='|' read -r package_name package_version; do
  resolved_version=$(
    opam show \
      --switch="$host_switch" \
      --field=version \
      "$package_name"
  )
  printf '%s|%s\n' "$package_name" "$resolved_version"
  test "$resolved_version" = "$package_version" ||
    fail "$package_name resolves to $resolved_version, expected $package_version"
done <"$locked_packages" >"$resolved_packages"

sort -u "$resolved_packages" -o "$resolved_packages"
sort -u "$locked_packages" -o "$locked_packages"
cmp -s "$locked_packages" "$resolved_packages" ||
  fail "locked package versions differ from the host switch"

printf '%s\n' \
  "iOS runtime closure verification passed: 56 runtime packages, 90 components, 1 target-build package"
