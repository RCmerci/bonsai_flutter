#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

# shellcheck source=tool/ios/toolchain.lock
. "$script_directory/toolchain.lock"

closure_lock="$repository_root/vendor/opam-ios/runtime-closure.lock"
opam_root="$repository_root/_build/ios/opam-root"
switch_root="$repository_root/_build/ios/switches"
package_root="$repository_root/_build/ios/packages"

fail() {
  printf '%s\n' "iOS runtime package build failure: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

test "$#" -eq 2 ||
  fail "usage: build_runtime_package.sh iphoneos <package>"

target=$1
requested_package=$2

test "$target" = iphoneos || fail "expected iphoneos"
expected_platform=IOS
expected_minimum=$IOS_DEPLOYMENT_TARGET

require_command awk
require_command cp
require_command curl
require_command dirname
require_command find
require_command grep
require_command mkdir
require_command mv
require_command opam
require_command patch
require_command pkg-config
require_command rg
require_command sed
require_command shasum
require_command sort
require_command tar
require_command tr
require_command xcrun

switch="$switch_root/$target"
test -x "$switch/_opam/bin/ocamlc" ||
  fail "missing $target switch; run tool/ios/setup_toolchain.sh first"

resolved_bonsai_version=$(
  OPAMROOT="$opam_root" \
    opam show --switch="$switch" --field=installed-version bonsai
)
test "$resolved_bonsai_version" = "$BONSAI_VERSION" ||
  fail "host dependencies are missing; run setup_host_dependencies.sh $target"

package_row=$(
  awk -F '|' -v package="$requested_package" '
    !/^#/ && $1 == package { print; found = 1 }
    END { if (!found) exit 1 }
  ' "$closure_lock"
) || fail "package is not present in the runtime closure: $requested_package"

old_ifs=$IFS
IFS='|'
set -- $package_row
IFS=$old_ifs

package_name=$1
package_version=$2
package_role=$3
source_url=$4
source_sha256=$5
package_components=$6

test "$package_name" = "$requested_package" ||
  fail "resolved the wrong package row"
case "$package_role" in
  target | dual | target-build) ;;
  *) fail "invalid package role for $package_name: $package_role" ;;
esac

work_root="$package_root/$target/$package_name/$package_version/recipe-$OCAML_IOS_RECIPE_REVISION"
source_archive="$work_root/source.archive"
partial_archive="$work_root/source.archive.partial"
source_directory="$work_root/source"
source_marker="$work_root/source.prepared"
build_directory="$work_root/build"
target_lib="$switch/_opam/ios-sysroot/lib"

mkdir -p "$work_root"

if test ! -f "$source_archive"; then
  rm -f "$partial_archive"
  curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --output "$partial_archive" \
    "$source_url"
  mv "$partial_archive" "$source_archive"
fi

printf '%s  %s\n' "$source_sha256" "$source_archive" |
  shasum -a 256 -c - >/dev/null ||
  fail "source digest does not match for $package_name"

tar -tf "$source_archive" |
  awk '
    /^\// { exit 1 }
    /(^|\/)\.\.(\/|$)/ { exit 1 }
  ' ||
  fail "source archive contains an unsafe path: $package_name"

if test ! -f "$source_marker"; then
  test ! -e "$source_directory" ||
    fail "source directory exists without a preparation marker: $source_directory"
  mkdir -p "$source_directory"
  tar -xf "$source_archive" -C "$source_directory" --strip-components=1
  if test "$package_name" = base; then
    patch \
      -d "$source_directory" \
      -p1 \
      <"$repository_root/vendor/patches/ios/base-host-generator.patch"
  fi
  if test "$package_name" = jst-config; then
    patch \
      -d "$source_directory" \
      -p1 \
      <"$repository_root/vendor/patches/ios/jst-config-host-discover.patch"
  fi
  : >"$source_marker"
fi

if test "$package_name" = jst-config; then
  if ! grep -F '(run ../discover/discover.exe)' \
    "$source_directory/src/dune" >/dev/null; then
    patch \
      --batch \
      --forward \
      -d "$source_directory" \
      -p1 \
      <"$repository_root/vendor/patches/ios/jst-config-host-discover.patch"
  fi
  grep -F '(run %{first_dep})' "$source_directory/src/dune" >/dev/null &&
    fail "jst-config still aliases its host discovery executable"
fi

if test "$package_name" = eio_posix; then
  if grep -F '| 6 -> Some (`Tcp' \
    "$source_directory/lib_eio_posix/net.ml" >/dev/null; then
    patch \
      --batch \
      --forward \
      -d "$source_directory" \
      -p1 \
      <"$repository_root/vendor/patches/ios/eio-posix-darwin-protocol-zero.patch"
  fi
  grep -F '| 6 -> Some (`Tcp' \
    "$source_directory/lib_eio_posix/net.ml" >/dev/null &&
    fail "eio_posix still drops Darwin address records with protocol zero"
  if grep -F 'Unix.getaddrinfo node service []' \
    "$source_directory/lib_eio_posix/net.ml" >/dev/null; then
    patch \
      --batch \
      --forward \
      -d "$source_directory" \
      -p1 \
      <"$repository_root/vendor/patches/ios/eio-posix-darwin-socktype-hints.patch"
  fi
  grep -F 'Unix.getaddrinfo node service []' \
    "$source_directory/lib_eio_posix/net.ml" >/dev/null &&
    fail "eio_posix still resolves Darwin addresses without socket type hints"
fi

sdk_version=$(xcrun --sdk "$target" --show-sdk-version)
sdk_root=$(xcrun --sdk "$target" --show-sdk-path)
target_archiver=$(xcrun --sdk "$target" --find ar)
target_pkg_config_path="$repository_root/vendor/pkgconfig/$target"
test -f "$target_pkg_config_path/sqlite3.pc" ||
  fail "missing target SQLite pkg-config metadata"
export PKG_CONFIG_PATH="$target_pkg_config_path"
export PKG_CONFIG_SYSROOT_DIR="$sdk_root"
export SQLITE3_DISABLE_LOADABLE_EXTENSIONS=1

host_lib=$(
  OPAMROOT="$opam_root" \
    opam var --switch="$switch" lib
)
host_package_root="$host_lib/$package_name"
test -f "$host_package_root/META" ||
  fail "host package metadata is missing for $package_name"

target_package_root="$target_lib/$package_name"
mkdir -p "$target_package_root"
for metadata_name in META dune-package opam; do
  if test -f "$host_package_root/$metadata_name"; then
    cp -f "$host_package_root/$metadata_name" "$target_package_root/"
  fi
done

case "$package_name" in
  fmt | hmap | mtime)
    require_command opam-installer
    topkg_build_directory="$source_directory/_build-ios"
    topkg_arguments=
    if test "$package_name" = fmt; then
      topkg_arguments="--with-base-unix false --with-cmdliner false"
    fi
    (
      cd "$source_directory"
      OPAMROOT="$opam_root" \
        SDK="$sdk_version" \
        VER="$IOS_DEPLOYMENT_TARGET" \
        opam exec --switch="$switch" -- \
        ocaml \
          pkg/pkg.ml \
          build \
          --build-dir _build-ios \
          --debug false \
          --tests false \
          --toolchain ios \
          $topkg_arguments

      install_manifest="$package_name.install"
      case "$package_name" in
        fmt | mtime)
          install_manifest="$package_name.runtime.install"
          awk '
            /_build-ios\/src\/top\// ||
            /_build-ios\/src\/mtime_top_init\.ml/ {
              if ($0 ~ /\][[:space:]]*$/) print "]"
              next
            }
            { print }
          ' "$package_name.install" >"$install_manifest"
          ;;
      esac
      opam-installer \
        --name "$package_name" \
        --prefix "$switch/_opam/ios-sysroot" \
        --libdir "$target_lib" \
        "$install_manifest"
    )

    case "$package_name" in
      fmt | mtime)
        test ! -e "$target_package_root/top" ||
          fail "$package_name staged an unrelated toplevel library"
        ;;
    esac
    if test "$package_name" = mtime; then
      test ! -e "$target_package_root/mtime_top_init.ml" ||
        fail "mtime staged an unrelated toplevel initializer"
    fi

    printf '%s\n' "$package_components" |
      tr ',' '\n' |
      while IFS= read -r component; do
        OPAMROOT="$opam_root" \
          opam exec --switch="$switch" -- \
          ocamlfind -toolchain ios query -predicates=native "$component" \
          >/dev/null ||
          fail "staged component is not visible to findlib: $component"
      done

    primary_topkg_object="$topkg_build_directory/src/$package_name.o"
    if test -f "$primary_topkg_object"; then
      representative_object=$primary_topkg_object
    else
      representative_object=$(
        find "$topkg_build_directory" \
          -type f \
          -name '*.o' \
          ! -name 'myocamlbuild.o' |
          sort |
          sed -n '1p'
      )
    fi
    test -n "$representative_object" ||
      fail "no representative target object was produced for $package_name"
    "$script_directory/verify_macho.sh" \
      "$representative_object" \
      "$expected_platform" \
      arm64 \
      "$expected_minimum"

    if rg -a -l \
      '/opt/homebrew|/usr/local|MacOSX[0-9]|/private/tmp/bonsai-flutter-opam|-mpopcnt' \
      "$target_package_root" >/dev/null; then
      fail "$package_name staged a prohibited host path or CPU flag"
    fi

    printf '%s\n' \
      "iOS $target runtime package build passed: $package_name $package_version"
    exit 0
    ;;
esac

if test "$package_name" = domain-local-await; then
  manual_build_directory="$build_directory/manual"
  mkdir -p "$manual_build_directory"

  compile_manual() {
    OPAMROOT="$opam_root" \
      SDK="$sdk_version" \
      VER="$IOS_DEPLOYMENT_TARGET" \
      opam exec --switch="$switch" -- \
      ocamlfind -toolchain ios ocamlopt \
        -package thread-table \
        -I "$manual_build_directory" \
        "$@"
  }

  compile_manual \
    -c \
    -o "$manual_build_directory/Thread_intf.cmx" \
    "$source_directory/src/Thread_intf.ml"
  compile_manual \
    -c \
    -o "$manual_build_directory/Domain_local_await.cmi" \
    "$source_directory/src/Domain_local_await.mli"
  compile_manual \
    -c \
    -o "$manual_build_directory/Domain_local_await.cmx" \
    "$source_directory/src/Domain_local_await.ml"
  compile_manual \
    -a \
    -o "$manual_build_directory/Domain_local_await.cmxa" \
    "$manual_build_directory/Thread_intf.cmx" \
    "$manual_build_directory/Domain_local_await.cmx"

  find "$manual_build_directory" \
    -maxdepth 1 \
    -type f \
    \( -name '*.a' -o -name '*.cmi' -o -name '*.cmx' -o -name '*.cmxa' \) \
    -exec cp -f {} "$target_package_root/" \;

  OPAMROOT="$opam_root" \
    opam exec --switch="$switch" -- \
    ocamlfind -toolchain ios query -predicates=native domain-local-await \
    >/dev/null ||
    fail "staged component is not visible to findlib: domain-local-await"

  "$script_directory/verify_macho.sh" \
    "$manual_build_directory/Domain_local_await.o" \
    "$expected_platform" \
    arm64 \
    "$expected_minimum"

  if rg -a -l \
    '/opt/homebrew|/usr/local|MacOSX[0-9]|/private/tmp/bonsai-flutter-opam|-mpopcnt' \
    "$target_package_root" >/dev/null; then
    fail "$package_name staged a prohibited host path or CPU flag"
  fi

  printf '%s\n' \
    "iOS $target runtime package build passed: $package_name $package_version"
  exit 0
fi

printf '%s\n' "$package_components" |
  tr ',' '\n' |
  while IFS= read -r component; do
    component_query=$(
      OPAMROOT="$opam_root" \
        opam exec --switch="$switch" -- \
        ocamlfind query \
          -predicates=native \
          -format '%d|%a' \
        "$component"
    )
    if test -z "$component_query"; then
      component_host_directory=$(
        OPAMROOT="$opam_root" \
          opam exec --switch="$switch" -- \
          ocamlfind query "$component"
      )
      component_query="$component_host_directory|"
    fi
    component_host_directory=${component_query%%|*}
    component_archives=${component_query#*|}
    component_relative_path=${component_host_directory#"$host_lib/"}
    target_component_directory="$target_lib/$component_relative_path"
    mkdir -p "$target_component_directory"

    # Package headers are architecture-independent inputs for downstream C
    # stubs. Copy installed headers first so target-generated headers, such as
    # jst-config's config.h, replace any host-generated version below.
    find "$component_host_directory" \
      \( -type f -o -type l \) \
      -name '*.h' |
      while IFS= read -r header; do
        header_relative=${header#"$component_host_directory/"}
        header_destination="$target_component_directory/$header_relative"
        mkdir -p "$(dirname "$header_destination")"
        cp -f "$header" "$header_destination"
      done

    if test -z "$component_archives"; then
      find "$component_host_directory" \
        -maxdepth 1 \
        \( -type f -o -type l \) \
        \( -name '*.ml' -o -name '*.mli' \) \
        -exec cp -f {} "$target_component_directory/" \;
      continue
    fi

    printf '%s\n' "$component_archives" |
      tr ' ' '\n' |
      while IFS= read -r archive_name; do
        test -n "$archive_name" || continue
        dune_file=$(
          rg \
            --files-with-matches \
            --fixed-strings \
            "(public_name $component)" \
            "$source_directory" \
            --glob dune |
            sed -n '1p'
        )
        test -n "$dune_file" ||
          fail "could not locate the Dune library for $component"
        duplicate_dune_file=$(
          rg \
            --files-with-matches \
            --fixed-strings \
            "(public_name $component)" \
            "$source_directory" \
            --glob dune |
            sed -n '2p'
        )
        test -z "$duplicate_dune_file" ||
          fail "multiple Dune libraries declare $component"

        source_component_directory=$(dirname -- "$dune_file")
        source_component_relative=${source_component_directory#"$source_directory/"}
        if test "$source_component_relative" = "$source_component_directory"; then
          source_component_relative=.
        fi
        if test "$source_component_relative" = .; then
          dune_target=$archive_name
        else
          dune_target="$source_component_relative/$archive_name"
        fi
        OPAMROOT="$opam_root" \
          SDK="$sdk_version" \
          VER="$IOS_DEPLOYMENT_TARGET" \
          opam exec --switch="$switch" -- \
          dune build \
            --root="$source_directory" \
            --build-dir="$build_directory" \
            --profile=release \
            -j "${JOBS:-4}" \
            -x ios \
            "$dune_target"

        if test "$package_name" = jst-config; then
          OPAMROOT="$opam_root" \
            SDK="$sdk_version" \
            VER="$IOS_DEPLOYMENT_TARGET" \
            opam exec --switch="$switch" -- \
            dune build \
              --root="$source_directory" \
              --build-dir="$build_directory" \
              --profile=release \
              -j "${JOBS:-4}" \
              -x ios \
              src/config.h \
              src/thread_id.h
        fi

        build_component_directory="$build_directory/default.ios/$source_component_relative"
        archive_stem=${archive_name%.cmxa}
        object_directory="$build_component_directory/.$archive_stem.objs"

        test -f "$build_component_directory/$archive_name" ||
          fail "Dune did not produce $component archive $archive_name"

        extra_c_objects=$(
          OPAMROOT="$opam_root" \
            opam exec --switch="$switch" -- \
            ocamlobjinfo "$build_component_directory/$archive_name" |
            sed -n 's/^Extra C object files:[[:space:]]*//p'
        )
        for extra_c_object in $extra_c_objects; do
          case "$extra_c_object" in
            -lsqlite3)
              test "$package_name" = sqlite3 ||
                fail "$component unexpectedly depends on system SQLite"
              ;;
            -L*)
              fail "$component uses unsupported library path $extra_c_object"
              ;;
            -l*)
              static_archive="lib${extra_c_object#-l}.a"
              if test "$source_component_relative" = .; then
                static_archive_target=$static_archive
              else
                static_archive_target="$source_component_relative/$static_archive"
              fi
              if test ! -f \
                "$build_directory/default.ios/$static_archive_target"; then
                stub_objects=$(
                  find "$build_component_directory" \
                    -maxdepth 1 \
                    -type f \
                    -name '*.o' \
                    -print
                )
                if test -n "$stub_objects"; then
                  "$target_archiver" \
                    rcs \
                    "$build_directory/default.ios/$static_archive_target" \
                    $stub_objects
                else
                  OPAMROOT="$opam_root" \
                    SDK="$sdk_version" \
                    VER="$IOS_DEPLOYMENT_TARGET" \
                    opam exec --switch="$switch" -- \
                    dune build \
                      --root="$source_directory" \
                      --build-dir="$build_directory" \
                      --profile=release \
                      -j "${JOBS:-4}" \
                      -x ios \
                      "$static_archive_target"
                fi
                test -f \
                  "$build_directory/default.ios/$static_archive_target" ||
                  fail "$component did not produce target C stubs $static_archive"
              fi
              ;;
            *)
              fail "$component uses unsupported extra C object $extra_c_object"
              ;;
          esac
        done

        find "$build_component_directory" \
          -maxdepth 1 \
          \( -type f -o -type l \) \
          \( \
            -name "$archive_stem.a" -o \
            -name "$archive_name" -o \
            -name 'lib*_stubs.a' -o \
            -name '*.h' -o \
            -name '*.js' -o \
            -name '*.ml' -o \
            -name '*.mli' \
          \) \
          -exec cp -f {} "$target_component_directory/" \;

        if test -d "$object_directory/byte"; then
          find "$object_directory/byte" \
            -maxdepth 1 \
            -type f \
            \( -name '*.cmi' -o -name '*.cmt' -o -name '*.cmti' \) \
            -exec cp -f {} "$target_component_directory/" \;
        fi
        if test -d "$object_directory/native"; then
          find "$object_directory/native" \
            -maxdepth 1 \
            -type f \
            -name '*.cmx' \
            -exec cp -f {} "$target_component_directory/" \;
        fi
      done

    OPAMROOT="$opam_root" \
      opam exec --switch="$switch" -- \
      ocamlfind -toolchain ios query -predicates=native "$component" \
      >/dev/null ||
      fail "staged component is not visible to findlib: $component"
  done

if test "$package_name" = sqlite3; then
  test -f "$target_package_root/libsqlite3_stubs.a" ||
    fail "sqlite3 target stubs archive is missing"
  bundled_sqlite_archive="lib${package_name}.a"
  test ! -f "$target_package_root/$bundled_sqlite_archive" ||
    fail "a bundled SQLite implementation was staged"
  sqlite_link_metadata=$(
    OPAMROOT="$opam_root" \
      opam exec --switch="$switch" -- \
      ocamlobjinfo "$target_package_root/sqlite3.cmxa"
  )
  printf '%s\n' "$sqlite_link_metadata" |
    grep -F -- '-lsqlite3_stubs -lsqlite3' >/dev/null ||
    fail "sqlite3 target archive lost its external system link requirement"
fi

representative_object=$(
  find "$build_directory/default.ios" -type f -name '*.o' |
    sort |
    sed -n '1p'
)
if test -n "$representative_object"; then
  "$script_directory/verify_macho.sh" \
    "$representative_object" \
    "$expected_platform" \
    arm64 \
    "$expected_minimum"
else
  test "$package_name" = stdlib-shims ||
    fail "no representative target object was produced for $package_name"
  printf '%s\n' \
    "No Mach-O object is expected for metadata-only package $package_name"
fi

if rg -a -l \
  '/opt/homebrew|/usr/local|MacOSX[0-9]|/private/tmp/bonsai-flutter-opam|-mpopcnt' \
  "$target_package_root" >/dev/null; then
  fail "$package_name staged a prohibited host path or CPU flag"
fi

printf '%s\n' \
  "iOS $target runtime package build passed: $package_name $package_version"
