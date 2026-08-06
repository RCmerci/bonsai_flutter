#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

# shellcheck source=tool/ios/toolchain.lock
. "$script_directory/toolchain.lock"

opam_root="$repository_root/_build/ios/opam-root"
switch_root="$repository_root/_build/ios/switches"
source_root="$repository_root/_build/ios/sources/host"
APPLICATION_OPAM_FILE=${APPLICATION_OPAM_FILE:-}
BONSAI_FLUTTER_FEATURES=${BONSAI_FLUTTER_FEATURES:-core,network,sqlite}

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

pin_application_dependencies() {
  switch=$1
  test -n "$APPLICATION_OPAM_FILE" || return 0
  test -f "$APPLICATION_OPAM_FILE" ||
    fail "APPLICATION_OPAM_FILE does not exist: $APPLICATION_OPAM_FILE"

  # Application pin-depends is the authority for source identities. Ignore
  # pin-depends advertised by those sources so an upstream development branch
  # cannot replace an application-selected commit.
  sed -n \
    's/^[[:space:]]*\["\([A-Za-z0-9_.+-]*\)"[[:space:]]*"\([^"]*\)"\][[:space:]]*$/\1|\2/p' \
    "$APPLICATION_OPAM_FILE" |
    while IFS='|' read -r package source; do
      case "$source" in
        git+https://*\#[0-9a-f][0-9a-f]*) ;;
        *) fail "$package has a floating or unsupported pin-depends source: $source" ;;
      esac
      opam_command pin add \
        --switch="$switch" \
        --no-action \
        --ignore-pin-depends \
        --yes \
        "$package" \
        "$source"
    done
}

has_feature() {
  case ",$BONSAI_FLUTTER_FEATURES," in
    *,$1,*) return 0 ;;
    *) return 1 ;;
  esac
}

pin_locked_datascript_dependencies() {
  switch=$1
  has_feature sqlite || return 0
  test -n "$APPLICATION_OPAM_FILE" && return 0

  opam_command pin add --switch="$switch" --no-action --ignore-pin-depends --yes \
    "datascript_ocaml.$DATASCRIPT_OCAML_VERSION" \
    "git+https://github.com/logseq/datascript-ocaml.git#$DATASCRIPT_OCAML_COMMIT"
  opam_command pin add --switch="$switch" --no-action --ignore-pin-depends --yes \
    "datascript-ocaml-native.$DATASCRIPT_OCAML_VERSION" \
    "git+https://github.com/logseq/datascript-ocaml.git#$DATASCRIPT_OCAML_COMMIT"
  opam_command pin add --switch="$switch" --no-action --ignore-pin-depends --yes \
    "persistent_sorted_set_ocaml.$PERSISTENT_SORTED_SET_VERSION" \
    "git+https://github.com/logseq/persistent-sorted-set-ocaml.git#$PERSISTENT_SORTED_SET_COMMIT"
  for package in melange-edn-core melange-edn-native; do
    opam_command pin add --switch="$switch" --no-action --ignore-pin-depends --yes \
      "$package.$MELANGE_EDN_VERSION" \
      "git+https://github.com/RCmerci/melange-edn.git#$MELANGE_EDN_COMMIT"
  done
  for package in melange-transit-core melange-transit-native; do
    opam_command pin add --switch="$switch" --no-action --ignore-pin-depends --yes \
      "$package.$MELANGE_TRANSIT_VERSION" \
      "git+https://github.com/RCmerci/melange-transit.git#$MELANGE_TRANSIT_COMMIT"
  done
}

install_application_dependencies() {
  switch=$1
  test -n "$APPLICATION_OPAM_FILE" || return 0
  opam_command install \
    --switch="$switch" \
    --deps-only \
    --assume-depexts \
    --yes \
    "$APPLICATION_OPAM_FILE"
}

install_for_switch() {
  logical_name=$1
  switch=$(switch_path "$logical_name")
  test -x "$switch/_opam/bin/ocamlc" ||
    fail "missing $logical_name switch; run tool/ios/setup_toolchain.sh first"

  pin_locked_datascript_dependencies "$switch"
  pin_application_dependencies "$switch"

  opam_command install \
    --switch="$switch" \
    "dune.$DUNE_VERSION" \
    "ocamlfind.$OCAMLFIND_VERSION" \
    "bonsai.$BONSAI_VERSION" \
    "core.$CORE_VERSION" \
    "bigstringaf.$BIGSTRINGAF_VERSION" \
    "cstruct.$CSTRUCT_VERSION" \
    "domain-local-await.$DOMAIN_LOCAL_AWAIT_VERSION" \
    "eio.$EIO_VERSION" \
    "eio_posix.$EIO_VERSION" \
    "fmt.$FMT_VERSION" \
    "hmap.$HMAP_VERSION" \
    "iomux.$IOMUX_VERSION" \
    "lwt-dllist.$LWT_DLLIST_VERSION" \
    "mtime.$MTIME_VERSION" \
    "optint.$OPTINT_VERSION" \
    "psq.$PSQ_VERSION" \
    "thread-table.$THREAD_TABLE_VERSION" \
    --assume-depexts \
    --yes

  if has_feature network; then
    opam_command install \
      --switch="$switch" \
      "ca-certs-nss.$CA_CERTS_NSS_VERSION" \
      "digestif.$DIGESTIF_VERSION" \
      "domain-name.$DOMAIN_NAME_VERSION" \
      "gluten.$GLUTEN_VERSION" \
      "gluten-eio.$GLUTEN_EIO_VERSION" \
      "httpun.$HTTPUN_VERSION" \
      "httpun-eio.$HTTPUN_EIO_VERSION" \
      "httpun-ws.$HTTPUN_WS_VERSION" \
      "mirage-crypto-rng.$MIRAGE_CRYPTO_VERSION" \
      "ptime.$PTIME_VERSION" \
      "tls.$TLS_VERSION" \
      "tls-eio.$TLS_VERSION" \
      "uri.$URI_VERSION" \
      "x509.$X509_VERSION" \
      --assume-depexts \
      --yes
  fi

  if has_feature sqlite; then
    opam_command install \
      --switch="$switch" \
      "sqlite3.$SQLITE3_VERSION" \
      "melange.$MELANGE_VERSION" \
      "datascript_ocaml.$DATASCRIPT_OCAML_VERSION" \
      "datascript-ocaml-native.$DATASCRIPT_OCAML_VERSION" \
      "persistent_sorted_set_ocaml.$PERSISTENT_SORTED_SET_VERSION" \
      "melange-edn-core.$MELANGE_EDN_VERSION" \
      "melange-edn-native.$MELANGE_EDN_VERSION" \
      "melange-transit-core.$MELANGE_TRANSIT_VERSION" \
      "melange-transit-native.$MELANGE_TRANSIT_VERSION" \
      --assume-depexts \
      --yes

    if test -z "$APPLICATION_OPAM_FILE"; then
      opam_command install \
        --switch="$switch" \
        "uutf.$UUTF_VERSION" \
        "uunf.$UUNF_VERSION" \
        "uucp.$UUCP_VERSION" \
        "yojson.$YOJSON_VERSION" \
        --assume-depexts \
        --yes
    fi
  fi

  install_application_dependencies "$switch"

  if test "${SKIP_CLOSURE_VERIFY:-false}" != true; then
    OPAMROOT="$opam_root" \
      HOST_OCAML_SWITCH="$switch" \
      "$script_directory/verify_runtime_closure.sh" \
        --check-lock-only \
        --lock "${RUNTIME_CLOSURE_LOCK:-$repository_root/vendor/opam-ios/runtime-closure.lock}" \
        --features "$BONSAI_FLUTTER_FEATURES"
  fi

  if test "$logical_name" != host; then
    "$script_directory/stage_host_metadata.sh" "$logical_name"
  fi
}

require_command opam

requested_target=${1:-all}
case "$requested_target" in
  host | iphoneos)
    install_for_switch "$requested_target"
    ;;
  all)
    install_for_switch host
    install_for_switch iphoneos
    ;;
  *)
    fail "expected host, iphoneos, or all"
    ;;
esac

printf '%s\n' "iOS $requested_target host dependency setup passed"
