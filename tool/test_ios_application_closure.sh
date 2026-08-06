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

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-flutter-host-setup-test.XXXXXX")
cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT HUP INT TERM

exercise_host_setup() {
  application_opam_file=$1
  fake_repository="$temporary_directory/repository"
  fake_bin="$temporary_directory/bin"
  fake_log="$temporary_directory/opam.log"
  rm -rf "$fake_repository" "$fake_bin"
  mkdir -p \
    "$fake_repository/tool/ios" \
    "$fake_repository/_build/ios/switches/host/_opam/bin" \
    "$fake_bin"
  cp tool/ios/setup_host_dependencies.sh "$fake_repository/tool/ios/"
  cp tool/ios/toolchain.lock "$fake_repository/tool/ios/"
  : >"$fake_repository/_build/ios/switches/host/_opam/bin/ocamlc"
  chmod +x "$fake_repository/_build/ios/switches/host/_opam/bin/ocamlc"
  cat >"$fake_bin/opam" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_OPAM_LOG"
EOF
  chmod +x "$fake_bin/opam"
  : >"$fake_log"

  if test -n "$application_opam_file"; then
    PATH="$fake_bin:$PATH" \
      FAKE_OPAM_LOG="$fake_log" \
      APPLICATION_OPAM_FILE="$application_opam_file" \
      BONSAI_FLUTTER_FEATURES=core,sqlite \
      SKIP_CLOSURE_VERIFY=true \
      "$fake_repository/tool/ios/setup_host_dependencies.sh" host
  else
    PATH="$fake_bin:$PATH" \
      FAKE_OPAM_LOG="$fake_log" \
      BONSAI_FLUTTER_FEATURES=core,sqlite \
      SKIP_CLOSURE_VERIFY=true \
      "$fake_repository/tool/ios/setup_host_dependencies.sh" host
  fi
}

resolver=tool/ios/resolve_application_closure.sh
require_file "$resolver"
require_file tool/ios/closure_capabilities.lock
resolver_source=$(cat "$resolver")
require_text "$resolver_source" 'Extra C object files' "foreign-stub archive preflight"
require_text "$resolver_source" 'Unix platform APIs' "Unix capability preflight"
require_text \
  "$resolver_source" \
  'system SQLite linker dependency' \
  "generic system SQLite capability discovery"
require_text \
  "$resolver_source" \
  '-lsqlite3' \
  "generic system SQLite linker inspection"
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
reject_pattern \
  "$feature_source" \
  'datascript' \
  "package-independent feature policy"
require_text "$feature_source" 'Pure_ocaml' "pure OCaml capability"
require_text "$feature_source" 'required cross-build recipe' "unsupported capability diagnostic"

sdk_source=$(cat bonsai_flutter_tool/lib/sdk.ml)
require_text "$sdk_source" 'resolve_application_closure.sh' "SDK application closure resolution"
require_text "$sdk_source" 'closure_digest' "SDK closure digest identity"
require_text "$sdk_source" 'features_digest' "SDK feature digest identity"
require_text "$sdk_source" '_build/ios/sdk-cache' "SDK cache separation"
require_text "$sdk_source" 'write_findlib_conf.sh' "SDK target findlib configuration"
require_text "$sdk_source" 'application_findlib_conf' "application target findlib configuration"
require_text \
  "$(cat bonsai_flutter_tool/bin/main.ml)" \
  '~project_root:(Some project_root)' \
  "SDK command application closure root"
reject_pattern \
  "$sdk_source" \
  'vendor/opam-ios/runtime-closure.lock' \
  "application-specific SDK verification"
require_text \
  "$sdk_source" \
  'requires an application project root' \
  "SDK missing application metadata diagnostic"

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
reject_pattern \
  "$host_setup" \
  'datascript|persistent.sorted.set|melange.edn|melange.transit' \
  "application-independent host dependency setup"

if exercise_host_setup "" >"$temporary_directory/missing-metadata.out" 2>&1; then
  fail "host dependency setup accepts a missing application opam metadata file"
else
  require_text \
    "$(cat "$temporary_directory/missing-metadata.out")" \
    'APPLICATION_OPAM_FILE is required' \
    "missing application metadata diagnostic"
fi

pure_application_opam="$temporary_directory/pure-application.opam"
cat >"$pure_application_opam" <<'EOF'
opam-version: "2.0"
name: "pure-application"
version: "0.1.0"
depends: [
  "ocaml" {= "5.1.1"}
  "dune" {= "3.23.1"}
  "astring" {= "0.8.5"}
]
EOF
if ! exercise_host_setup "$pure_application_opam" \
  >"$temporary_directory/pure-metadata.out" 2>&1
then
  fail "host dependency setup rejects application-owned pure OCaml metadata"
fi
host_setup_invocations=$(cat "$temporary_directory/opam.log")
require_text \
  "$host_setup_invocations" \
  "$pure_application_opam" \
  "application metadata dependency installation"
reject_pattern \
  "$host_setup_invocations" \
  'datascript|persistent.sorted.set|melange.edn|melange.transit' \
  "application-owned dependency installation"

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
  'datascript-ocaml-native|dev|target-package|System_sqlite|' \
  "DataScript SQLite capability is discovered from artifacts"
require_text \
  "$runtime_lock" \
  'sqlite3|5.4.0|target-package|System_sqlite|' \
  "SQLite package owns the system sqlite capability"
require_text \
  "$runtime_lock" \
  'ppx_optcomp|v0.17.0|host-package|Host_only|' \
  "host-only PPX dependency lock"
require_text \
  "$runtime_lock" \
  'jst-config|v0.17.0|target-build|Foreign_stubs|' \
  "target build dependency lock"
reject_pattern \
  "$toolchain_lock" \
  'DATASCRIPT|PERSISTENT_SORTED_SET|MELANGE_EDN|MELANGE_TRANSIT' \
  "application-independent toolchain lock"
reject_pattern \
  "$(cat tool/ios/closure_capabilities.lock)" \
  'datascript' \
  "package-independent capability registry"
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
