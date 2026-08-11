#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
framework_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

# shellcheck source=tool/ios/sdk_repository.lock
. "$script_directory/sdk_repository.lock"

if [ "$#" -ne 5 ]; then
  echo "usage: $0 SOLUTION_JSON OPAM_REPO_CACHE OUTPUT_REPOSITORY SDK_META_OPAM SUPPORTED_CLOSURE_LOCK" >&2
  exit 64
fi

solution_json=$1
repo_cache=$2
output_repository=$3
sdk_meta_opam=$4
supported_closure_lock=$5
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

packages_tsv="$temporary_directory/packages.tsv"
jq -r '.solution[] | .install? | select(.) | [.name, .version] | @tsv' \
  "$solution_json" | LC_ALL=C sort -u > "$packages_tsv"

package_lock="$temporary_directory/package-universe.lock"
source_lock="$temporary_directory/source-archives.lock"
meta_file="$temporary_directory/opam"
sdk_files="$temporary_directory/files"
mkdir -p "$sdk_files"
mkdir -p "$sdk_files/patches" "$sdk_files/pkgconfig/iphoneos"
cp "$script_directory/build_installed_sdk.sh" "$sdk_files/build-installed-sdk.sh"
sed \
  "s/^framework_source_sha256=.*/framework_source_sha256='$BONSAI_FLUTTER_SOURCE_SHA256'/" \
  "$script_directory/build_installed_sdk.sh" \
  > "$sdk_files/build-installed-sdk.sh"
cp "$script_directory/build_runtime_closure.sh" "$sdk_files/build-runtime-closure.sh"
cp "$script_directory/build_runtime_package.sh" "$sdk_files/build-runtime-package.sh"
cp "$script_directory/verify_macho.sh" "$sdk_files/verify_macho.sh"
cp "$script_directory/toolchain.lock" "$sdk_files/toolchain.lock"
cp "$supported_closure_lock" "$sdk_files/supported-closure.lock"
cp "$framework_root/vendor/patches/ios/"*.patch "$sdk_files/patches/"
for patch_file in "$sdk_files/patches/"*.patch; do
  sed 's/^ $//' "$patch_file" >"$patch_file.normalized"
  mv "$patch_file.normalized" "$patch_file"
done
cp "$framework_root/vendor/pkgconfig/iphoneos/sqlite3.pc" "$sdk_files/pkgconfig/iphoneos/"
chmod +x "$sdk_files/"*.sh

printf '%s\n' '# package|version|repository|metadata-sha256' > "$package_lock"
printf '%s\n' '# package|version|source|algorithm|checksum' > "$source_lock"

while IFS="$(printf '\t')" read -r package version; do
  if [ "$package" = bonsai_flutter_ios_sdk ]; then
    continue
  fi
  package_directory=
  repository_name=
  for repository in bonsai-flutter-ios ios-cross default; do
    candidate="$repo_cache/$repository/packages/$package/$package.$version"
    if [ -d "$candidate" ]; then
      package_directory=$candidate
      case "$repository" in
        bonsai-flutter-ios) repository_name=local ;;
        ios-cross) repository_name=ios-cross ;;
        default) repository_name=default ;;
      esac
      break
    fi
  done
  if [ -z "$package_directory" ]; then
    echo "missing solved package metadata: $package.$version" >&2
    exit 1
  fi
  if find "$package_directory" -type l | grep -q .; then
    echo "package metadata contains a symlink: $package.$version" >&2
    exit 1
  fi

  metadata_input="$temporary_directory/metadata-input"
  : > "$metadata_input"
  find "$package_directory" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    relative=${file#"$package_directory"/}
    printf '%s\0%s\0' "$relative" "$(shasum -a 256 "$file" | cut -d ' ' -f 1)"
  done > "$metadata_input"
  metadata_sha=$(shasum -a 256 "$metadata_input" | cut -d ' ' -f 1)
  printf '%s|%s|%s|%s\n' \
    "$package" "$version" "$repository_name" "$metadata_sha" >> "$package_lock"

  perl -0777 -e '
    use strict;
    use warnings;
    my ($package, $version, @files) = @ARGV;
    for my $file (@files) {
      open my $handle, "<", $file or die "cannot read $file: $!\n";
      local $/;
      my $contents = <$handle>;
      close $handle;
      my @blocks = $file =~ m{/url$}
        ? ($contents)
        : ($contents =~ /(?:^|\n)\s*(?:url|extra-source\s+"[^"]+")\s*\{(.*?)^\s*\}/msg);
      for my $block (@blocks) {
        next unless $block =~ /"([^"]+:\/\/[^\"]+)"/s;
        my $source = $1;
        my ($algorithm, $checksum);
        if ($block =~ /"sha256=([0-9a-fA-F]{64})"/s) {
          ($algorithm, $checksum) = ("sha256", $1);
        } elsif ($block =~ /"sha512=([0-9a-fA-F]{128})"/s) {
          ($algorithm, $checksum) = ("sha512", $1);
        } else {
          die "$package.$version source lacks SHA-256 or SHA-512: $source\n";
        }
        print "$package|$version|$source|$algorithm|$checksum\n";
      }
    }
  ' "$package" "$version" "$package_directory/opam" \
    $(find "$package_directory" -maxdepth 1 -type f -name url -print) >> "$source_lock"
done < "$packages_tsv"

{
  printf '%s\n' '(package_lock' ' (format_version 1)' ' (packages'
  while IFS='|' read -r package version repository metadata_sha; do
    case "$package" in
      ''|'# package') continue ;;
    esac
    printf '  (%s %s %s %s)\n' "$package" "$version" "$repository" "$metadata_sha"
  done < "$package_lock"
  printf '%s\n' ' ))'
} > "$sdk_files/package-lock.sexp"

package_lock_digest=$(shasum -a 256 "$sdk_files/package-lock.sexp" | cut -d ' ' -f 1)
target_components_digest=$(shasum -a 256 "$supported_closure_lock" | cut -d ' ' -f 1)
target_packages="$temporary_directory/target-packages.tsv"
awk -F '|' '
  $1 !~ /^#/ && ($3 == "target-build" || $3 == "target-package") {
    print $1 "\t" $2
  }
' "$supported_closure_lock" | LC_ALL=C sort -u > "$target_packages"
printf '%s\t%s\n' bonsai_flutter "$BONSAI_FLUTTER_VERSION" >> "$target_packages"
printf '%s\t%s\n' ocaml-ios64 5.1.1 >> "$target_packages"
LC_ALL=C sort -u "$target_packages" -o "$target_packages"

{
  printf '%s\n' \
    '(sdk' \
    ' (format_version 1)' \
    " (bonsai_flutter_version $BONSAI_FLUTTER_VERSION)" \
    ' (bonsai_flutter_source' \
    "  $BONSAI_FLUTTER_SOURCE_REVISION" \
    '  sha256' \
    "  $BONSAI_FLUTTER_SOURCE_SHA256)" \
    " (abi_version $SDK_ABI_VERSION)" \
    ' (ocaml_version 5.1.1)' \
    ' (dune_version_range 3.17 4.0)' \
    ' (cross_compiler ocaml-ios64 5.1.1)' \
    ' (findlib_toolchain ios)' \
    ' (architecture arm64)' \
    ' (platform iphoneos)' \
    ' (minimum_deployment_target 15.0)' \
    " (package_universe_digest $package_lock_digest)" \
    " (target_components_digest $target_components_digest)" \
    ' (required_frameworks Foundation Security)' \
    ' (required_system_libraries sqlite3)' \
    " (build_recipe_revision $SDK_BUILD_RECIPE_REVISION)" \
    ' (packages'
  while IFS="$(printf '\t')" read -r package version; do
    printf '  (%s %s)\n' "$package" "$version"
  done < "$target_packages"
  printf '%s\n' ' )' ' (libraries'
  awk -F '|' '
    $1 !~ /^#/ && ($3 == "target-build" || $3 == "target-package") && $8 != "-" {
      count = split($8, components, ",")
      component_list = ""
      for (component_index = 1; component_index <= count; component_index++) {
        component_list = component_list " " components[component_index]
      }
      for (component_index = 1; component_index <= count; component_index++) {
        printf "  (%s %s %s (%s))\n", components[component_index], $1, $2, substr(component_list, 2)
      }
    }
  ' "$supported_closure_lock"
  standard_library_components='threads unix str dynlink'
  for library in $standard_library_components; do
    printf '  (%s ocaml-ios64 5.1.1 (%s))\n' "$library" "$standard_library_components"
  done
  framework_components='bonsai_flutter bonsai_flutter.driver bonsai_flutter.native_backend bonsai_flutter.protocol bonsai_flutter.runtime bonsai_flutter.runtime_adapter bonsai_flutter.spec bonsai_flutter.spec_impl bonsai_flutter.ui'
  for library in $framework_components; do
    printf '  (%s bonsai_flutter %s (%s))\n' \
      "$library" "$BONSAI_FLUTTER_VERSION" "$framework_components"
  done
  printf '%s\n' ' ))'
} > "$sdk_files/manifest.sexp"

framework_source_record=$(awk -F '|' '
  $1 == package && $2 == version { print; exit }
' package="bonsai_flutter" version="$BONSAI_FLUTTER_VERSION" "$source_lock")
test -n "$framework_source_record" || {
  echo "missing Bonsai Flutter source archive lock" >&2
  exit 1
}
old_ifs=$IFS
IFS='|'
set -- $framework_source_record
IFS=$old_ifs
framework_source_url=$3
framework_source_checksum_algorithm=$4
framework_source_checksum=$5
test "$framework_source_checksum_algorithm" = sha256 || {
  echo "Bonsai Flutter source must use SHA-256" >&2
  exit 1
}
test "$framework_source_url" = \
  "https://github.com/RCmerci/bonsai_flutter/archive/$BONSAI_FLUTTER_SOURCE_REVISION.tar.gz" || {
  echo "Bonsai Flutter source revision differs from sdk_repository.lock" >&2
  exit 1
}
test "$framework_source_checksum" = "$BONSAI_FLUTTER_SOURCE_SHA256" || {
  echo "Bonsai Flutter source checksum differs from sdk_repository.lock" >&2
  exit 1
}

{
  printf '%s\n' \
    'opam-version: "2.0"' \
    'synopsis: "Locked Bonsai Flutter iPhoneOS SDK package universe"' \
    'description: """' \
    'Installs the exact host and target package universe supported by Bonsai Flutter' \
    'for iPhoneOS arm64. Package versions, recipes, and source checksums are immutable' \
    'for this SDK release.' \
    '"""' \
    'maintainer: "bonsai_flutter contributors"' \
    'authors: ["bonsai_flutter contributors"]' \
    'license: "MIT"' \
    'homepage: "https://github.com/RCmerci/bonsai_flutter"' \
    'bug-reports: "https://github.com/RCmerci/bonsai_flutter/issues"' \
    'dev-repo: "git+https://github.com/RCmerci/bonsai_flutter.git"' \
    'extra-source "bonsai_flutter.tar.gz" {' \
    "  src: \"$framework_source_url\"" \
    "  checksum: [\"sha256=$framework_source_checksum\"]" \
    '}'
  awk -F '|' '
    $1 !~ /^#/ && ($3 == "target-build" || $3 == "target-package") {
      printf "extra-source \"runtime-%s-%s.archive\" {\n", $1, $7
      printf "  src: \"%s\"\n", $6
      printf "  checksum: [\"sha256=%s\"]\n", $7
      print "}"
    }
  ' "$supported_closure_lock"
  printf '%s\n' 'extra-files: ['
  find "$sdk_files" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    relative=${file#"$sdk_files"/}
    printf '  ["%s" "sha256=%s"]\n' \
      "$relative" \
      "$(shasum -a 256 "$file" | cut -d ' ' -f 1)"
  done
  printf '%s\n' ']' 'depends: ['
  while IFS="$(printf '\t')" read -r package version; do
    if [ "$package" != bonsai_flutter_ios_sdk ]; then
      printf '  "%s" {= "%s"}\n' "$package" "$version"
    fi
  done < "$packages_tsv"
  printf '%s\n' \
    ']' \
    'build: [' \
    '  ["sh" "./build-installed-sdk.sh" "%{switch}%" "%{prefix}%"]' \
    ']' \
    'install: [' \
    '  ["cp" "-R" ".bonsai_flutter_ios_sdk/stage/ios-sysroot/." "%{prefix}%/ios-sysroot/"]' \
    '  ["mkdir" "-p" "%{share}%/bonsai_flutter_ios_sdk"]' \
    '  ["cp" "manifest.sexp" "%{share}%/bonsai_flutter_ios_sdk/manifest.sexp"]' \
    '  ["cp" "package-lock.sexp" "%{share}%/bonsai_flutter_ios_sdk/package-lock.sexp"]' \
    ']' \
    'available: os = "macos" & arch = "arm64"'
} > "$meta_file"

mkdir -p "$output_repository" "$(dirname "$sdk_meta_opam")"
actual_sdk_files="$(dirname "$sdk_meta_opam")/files"
mkdir -p "$actual_sdk_files"
mv "$package_lock" "$output_repository/package-universe.lock"
mv "$source_lock" "$output_repository/source-archives.lock"
mv "$sdk_files/manifest.sexp" "$actual_sdk_files/manifest.sexp"
mv "$sdk_files/package-lock.sexp" "$actual_sdk_files/package-lock.sexp"
cp -R "$sdk_files/." "$actual_sdk_files/"
mv "$meta_file" "$sdk_meta_opam"
