#!/bin/sh

set -u

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

failures=0

fail() {
  printf '%s\n' "DataScript Worker contract failure: $1" >&2
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

reject_text() {
  haystack=$1
  needle=$2
  label=$3
  if printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null; then
    fail "$label unexpectedly contains: $needle"
  fi
}

require_before() {
  haystack=$1
  earlier=$2
  later=$3
  label=$4
  earlier_line=$(printf '%s\n' "$haystack" | grep -n -F -- "$earlier" | head -1 | cut -d: -f1)
  later_line=$(printf '%s\n' "$haystack" | grep -n -F -- "$later" | head -1 | cut -d: -f1)
  if test -z "$earlier_line" || test -z "$later_line" || \
    test "$earlier_line" -ge "$later_line"
  then
    fail "$label does not place $earlier before $later"
  fi
}

fixture=tool/ios/fixtures/application-closure
for path in \
  "$fixture/datascript_worker_probe.ml" \
  "$fixture/datascript_worker_native_embed.ml" \
  tool/ios/test_datascript_worker_device.sh
do
  require_file "$path"
done

fixture_dune=$(cat "$fixture/app.dune")
for library in \
  bonsai_flutter_sqlite_worker_example \
  datascript-ocaml-native \
  datascript-ocaml-native.sqlite \
  uutf \
  uunf \
  uucp
do
  require_text "$fixture_dune" "$library" "DataScript Worker fixture libraries"
done
require_text "$fixture_dune" 'datascript_worker_native_embed' "DataScript Worker fixture executable"

probe=$(cat "$fixture/datascript_worker_probe.ml" 2>/dev/null)
require_text "$probe" 'Datascript_sqlite.open_session' "DataScript SQLite open"
require_text "$probe" 'Datascript.store' "typed fact persistence"
require_text "$probe" 'Datascript.restore' "typed fact restoration"
require_text "$probe" 'BONSAI_DATASCRIPT_WORKER_PERSISTED' "first-launch marker"
require_text "$probe" 'BONSAI_DATASCRIPT_WORKER_RESTORED' "relaunch marker"
require_text "$probe" 'BONSAI_DATASCRIPT_WORKER_SHUTDOWN' "Worker shutdown marker"

service=$(cat examples/sqlite_worker/ocaml/sqlite_worker_service.ml)
service_interface=$(cat examples/sqlite_worker/ocaml/sqlite_worker_service.mli)
require_text "$service" 'create_with_persistence_probe' "injectable Worker persistence probe"
require_text "$service_interface" 'create_with_persistence_probe' "Worker persistence probe interface"

device_test=$(cat tool/ios/test_datascript_worker_device.sh 2>/dev/null)
device_entry=$(cat examples/sqlite_worker/flutter/lib/datascript_worker_device.dart)
require_text \
  "$device_entry" \
  "stderr.writeln('BONSAI_DATASCRIPT_HOST_RUNTIME_STARTED')" \
  "physical-device host runtime start evidence"
require_text \
  "$device_entry" \
  "stderr.writeln('BONSAI_DATASCRIPT_HOST_RUNTIME_DISPOSED')" \
  "physical-device host runtime disposal evidence"
require_text "$device_test" 'IOS_DEVICE_ID' "physical iPhone selection"
require_text "$device_test" 'IOS_SIGNING_IDENTITY' "physical iPhone signing"
require_text "$device_test" 'CODE_SIGN_IDENTITY = $IOS_SIGNING_IDENTITY' \
  "selected Development signing identity"
reject_text "$device_test" '--require-signing' \
  "Development-only DataScript physical slice"
require_before \
  "$device_test" \
  'ios_device_preflight.sh' \
  'setup_toolchain.sh' \
  "physical-device fail-fast preflight"
require_text "$device_test" '      --profile \' \
  "standalone physical-device Flutter build mode"
reject_text "$device_test" '--debug' \
  "standalone physical-device Flutter build mode"
require_text "$device_test" 'BONSAI_DATASCRIPT_WORKER_PERSISTED' "first launch evidence"
require_text "$device_test" 'BONSAI_DATASCRIPT_WORKER_SHUTDOWN' "runtime shutdown evidence"
require_text "$device_test" 'BONSAI_DATASCRIPT_WORKER_RESTORED' "relaunch evidence"
require_text "$device_test" '--terminate-existing' "runtime relaunch"

require_text "$(cat Makefile)" 'tool/test_datascript_worker_contract.sh' "CI contract target"
require_text "$(cat Makefile)" 'tool/ios/test_datascript_worker_device.sh' "physical-device target"

if test "$failures" -ne 0; then
  printf '%s\n' "DataScript Worker contract failed with $failures violation(s)" >&2
  exit 1
fi

printf '%s\n' "DataScript Worker contract tests passed"
