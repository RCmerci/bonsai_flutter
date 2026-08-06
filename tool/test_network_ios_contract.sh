#!/bin/sh

set -u

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
cd "$repository_root"

failures=0

fail() {
  printf '%s\n' "network iOS contract failure: $1" >&2
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

for path in \
  examples/network/flutter/ios/Flutter/AppFrameworkInfo.plist \
  examples/network/flutter/ios/Flutter/Debug.xcconfig \
  examples/network/flutter/ios/Flutter/Release.xcconfig \
  examples/network/flutter/ios/Runner.xcodeproj/project.pbxproj \
  examples/network/flutter/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme \
  examples/network/flutter/ios/Runner.xcworkspace/contents.xcworkspacedata \
  examples/network/flutter/ios/Runner/AppDelegate.swift \
  examples/network/flutter/ios/Runner/Info.plist \
  examples/network/flutter/ios/Runner/PrivacyInfo.xcprivacy \
  examples/network/flutter/ios/Runner/Runner-Bridging-Header.h \
  examples/network/flutter/ios/Runner/SceneDelegate.swift
do
  require_file "$path"
done

native_builder=$(cat tool/ios/build_native_objects.sh)
network_loop_entries=$(
  printf '%s\n' "$native_builder" |
    grep -F '  network \' |
    wc -l |
    tr -d ' '
)
test "$network_loop_entries" -eq 2 ||
  fail "network must appear once in each iOS build and staging loop"
require_text \
  "$native_builder" \
  'artifact_root/$example/ios/$target/arm64' \
  "iOS native-object staging destination"
require_text "$native_builder" 'nm -u' "iOS unresolved-symbol audit"
require_text "$native_builder" 'openssl' "iOS prohibited TLS-backend audit"

makefile=$(cat Makefile)
require_text \
  "$makefile" \
  'cd examples/network/flutter && flutter build ios --debug --no-codesign' \
  "ci-ios network debug build"
require_text \
  "$makefile" \
  'cd examples/network/flutter && flutter build ios --profile --no-codesign' \
  "ci-ios network profile build"
require_text \
  "$makefile" \
  'cd examples/network/flutter && flutter build ios --release --no-codesign' \
  "ci-ios network release build"
require_text \
  "$makefile" \
  'examples/network/flutter/build/ios/iphoneos/Runner.app' \
  "ci-ios network bundle audit"
require_text \
  "$makefile" \
  'tool/network_spike/test_ios_device_probe.sh' \
  "signed network device probe"

closure_lock=$(cat vendor/opam-ios/runtime-closure.lock)
closure_rows=$(printf '%s\n' "$closure_lock" | awk -F '|' '!/^#/ && NF { count++ } END { print count + 0 }')
runtime_rows=$(printf '%s\n' "$closure_lock" | awk -F '|' '!/^#/ && NF && $3 != "target-build" { count++ } END { print count + 0 }')
target_build_rows=$(printf '%s\n' "$closure_lock" | awk -F '|' '!/^#/ && NF && $3 == "target-build" { count++ } END { print count + 0 }')
component_count=$(
  printf '%s\n' "$closure_lock" |
    awk -F '|' '
      !/^#/ && NF && $3 != "target-build" {
        count = split($6, components, ",")
        for (component_index = 1; component_index <= count; component_index++) {
          print components[component_index]
        }
      }
    ' |
    sort -u |
    wc -l |
    tr -d ' '
)
test "$closure_rows" -eq 90 ||
  fail "iOS runtime closure has $closure_rows rows, expected 90"
test "$runtime_rows" -eq 88 ||
  fail "iOS runtime closure has $runtime_rows runtime packages, expected 88"
test "$target_build_rows" -eq 2 ||
  fail "iOS runtime closure has $target_build_rows target-build packages, expected 2"
test "$component_count" -eq 128 ||
  fail "iOS runtime closure has $component_count components, expected 128"

for row in \
  'gmp-sys-ios|6.3.0|target-build|https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz|a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898|gmp-sys-ios' \
  'ca-certs-nss|3.126|target|https://github.com/mirage/ca-certs-nss/releases/download/v3.126/ca-certs-nss-3.126.tbz|682a23c2c547c2af85084d75bb9844c5d9a7b8fddf90fa02ea4958eddce30204|ca-certs-nss' \
  'mirage-crypto-rng|2.2.0|target|https://github.com/mirage/mirage-crypto/releases/download/v2.2.0/mirage-crypto-2.2.0.tbz|4b87091b6a77843bf97a74aae2e7da21310307ff7d2105712c4369680122d80a|mirage-crypto-rng,mirage-crypto-rng.unix' \
  'httpun-eio|0.2.0|target|https://github.com/anmonteiro/httpun/releases/download/0.2.0/httpun-0.2.0.tbz|a2ce27ef4c85ae8e1c1008d1e3d5e893d6b211b934586a1dd2942f7db687bd2c|httpun-eio' \
  'httpun-ws|0.2.0|target|https://github.com/anmonteiro/httpun-ws/releases/download/0.2.0/httpun-ws-0.2.0.tbz|eae0cd2e0eb5b4fc9cb6d862b7116a6f0fc8503b2e439046bf0e6f4cb2c297fd|httpun-ws' \
  'tls-eio|2.1.2|target|https://github.com/mirleft/ocaml-tls/releases/download/v2.1.2/tls-2.1.2.tbz|d51940587bce9475c977c596904c8179dcd784d9ef6dd9afe3e634cca940c9f3|tls-eio'
do
  require_text "$closure_lock" "$row" "iOS runtime closure lock"
done
reject_pattern \
  "$closure_lock" \
  '(^|[|])(openssl|ssl|eio-ssl|piaf|cohttp-eio)([|.-]|$)' \
  "iOS runtime closure lock"

closure_verifier=$(cat tool/ios/verify_runtime_closure.sh)
require_text "$closure_verifier" '= 88 ||' "iOS closure runtime-package count"
require_text "$closure_verifier" '= 128 ||' "iOS closure component count"
require_text \
  "$closure_verifier" \
  'closure lock must contain 88 runtime and two target-build packages' \
  "iOS closure package count"
for root in \
  ca-certs-nss \
  digestif.c \
  gluten-eio \
  httpun-eio \
  httpun-ws \
  mirage-crypto-rng.unix \
  mirage-ptime.unix \
  tls-eio \
  x509
do
  require_text "$closure_verifier" "$root" "iOS closure findlib roots"
done

host_setup=$(cat tool/ios/setup_host_dependencies.sh)
for dependency in \
  'ca-certs-nss.$CA_CERTS_NSS_VERSION' \
  'gluten-eio.$GLUTEN_EIO_VERSION' \
  'httpun-eio.$HTTPUN_EIO_VERSION' \
  'httpun-ws.$HTTPUN_WS_VERSION' \
  'mirage-crypto-rng.$MIRAGE_CRYPTO_VERSION' \
  'tls-eio.$TLS_VERSION' \
  'x509.$X509_VERSION'
do
  require_text "$host_setup" "$dependency" "iOS host network dependency setup"
done
reject_pattern \
  "$host_setup" \
  '(openssl|ssl|eio-ssl|piaf|cohttp-eio)' \
  "iOS host dependency setup"

toolchain_lock=$(cat tool/ios/toolchain.lock)
for pin in \
  "CA_CERTS_NSS_VERSION='3.126'" \
  "GLUTEN_EIO_VERSION='0.5.2'" \
  "HTTPUN_EIO_VERSION='0.2.0'" \
  "HTTPUN_WS_VERSION='0.2.0'" \
  "MIRAGE_CRYPTO_VERSION='2.2.0'" \
  "TLS_VERSION='2.1.2'" \
  "X509_VERSION='1.1.1'"
do
  require_text "$toolchain_lock" "$pin" "iOS network toolchain lock"
done

runtime_builder=$(cat tool/ios/build_runtime_package.sh)
require_text "$runtime_builder" 'gmp-sys-ios' "iOS static GMP target recipe"
require_text "$runtime_builder" 'ios-deps/gmp' "iOS static GMP staging"
require_text "$runtime_builder" 'zarith' "iOS Zarith target recipe"
require_text "$runtime_builder" 'logs | ptime' "iOS Topkg network dependencies"
require_file vendor/patches/ios/mirage-crypto-rng-apple-entropy.patch
require_text \
  "$runtime_builder" \
  'mirage-crypto-rng-apple-entropy.patch' \
  "iOS mirage-crypto-rng Apple entropy recipe"
reject_pattern \
  "$runtime_builder" \
  '(openssl|libssl|libcrypto|securetransport)' \
  "iOS runtime package builder"

device_probe=$(cat tool/network_spike/test_ios_device_probe.sh)
require_text \
  "$device_probe" \
  'IOS_DEVELOPMENT_PROFILE_PATH' \
  "network device probe signing contract"
require_text \
  "$device_probe" \
  'IOS_DEVELOPMENT_SIGNING_IDENTITY' \
  "network device probe signing contract"

if test "$failures" -ne 0; then
  printf '%s\n' "network iOS contract failed with $failures violation(s)" >&2
  exit 1
fi

printf '%s\n' "Network iOS contract tests passed"
