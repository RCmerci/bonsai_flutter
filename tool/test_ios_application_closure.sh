#!/bin/sh

set -u

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
cd "$repository_root"

failures=0

fail() {
  printf '%s\n' "application iOS closure contract failure: $1" >&2
  failures=$((failures + 1))
}

require_file() {
  test -f "$1" || fail "missing $1"
}

require_text() {
  haystack=$1
  needle=$2
  label=$3
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null ||
    fail "$label does not contain: $needle"
}

reject_pattern() {
  haystack=$1
  pattern=$2
  label=$3
  if printf '%s' "$haystack" | grep -Ei -- "$pattern" >/dev/null; then
    fail "$label contains forbidden pattern: $pattern"
  fi
}

resolver=tool/ios/resolve_application_closure.sh
require_file "$resolver"
require_file tool/ios/closure_capabilities.lock
resolver_source=$(cat "$resolver")
require_text "$resolver_source" 'Extra C object files' "foreign-stub archive preflight"
require_text "$resolver_source" 'Unix platform APIs' "Unix capability preflight"
require_text \
  "$(cat tool/ios/closure_capabilities.lock)" \
  'ptime|Foreign_stubs|core|topkg-ios-cc' \
  "package-level ptime Topkg stub recipe"
require_text \
  "$(cat tool/ios/closure_capabilities.lock)" \
  'jst-config|Foreign_stubs|core|dune-ios-configure' \
  "target-generated platform configuration recipe"

fixture_root=tool/ios/fixtures/application-closure
fixture_dune=$(cat "$fixture_root/app.dune")
fixture_opam=$(cat "$fixture_root/bonsai_flutter_ios_closure_fixture.opam")
for library in \
  datascript-ocaml-native \
  datascript-ocaml-native.sqlite \
  uutf \
  uunf \
  uucp \
  astring
do
  require_text "$fixture_dune" "$library" "application closure fixture Dune libraries"
done
for package in \
  datascript_ocaml \
  persistent_sorted_set_ocaml \
  melange-edn-core \
  melange-edn-native \
  melange-transit-core \
  melange-transit-native \
  sqlite3
do
  require_text "$fixture_opam" "\"$package\"" "application closure fixture opam roots"
done
reject_pattern "$fixture_opam" '#main([^0-9a-f]|$)' "application closure fixture pins"

feature_source=$(cat bonsai_flutter_tool/lib/feature.ml)
require_text \
  "$feature_source" \
  'datascript-ocaml-native.sqlite' \
  "DataScript SQLite feature gate"
require_text "$feature_source" 'Pure_ocaml' "pure OCaml capability"
require_text "$feature_source" 'required cross-build recipe' "unsupported capability diagnostic"

sdk_source=$(cat bonsai_flutter_tool/lib/sdk.ml)
require_text "$sdk_source" 'resolve_application_closure.sh' "SDK application closure resolution"
require_text "$sdk_source" 'closure_digest' "SDK closure digest identity"
require_text "$sdk_source" 'features_digest' "SDK feature digest identity"
require_text "$sdk_source" '_build/ios/sdk-cache' "SDK cache separation"
require_text "$sdk_source" 'write_findlib_conf.sh' "SDK target findlib configuration"
require_text "$sdk_source" 'application_findlib_conf' "application target findlib configuration"

build_system=$(cat bonsai_flutter_tool/lib/build_system.ml)
require_text "$build_system" 'OCAMLFIND_CONF' "application Dune target compiler selection"

host_setup=$(cat tool/ios/setup_host_dependencies.sh)
require_text "$host_setup" 'APPLICATION_OPAM_FILE' "application opam root installation"
require_text "$host_setup" 'pin-depends' "pinned application dependency installation"
require_text \
  "$host_setup" \
  '--ignore-pin-depends' \
  "application pins must not follow upstream floating pin-depends"
require_text "$host_setup" 'HOST_OCAML_SWITCH' "host-only build dependency switch"

closure_builder=$(cat tool/ios/build_runtime_closure.sh)
require_text "$closure_builder" 'RUNTIME_CLOSURE_LOCK' "per-application closure build"
require_text "$closure_builder" 'target-package' "target-only package build selection"
require_text "$closure_builder" 'Pure_ocaml' "generic pure OCaml build path"
require_text \
  "$closure_builder" \
  'stage_host_ppx_metadata' \
  "host-only PPX metadata projection"

package_builder=$(cat tool/ios/build_runtime_package.sh)
require_text "$package_builder" 'detect_build_mechanism' "supported build mechanism detection"
require_text "$package_builder" 'foreign_stubs' "foreign-stub capability detection"
require_text "$package_builder" 'Extra C object files' "foreign-stub archive build safeguard"
require_text "$package_builder" 'unsupported capability' "pre-compilation capability failure"
require_text "$package_builder" 'required cross-build recipe' "cross-build recipe diagnostic"
require_text \
  "$package_builder" \
  'baseline_target_lib/ocaml' \
  "package build must expose only target closure plus iPhoneOS standard libraries"
require_text \
  "$package_builder" \
  'baseline_target_lib/seq/META' \
  "package build must expose the OCaml seq compatibility metadata"

findlib_writer=$(cat tool/ios/write_findlib_conf.sh)
require_text \
  "$findlib_writer" \
  'baseline_target_lib/ocaml' \
  "application findlib path must isolate the target closure"

closure_verifier=$(cat tool/ios/verify_runtime_closure.sh)
require_text "$closure_verifier" 'metadata.package-count' "lock-derived package count"
require_text "$closure_verifier" 'metadata.component-count' "lock-derived component count"
require_text "$closure_verifier" 'lock digest differs' "lock drift detection"
require_text "$closure_verifier" 'missing target artifact' "missing target artifact detection"
require_text \
  "$closure_verifier" \
  'outside the selected target closure' \
  "target verifier must reject baseline cache fallback"
require_text "$closure_verifier" 'verify_macho.sh' "Mach-O platform verification"
require_text "$closure_verifier" 'LC_BUILD_VERSION' "iPhoneOS platform evidence"
require_text "$closure_verifier" '-lsqlite3' "system SQLite link verification"
reject_pattern \
  "$closure_verifier" \
  'must contain exactly [0-9]+|= [0-9]+ \|\|' \
  "runtime closure verifier fixed counts"

runtime_lock=$(cat vendor/opam-ios/runtime-closure.lock)
toolchain_lock=$(cat tool/ios/toolchain.lock)
for package in \
  datascript-ocaml-native \
  datascript_ocaml \
  persistent_sorted_set_ocaml \
  melange-transit-native \
  melange-transit-core \
  melange-edn-native \
  melange-edn-core \
  sqlite3 \
  uutf \
  uunf \
  uucp
do
require_text "$runtime_lock" "$package" "pinned DataScript target closure"
done
require_text \
  "$runtime_lock" \
  'ppx_optcomp|v0.17.0|host-package|Host_only|' \
  "host-only PPX dependency lock"
require_text \
  "$runtime_lock" \
  'jst-config|v0.17.0|target-build|Foreign_stubs|' \
  "target build dependency lock"
require_text "$toolchain_lock" 'DATASCRIPT_OCAML_COMMIT' "DataScript source commit"
require_text "$toolchain_lock" 'PERSISTENT_SORTED_SET_COMMIT' "persistent set source commit"
require_text "$toolchain_lock" 'MELANGE_EDN_COMMIT' "EDN source commit"
require_text "$toolchain_lock" 'MELANGE_TRANSIT_COMMIT' "Transit source commit"
reject_pattern \
  "$runtime_lock\n$toolchain_lock" \
  '(refs/heads/main|#main([^0-9a-f]|$)|archive/main)' \
  "iOS source locks"

if test "$failures" -ne 0; then
  printf '%s\n' \
    "Application iOS closure contract failed with $failures violation(s)" >&2
  exit 1
fi

printf '%s\n' "Application iOS closure contract tests passed"
