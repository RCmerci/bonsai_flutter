open Bonsai_flutter_tool

let valid_config =
  {|
(lang 2)

(app
 (name journal)
 (flutter_root flutter)
 (native_target app/native_embed.exe.o)
 (features network sqlite)
 (host
  (mode managed_adapter)
  (adapter lib/application_host_adapter.dart)
  (entrypoint journal)
  (launch_policy replace_existing))
 (macos
  (minimum_version 26.0)
  (architectures arm64))
 (ios
  (minimum_version 15.0)
  (architectures arm64)))
|}
;;

let managed_adapter_config =
  {|
(lang 2)

(app
 (name journal)
 (flutter_root flutter)
 (native_target app/native_embed.exe.o)
 (features network sqlite)
 (host
  (mode managed_adapter)
  (adapter lib/application_host_adapter.dart)
  (entrypoint journal_runtime)
  (launch_policy replace_existing))
 (macos
  (minimum_version 26.0)
  (architectures arm64))
 (ios
  (minimum_version 15.0)
  (architectures arm64)))
|}
;;

let custom_host_config =
  {|
(lang 2)

(app
 (name journal)
 (flutter_root flutter)
 (native_target ocaml/native_embed.exe.o)
 (features sqlite)
 (host
  (mode custom)
  (main lib/main.dart))
 (macos
  (minimum_version 26.0)
  (architectures arm64))
 (ios
  (minimum_version 15.0)
  (architectures arm64)))
|}
;;

let consumer_pubspec ?(line_ending = "\n") () =
  [ "name: journal_host"
  ; "# consumer comment"
  ; "dependencies:"
  ; "  path_provider: ^2.1.5"
  ; "  # bonsai-flutter:begin packages"
  ; "  bonsai_flutter:"
  ; "    path: old/path"
  ; "  # bonsai-flutter:end packages"
  ; "hooks:"
  ; "  unrelated_hook: keep-me"
  ; "  user_defines:"
  ; "    bonsai_flutter_native:"
  ; "      # bonsai-flutter:begin native-hook"
  ; "      native_artifact_root: old/artifacts"
  ; "      ios_deployment_target: '14.0'"
  ; "      # bonsai-flutter:end native-hook"
  ; "dev_dependencies:"
  ; "  test: ^1.31.0"
  ; ""
  ]
  |> String.concat line_ending
;;

let get_ok = function
  | Ok value -> value
  | Error message -> Alcotest.fail message
;;

let contains source pattern =
  try
    ignore (Str.search_forward (Str.regexp_string pattern) source 0);
    true
  with
  | Not_found -> false
;;

let check_error_contains expected = function
  | Ok _ -> Alcotest.failf "expected an error containing %S" expected
  | Error message -> Alcotest.(check bool) message true (contains message expected)
;;

let replace_once source ~pattern ~replacement =
  let regexp = Str.regexp_string pattern in
  Str.replace_first regexp replacement source
;;

let read_file path =
  let channel = open_in_bin path in
  let contents = really_input_string channel (in_channel_length channel) in
  close_in channel;
  contents
;;

let write_file path contents =
  Scaffold.ensure_directory (Filename.dirname path);
  let channel = open_out_bin path in
  output_string channel contents;
  close_out channel
;;

let write_executable path contents =
  write_file path contents;
  Unix.chmod path 0o755
;;

let non_empty_lines source =
  source |> String.split_on_char '\n' |> List.filter (fun line -> line <> "")
;;

let with_environment bindings f =
  let previous = List.map (fun (name, _) -> name, Sys.getenv_opt name) bindings in
  List.iter (fun (name, value) -> Unix.putenv name value) bindings;
  Fun.protect
    ~finally:(fun () ->
      List.iter
        (fun (name, value) ->
           match value with
           | Some value -> Unix.putenv name value
           | None -> Unix.putenv name "")
        previous)
    f
;;

type ios_tool_fixture =
  { root : string
  ; project_root : string
  ; framework_root : string
  ; command_log : string
  ; config : Config.t
  }

let command_logger program =
  Printf.sprintf
    {|#!/bin/sh
set -eu
{
  printf '%%s\t%%s' '%s' "$PWD"
  for argument in "$@"; do
    printf '\t%%s' "$argument"
  done
  printf '\n'
} >> "$COMMAND_LOG"
|}
    program
;;

let create_ios_tool_fixture () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "ios-device" |> Unix.realpath in
  let project_root = Filename.concat root "project" in
  let framework_root = Filename.concat root "framework" in
  let bin = Filename.concat root "bin" in
  let command_log = Filename.concat root "commands.log" in
  Scaffold.ensure_directory (Filename.concat project_root "flutter");
  Scaffold.ensure_directory (Filename.concat framework_root "tool/ios");
  Scaffold.ensure_directory bin;
  write_executable
    (Filename.concat bin "flutter")
    (command_logger "flutter"
     ^ {|exit "${FLUTTER_EXIT:-0}"
|}
    );
  write_executable
    (Filename.concat bin "plutil")
    (command_logger "plutil"
     ^ {|test -z "${PLUTIL_EXIT:-}" || exit "$PLUTIL_EXIT"
printf '%s\n' "${BUNDLE_IDENTIFIER:-com.example.journal}"
|}
    );
  write_executable
    (Filename.concat bin "xcrun")
    (command_logger "xcrun"
     ^ {|if test "${1:-}" = devicectl \
  && test "${2:-}" = device \
  && test "${3:-}" = install \
  && test -n "${INSTALL_EXIT:-}"; then
  exit "$INSTALL_EXIT"
fi
exit "${XCRUN_EXIT:-0}"
|}
    );
  write_executable
    (Filename.concat framework_root "tool/ios/verify_app_bundle.sh")
    (command_logger "verify_app_bundle"
     ^ {|exit "${VERIFY_EXIT:-0}"
|}
    );
  { root
  ; project_root
  ; framework_root
  ; command_log
  ; config = Config.parse_string valid_config |> get_ok
  }
;;

let with_ios_tool_fixture ?(environment = []) fixture f =
  let path = Filename.concat fixture.root "bin" ^ ":" ^ Sys.getenv "PATH" in
  with_environment
    (("PATH", path) :: ("COMMAND_LOG", fixture.command_log) :: environment)
    f
;;

let create_ios_app_bundle fixture profile =
  let app_bundle =
    Plan.ios_app_bundle ~project_root:fixture.project_root ~config:fixture.config ~profile
  in
  Scaffold.ensure_directory app_bundle;
  write_file
    (Filename.concat app_bundle "Info.plist")
    {|<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.journal</string>
</dict></plist>
|};
  app_bundle
;;

let run_ios_device fixture ~profile ~device ~forwarded =
  Build_system.run_flutter_host
    ~framework_root:fixture.framework_root
    ~project_root:fixture.project_root
    ~config:fixture.config
    ~action:Plan.Run
    ~platform:Plan.Ios_platform
    ~profile
    ~device:(Some device)
    ~no_codesign:false
    ~forwarded
;;

let test_parse_valid_config () =
  let config = Config.parse_string valid_config |> get_ok in
  Alcotest.(check string) "name" "journal" config.name;
  Alcotest.(check string) "flutter root" "flutter" config.flutter_root;
  Alcotest.(check string) "native target" "app/native_embed.exe.o" config.native_target;
  Alcotest.(check (list string))
    "features"
    [ "core"; "network"; "sqlite" ]
    (List.map Config.Feature.to_string config.features);
  Alcotest.(check string) "macOS minimum" "26.0" config.macos.minimum_version;
  Alcotest.(check string) "iOS minimum" "15.0" config.ios.minimum_version;
  Alcotest.(check (list string)) "iOS architectures" [ "arm64" ] config.ios.architectures
;;

let test_invalid_configs () =
  [ ( "unsupported schema"
    , replace_once valid_config ~pattern:"(lang 2)" ~replacement:"(lang 1)"
    , "Unsupported schema version" )
  ; ( "unknown field"
    , replace_once
        valid_config
        ~pattern:"(features network sqlite)"
        ~replacement:"(mystery true)"
    , "Unknown app field" )
  ; ( "duplicate field"
    , replace_once
        valid_config
        ~pattern:"(name journal)"
        ~replacement:"(name journal) (name other)"
    , "Duplicate app field" )
  ; ( "unsafe name"
    , replace_once valid_config ~pattern:"(name journal)" ~replacement:"(name ../journal)"
    , "Invalid application name" )
  ; ( "absolute native target"
    , replace_once
        valid_config
        ~pattern:"app/native_embed.exe.o"
        ~replacement:"/tmp/native_embed.exe.o"
    , "native_target must be a relative path" )
  ; ( "traversing native target"
    , replace_once
        valid_config
        ~pattern:"app/native_embed.exe.o"
        ~replacement:"../native_embed.exe.o"
    , "native_target must not contain parent traversal" )
  ; ( "unsupported macOS minimum"
    , replace_once valid_config ~pattern:"26.0" ~replacement:"13.0"
    , "Unsupported macOS minimum version" )
  ; ( "unsupported macOS architecture"
    , replace_once
        valid_config
        ~pattern:"(minimum_version 26.0)\n  (architectures arm64)"
        ~replacement:"(minimum_version 26.0)\n  (architectures x86_64)"
    , "Unsupported macOS architecture" )
  ; ( "duplicate macOS architecture"
    , replace_once
        valid_config
        ~pattern:"(minimum_version 26.0)\n  (architectures arm64)"
        ~replacement:"(minimum_version 26.0)\n  (architectures arm64 arm64)"
    , "Duplicate macOS architecture" )
  ; ( "empty macOS architecture"
    , replace_once
        valid_config
        ~pattern:"(minimum_version 26.0)\n  (architectures arm64)"
        ~replacement:"(minimum_version 26.0)\n  (architectures)"
    , "macos.architectures must not be empty" )
  ; ( "unsupported iOS architecture"
    , replace_once
        valid_config
        ~pattern:"(minimum_version 15.0)\n  (architectures arm64)"
        ~replacement:"(minimum_version 15.0)\n  (architectures x86_64)"
    , "Unsupported iOS architecture" )
  ; ( "duplicate feature"
    , replace_once
        valid_config
        ~pattern:"(features network sqlite)"
        ~replacement:"(features network network)"
    , "Duplicate feature" )
  ]
  |> List.iter (fun (name, input, expected) ->
    match Config.parse_string input with
    | Error message when String.length message >= String.length expected ->
      let found = ref false in
      for index = 0 to String.length message - String.length expected do
        if String.sub message index (String.length expected) = expected then found := true
      done;
      Alcotest.(check bool) name true !found
    | Error message -> Alcotest.failf "%s: unexpected error: %s" name message
    | Ok _ -> Alcotest.failf "%s: expected an error" name)
;;

let test_managed_adapter_config_validation () =
  let invalid =
    [ ( "unknown mode"
      , replace_once
          managed_adapter_config
          ~pattern:"(mode managed_adapter)"
          ~replacement:"(mode application_owned)"
      , "Unsupported host mode" )
    ; ( "unknown field"
      , replace_once
          managed_adapter_config
          ~pattern:"(entrypoint journal_runtime)"
          ~replacement:"(entrypoint journal_runtime) (mystery true)"
      , "Unknown host field" )
    ; ( "absolute adapter"
      , replace_once
          managed_adapter_config
          ~pattern:"lib/application_host_adapter.dart"
          ~replacement:"/tmp/application_host_adapter.dart"
      , "host.adapter must be a relative path" )
    ; ( "traversing adapter"
      , replace_once
          managed_adapter_config
          ~pattern:"lib/application_host_adapter.dart"
          ~replacement:"lib/../application_host_adapter.dart"
      , "host.adapter must not contain parent traversal" )
    ; ( "adapter outside lib"
      , replace_once
          managed_adapter_config
          ~pattern:"lib/application_host_adapter.dart"
          ~replacement:"application_host_adapter.dart"
      , "host.adapter must be inside flutter lib" )
    ; ( "generated main ownership"
      , replace_once
          managed_adapter_config
          ~pattern:"lib/application_host_adapter.dart"
          ~replacement:"lib/main.dart"
      , "host.adapter must not be the generated host" )
    ; ( "backslash adapter"
      , replace_once
          managed_adapter_config
          ~pattern:"lib/application_host_adapter.dart"
          ~replacement:"lib\\application_host_adapter.dart"
      , "host.adapter must use forward slashes" )
    ; ( "unknown launch policy"
      , replace_once
          managed_adapter_config
          ~pattern:"(launch_policy replace_existing)"
          ~replacement:"(launch_policy restart)"
      , "Unsupported host launch policy" )
    ; ( "empty entrypoint"
      , replace_once
          managed_adapter_config
          ~pattern:"(entrypoint journal_runtime)"
          ~replacement:"(entrypoint \"\")"
      , "host.entrypoint must not be empty" )
    ]
  in
  List.iter
    (fun (name, input, expected) ->
       match Config.parse_string input with
       | Error message -> Alcotest.(check bool) name true (contains message expected)
       | Ok _ -> Alcotest.failf "%s: expected an error containing %S" name expected)
    invalid
;;

let test_custom_host_config_validation () =
  Config.parse_string custom_host_config |> get_ok |> ignore;
  [ ( "custom adapter"
    , replace_once
        custom_host_config
        ~pattern:"(main lib/main.dart)"
        ~replacement:"(main lib/main.dart) (adapter lib/adapter.dart)"
    , "Unknown host field" )
  ; ( "custom entrypoint"
    , replace_once
        custom_host_config
        ~pattern:"(main lib/main.dart)"
        ~replacement:"(main lib/main.dart) (entrypoint journal)"
    , "Unknown host field" )
  ; ( "missing custom main"
    , replace_once custom_host_config ~pattern:"(main lib/main.dart)" ~replacement:""
    , "Missing host field: main" )
  ; ( "absolute custom main"
    , replace_once
        custom_host_config
        ~pattern:"lib/main.dart"
        ~replacement:"/tmp/main.dart"
    , "host.main must be a relative path" )
  ; ( "traversing custom main"
    , replace_once custom_host_config ~pattern:"lib/main.dart" ~replacement:"../main.dart"
    , "host.main must not contain parent traversal" )
  ]
  |> List.iter (fun (name, input, expected) ->
    match Config.parse_string input with
    | Error message -> Alcotest.(check bool) name true (contains message expected)
    | Ok _ -> Alcotest.failf "%s: expected an error containing %S" name expected)
;;

let test_missing_host_requires_migration () =
  let without_host =
    {|
(lang 2)

(app
 (name journal)
 (flutter_root flutter)
 (native_target app/native_embed.exe.o)
 (features network sqlite)
 (macos
  (minimum_version 26.0)
  (architectures arm64))
 (ios
  (minimum_version 15.0)
  (architectures arm64)))
|}
  in
  Config.parse_string without_host
  |> check_error_contains "app.host is required; configure managed_adapter"
;;

let test_command_plans () =
  let config = Config.parse_string valid_config |> get_ok in
  let macos =
    Plan.native_build
      ~project_root:"/work/journal"
      ~config
      ~target:Plan.Macos
      ~profile:Plan.Debug
      ~toolchain_fingerprint:"host-abc"
      ~apple_sdk_root:"/Xcode/MacOSX.sdk"
      ~apple_sdk_version:None
    |> get_ok
  in
  Alcotest.(check string) "macOS executable" "opam" macos.command.program;
  Alcotest.(check (list string))
    "macOS args"
    [ "exec"
    ; "--"
    ; "dune"
    ; "build"
    ; "--root=/work/journal"
    ; "--build-dir=/work/journal/_build/bonsai-flutter/dune/macos/host-abc/debug"
    ; "--profile=debug"
    ; "@app/bonsai-flutter-macos"
    ]
    macos.command.arguments;
  Alcotest.(check (pair string string))
    "embed env"
    ("BONSAI_FLUTTER_EMBED_OCAML", "enabled")
    (List.assoc "BONSAI_FLUTTER_EMBED_OCAML" macos.command.environment
     |> fun value -> "BONSAI_FLUTTER_EMBED_OCAML", value);
  Alcotest.(check string)
    "macOS deployment environment"
    "26.0"
    (List.assoc "MACOSX_DEPLOYMENT_TARGET" macos.command.environment);
  Alcotest.(check string)
    "macOS SDK root"
    "/Xcode/MacOSX.sdk"
    (List.assoc "BONSAI_FLUTTER_APPLE_SDK_ROOT" macos.command.environment);
  Alcotest.(check string)
    "macOS source object"
    "/work/journal/_build/bonsai-flutter/dune/macos/host-abc/debug/default/app/native_embed.exe.o"
    macos.source_object;
  Alcotest.(check string)
    "macOS staged object"
    "/work/journal/_build/bonsai-flutter/artifacts/macos/arm64/debug/native_embed.exe.o"
    macos.staged_object;
  let ios =
    Plan.native_build
      ~project_root:"/work/journal"
      ~config
      ~target:Plan.Iphoneos
      ~profile:Plan.Release
      ~toolchain_fingerprint:"sdk-def"
      ~apple_sdk_root:"/Xcode/iPhoneOS.sdk"
      ~apple_sdk_version:(Some "26.0")
    |> get_ok
  in
  Alcotest.(check string) "iOS executable" "opam" ios.command.program;
  Alcotest.(check (list string))
    "iOS args"
    [ "exec"
    ; "--switch=bonsai-flutter-ios"
    ; "--"
    ; "dune"
    ; "build"
    ; "--root=/work/journal"
    ; "--build-dir=/work/journal/_build/bonsai-flutter/dune/iphoneos/sdk-def/release"
    ; "--profile=release"
    ; "-x"
    ; "ios"
    ; "@app/bonsai-flutter-ios"
    ]
    ios.command.arguments;
  Alcotest.(check bool)
    "macOS environment is not leaked to iPhoneOS"
    false
    (List.mem_assoc "MACOSX_DEPLOYMENT_TARGET" ios.command.environment);
  Alcotest.(check string)
    "iOS SDK version"
    "26.0"
    (List.assoc "SDK" ios.command.environment);
  Alcotest.(check string)
    "iOS deployment target"
    "15.0"
    (List.assoc "VER" ios.command.environment);
  Alcotest.(check string)
    "iOS source object"
    "/work/journal/_build/bonsai-flutter/dune/iphoneos/sdk-def/release/default.ios/app/native_embed.exe.o"
    ios.source_object;
  Alcotest.(check string)
    "iOS staged object"
    "/work/journal/_build/bonsai-flutter/artifacts/ios/iphoneos/arm64/release/native_embed.exe.o"
    ios.staged_object;
  List.iter
    (fun path ->
       Alcotest.(check bool)
         ("project-local path: " ^ path)
         true
         (String.starts_with ~prefix:"/work/journal/_build/bonsai-flutter/" path))
    [ ios.build_directory
    ; ios.source_object
    ; ios.staged_object
    ; ios.manifest
    ; ios.log
    ; ios.lock
    ];
  Plan.native_build
    ~project_root:"/work/journal"
    ~config
    ~target:Plan.Iphoneos
    ~profile:Plan.Debug
    ~toolchain_fingerprint:"../../../shared"
    ~apple_sdk_root:"/Xcode/iPhoneOS.sdk"
    ~apple_sdk_version:(Some "26.0")
  |> check_error_contains "Invalid toolchain fingerprint"
;;

let test_fixed_iphoneos_switch () =
  Alcotest.(check string) "fixed switch" "bonsai-flutter-ios" Plan.iphoneos_switch;
  valid_config
  |> replace_once
       ~pattern:"(minimum_version 15.0)"
       ~replacement:"(minimum_version 15.0)\n  (switch local-ios)"
  |> Config.parse_string
  |> check_error_contains "Unknown ios field: switch"
;;

let valid_sdk_manifest =
  {|
(sdk
 (format_version 1)
 (bonsai_flutter_version 0.1.0~dev)
 (bonsai_flutter_source
  b570881ba27e8e376dc231ef014506d37ce8e662
  sha256
  253c523dc0fb2d9ea931e82f3b9174613ff6519e3718ad650f550ae02593d4dc)
 (abi_version 2)
 (ocaml_version 5.1.1)
 (dune_version_range 3.17 4.0)
 (cross_compiler ocaml-ios64 5.1.1)
 (findlib_toolchain ios)
 (architecture arm64)
 (platform iphoneos)
 (minimum_deployment_target 15.0)
 (package_universe_digest package-digest)
 (target_components_digest component-digest)
 (required_frameworks Foundation Security)
 (required_system_libraries sqlite3)
 (build_recipe_revision 2)
 (packages
  (base v0.17.0)
  (bonsai_flutter 0.1.0~dev)
  (core v0.17.0))
 (libraries
  (base base v0.17.0 (base base.md5))
  (bonsai_flutter.ui bonsai_flutter 0.1.0~dev
   (bonsai_flutter.driver bonsai_flutter.ui))))
|}
;;

let parse_sdk_manifest source = Sdk.Manifest.parse source |> get_ok

let test_sdk_manifest_contract () =
  let manifest = parse_sdk_manifest valid_sdk_manifest in
  Sdk.Manifest.validate
    manifest
    ~bonsai_flutter_version:"0.1.0~dev"
    ~abi_version:"2"
    ~minimum_deployment_target:"15.0"
  |> get_ok;
  Sdk.Manifest.validate_packages
    manifest
    [ "bonsai_flutter", "0.1.0~dev"; "base", "v0.17.0" ]
  |> get_ok;
  Sdk.Manifest.validate_packages manifest [ "missing", "1.0" ]
  |> check_error_contains
       "Package missing.1.0 is not in the fixed iPhoneOS SDK package universe";
  Sdk.Manifest.validate_packages manifest [ "base", "v0.18.0" ]
  |> check_error_contains
       "Package base.v0.18.0 conflicts with iPhoneOS SDK package base.v0.17.0";
  Sdk.Manifest.validate
    (valid_sdk_manifest
     |> replace_once ~pattern:"(platform iphoneos)" ~replacement:"(platform macos)"
     |> parse_sdk_manifest)
    ~bonsai_flutter_version:"0.1.0~dev"
    ~abi_version:"2"
    ~minimum_deployment_target:"15.0"
  |> check_error_contains "expected Apple platform iphoneos";
  Sdk.Manifest.validate
    manifest
    ~bonsai_flutter_version:"0.2.0"
    ~abi_version:"2"
    ~minimum_deployment_target:"15.0"
  |> check_error_contains
       "The iPhoneOS switch SDK manifest is incompatible with bonsai-flutter 0.2.0";
  Sdk.Manifest.validate
    manifest
    ~bonsai_flutter_version:"0.1.0~dev"
    ~abi_version:"2"
    ~minimum_deployment_target:"14.0"
  |> check_error_contains "minimum deployment target 14.0 is unsupported";
  Sdk.Manifest.validate
    (valid_sdk_manifest
     |> replace_once ~pattern:"(abi_version 2)" ~replacement:"(abi_version 1)"
     |> parse_sdk_manifest)
    ~bonsai_flutter_version:"0.1.0~dev"
    ~abi_version:"2"
    ~minimum_deployment_target:"15.0"
  |> check_error_contains
       "Run: bonsai-flutter toolchain remove iphoneos; bonsai-flutter toolchain install \
        iphoneos";
  valid_sdk_manifest
  |> replace_once
       ~pattern:" (target_components_digest component-digest)\n"
       ~replacement:""
  |> Sdk.Manifest.parse
  |> check_error_contains "Missing SDK manifest field: target_components_digest"
;;

let test_sdk_rejects_framework_source_drift () =
  let stale_manifest =
    valid_sdk_manifest
    |> replace_once
         ~pattern:"b570881ba27e8e376dc231ef014506d37ce8e662"
         ~replacement:"ea5e96b4dd38795a901720c80e1ffc9eb684b86c"
    |> replace_once
         ~pattern:"253c523dc0fb2d9ea931e82f3b9174613ff6519e3718ad650f550ae02593d4dc"
         ~replacement:"c20edc77779c24c411854a19d234887615a6ba0a352784d35a970fb0a7d148a5"
    |> parse_sdk_manifest
  in
  Sdk.Manifest.validate
    stale_manifest
    ~bonsai_flutter_version:"0.1.0~dev"
    ~abi_version:"2"
    ~minimum_deployment_target:"15.0"
  |> check_error_contains
       "Run: bonsai-flutter toolchain remove iphoneos; bonsai-flutter toolchain install \
        iphoneos"
;;

let test_sdk_rejects_unadvertised_framework_source_identity () =
  let legacy_manifest =
    valid_sdk_manifest
    |> replace_once
         ~pattern:
           " (bonsai_flutter_source\n\
           \  b570881ba27e8e376dc231ef014506d37ce8e662\n\
           \  sha256\n\
           \  253c523dc0fb2d9ea931e82f3b9174613ff6519e3718ad650f550ae02593d4dc)\n"
         ~replacement:""
    |> replace_once ~pattern:"(abi_version 2)" ~replacement:"(abi_version 1)"
    |> parse_sdk_manifest
  in
  Sdk.Manifest.validate
    legacy_manifest
    ~bonsai_flutter_version:"0.1.0~dev"
    ~abi_version:"1"
    ~minimum_deployment_target:"15.0"
  |> check_error_contains
       "Run: bonsai-flutter toolchain remove iphoneos; bonsai-flutter toolchain install \
        iphoneos"
;;

let application_lock =
  {|opam-version: "2.0"
name: "demo"
version: "0.1.0"
depends: [
  "base" {= "v0.17.0"}
  "bonsai_flutter" {= "0.1.0~dev"}
  "unreachable" {= "99.0"}
]
|}
;;

let test_sdk_validates_only_reachable_application_lock_subset () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "application-lock" in
  let lock = Filename.concat root "demo.opam.locked" in
  write_file lock application_lock;
  let manifest = parse_sdk_manifest valid_sdk_manifest in
  Alcotest.(check (list (pair string string)))
    "reachable package subset"
    [ "base", "v0.17.0"; "bonsai_flutter", "0.1.0~dev" ]
    (Sdk.validate_application_lock
       ~project_root:root
       ~application_name:"demo"
       ~reachable_libraries:[ "bonsai_flutter.ui"; "base" ]
       manifest
     |> get_ok);
  Sdk.validate_application_lock
    ~project_root:root
    ~application_name:"demo"
    ~reachable_libraries:[ "unsupported.library" ]
    manifest
  |> check_error_contains
       "Findlib library unsupported.library is not provided by the iPhoneOS SDK";
  write_file
    lock
    (application_lock
     |> replace_once
          ~pattern:"\"base\" {= \"v0.17.0\"}"
          ~replacement:"\"base\" {= \"v0.18.0\"}");
  Sdk.validate_application_lock
    ~project_root:root
    ~application_name:"demo"
    ~reachable_libraries:[ "base" ]
    manifest
  |> check_error_contains
       "Package base.v0.18.0 conflicts with reachable SDK package base.v0.17.0";
  write_file
    lock
    (application_lock
     |> replace_once ~pattern:"  \"base\" {= \"v0.17.0\"}\n" ~replacement:"");
  Sdk.validate_application_lock
    ~project_root:root
    ~application_name:"demo"
    ~reachable_libraries:[ "base" ]
    manifest
  |> check_error_contains
       "Reachable SDK package base.v0.17.0 is missing from demo.opam.locked";
  write_file
    lock
    (application_lock
     |> replace_once
          ~pattern:"\"base\" {= \"v0.17.0\"}"
          ~replacement:"\"base\" {>= \"v0.17.0\"}");
  Sdk.validate_application_lock
    ~project_root:root
    ~application_name:"demo"
    ~reachable_libraries:[ "base" ]
    manifest
  |> check_error_contains "Dependency base in demo.opam.locked is not pinned exactly"
;;

let test_sdk_manifest_fingerprint_is_canonical () =
  let compact = parse_sdk_manifest valid_sdk_manifest in
  let expanded =
    valid_sdk_manifest
    |> replace_once
         ~pattern:"(architecture arm64)"
         ~replacement:"(architecture       arm64)"
    |> parse_sdk_manifest
  in
  let first = Sdk.Manifest.fingerprint compact in
  let second = Sdk.Manifest.fingerprint expanded in
  Alcotest.(check string) "whitespace independent" first second;
  Alcotest.(check int) "SHA-256 length" 64 (String.length first);
  let changed =
    valid_sdk_manifest
    |> replace_once ~pattern:"component-digest" ~replacement:"changed-digest"
    |> parse_sdk_manifest
    |> Sdk.Manifest.fingerprint
  in
  Alcotest.(check bool) "component changes identity" true (first <> changed)
;;

let test_sdk_preflight_is_read_only () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "sdk-preflight" |> Unix.realpath in
  let project_root = Filename.concat root "project" in
  let prefix = Filename.concat root "switch-prefix" in
  let bin = Filename.concat root "bin" in
  let command_log = Filename.concat root "commands.log" in
  Scaffold.ensure_directory project_root;
  [ "dune"; "ocamlc"; "ocamlfind" ]
  |> List.iter (fun program ->
    write_executable (Filename.concat prefix ("bin/" ^ program)) "#!/bin/sh\nexit 0\n");
  let manifest_path =
    Filename.concat prefix "share/bonsai_flutter_ios_sdk/manifest.sexp"
  in
  write_file manifest_path valid_sdk_manifest;
  write_executable
    (Filename.concat bin "opam")
    (command_logger "opam"
     ^ Printf.sprintf
         {|if test "$1" = switch && test "$2" = show; then
  printf '%%s\n' 'bonsai-flutter-ios'
elif test "$1" = var && test "$2" = --switch=bonsai-flutter-ios; then
  printf '%%s\n' '%s'
elif test "$1" = exec && test "$4" = dune; then
  printf '%%s\n' '3.18.2'
elif test "$1" = exec && test "$4" = ocamlc; then
  printf '%%s\n' '5.1.1'
elif test "$1" = exec && test "$4" = ocamlfind; then
  printf '%%s\n' '%s/lib/ios'
else
  exit 64
fi
|}
         prefix
         prefix);
  let manifest_mtime = (Unix.stat manifest_path).st_mtime in
  with_environment
    [ "PATH", bin ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH")
    ; "COMMAND_LOG", command_log
    ]
    (fun () ->
       let result =
         Sdk.preflight
           ~project_root
           ~bonsai_flutter_version:"0.1.0~dev"
           ~abi_version:"2"
           ~minimum_deployment_target:"15.0"
           ~required_packages:[ "base", "v0.17.0" ]
         |> get_ok
       in
       Alcotest.(check string) "global switch prefix" prefix result.switch_prefix;
       Alcotest.(check string)
         "manifest fingerprint"
         (valid_sdk_manifest |> parse_sdk_manifest |> Sdk.Manifest.fingerprint)
         result.fingerprint);
  Alcotest.(check (float 0.))
    "manifest remains untouched"
    manifest_mtime
    (Unix.stat manifest_path).st_mtime;
  let commands = read_file command_log |> non_empty_lines in
  Alcotest.(check int) "five read-only opam calls" 5 (List.length commands);
  Alcotest.(check bool)
    "switch is selected explicitly"
    true
    (List.for_all
       (fun command -> contains command "--switch=bonsai-flutter-ios")
       commands);
  Alcotest.(check bool)
    "no mutation command"
    false
    (List.exists
       (fun command ->
          contains command " install "
          || contains command " remove "
          || contains command " switch create ")
       commands)
;;

let test_sdk_preflight_reports_missing_switch () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "missing-switch" |> Unix.realpath in
  let bin = Filename.concat root "bin" in
  Scaffold.ensure_directory (Filename.concat root "project");
  write_executable (Filename.concat bin "opam") "#!/bin/sh\nexit 2\n";
  with_environment
    [ "PATH", bin ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH") ]
    (fun () ->
       Sdk.preflight
         ~project_root:(Filename.concat root "project")
         ~bonsai_flutter_version:"0.1.0~dev"
         ~abi_version:"2"
         ~minimum_deployment_target:"15.0"
         ~required_packages:[]
       |> check_error_contains
            "The global iPhoneOS switch \"bonsai-flutter-ios\" is missing. Run: \
             bonsai-flutter toolchain install iphoneos")
;;

let rec repository_files root relative =
  let path = Filename.concat root relative in
  match (Unix.lstat path).st_kind with
  | Unix.S_DIR ->
    Sys.readdir path
    |> Array.to_list
    |> List.sort String.compare
    |> List.concat_map (fun name ->
      repository_files
        root
        (if relative = "" then name else Filename.concat relative name))
  | Unix.S_REG -> if relative = "repository.sexp" then [] else [ relative ]
  | Unix.S_LNK | Unix.S_CHR | Unix.S_BLK | Unix.S_FIFO | Unix.S_SOCK ->
    Alcotest.failf "invalid repository entry: %s" path
;;

let repository_digest root =
  let canonical =
    repository_files root ""
    |> List.map (fun relative ->
      relative ^ "\000" ^ Artifact.digest (Filename.concat root relative))
    |> String.concat "\000"
  in
  let temporary = Filename.temp_file "bonsai-flutter-repository" ".digest-input" in
  Fun.protect
    ~finally:(fun () -> Sys.remove temporary)
    (fun () ->
       write_file temporary canonical;
       Artifact.digest temporary)
;;

let repository_lock ~digest ~source_digest ~package_digest ~archive_digest =
  Printf.sprintf
    {|(repository
 (format_version 1)
 (repository_version 0.1.0)
 (repository_snapshot_sha256 %s)
 (source_lock vendor/opam-ios/runtime-closure.lock %s)
 (package_universe package-universe.lock %s)
 (source_archives source-archives.lock %s)
 (default_repository https://github.com/RCmerci/opam-repository.git c98b21e24c088665ccae4c3b53eadadd3b755b15)
 (cross_repository https://github.com/ocaml-cross/opam-cross-ios.git 8380b52b0154752c26c6e221c04fbced3320aa48)
 (compiler ocaml-base-compiler 5.1.1)
 (sdk_package bonsai_flutter_ios_sdk 0.1.0~dev.2))
|}
    digest
    source_digest
    package_digest
    archive_digest
;;

let rec source_root directory =
  if Sys.file_exists (Filename.concat directory "tool/ios/opam-repository/0.1.0")
  then directory
  else (
    let parent = Filename.dirname directory in
    if parent = directory
    then Alcotest.fail "repository source root was not found"
    else source_root parent)
;;

let write_repository_fixture root =
  let framework_root =
    root |> Filename.dirname |> Filename.dirname |> Filename.dirname |> Filename.dirname
  in
  let source_lock =
    Filename.concat framework_root "vendor/opam-ios/runtime-closure.lock"
  in
  write_file
    source_lock
    "# \
     package|version|role|capability|build-mechanism|source|sha256|components|dependencies\n";
  write_file (Filename.concat root "repo") "opam-version: \"2.0\"\n";
  write_file
    (Filename.concat root "package-universe.lock")
    "# package|version|repository|metadata-sha256\n";
  write_file
    (Filename.concat root "source-archives.lock")
    "# package|version|source|algorithm|checksum\n";
  write_file
    (Filename.concat
       root
       "packages/bonsai_flutter_ios_sdk/bonsai_flutter_ios_sdk.0.1.0~dev.2/opam")
    {|opam-version: "2.0"
synopsis: "Bonsai Flutter iPhoneOS SDK"
maintainer: "bonsai_flutter contributors"
depends: [
  "ocaml-base-compiler" {= "5.1.1"}
]
|};
  write_file
    (Filename.concat root "repository.sexp")
    (repository_lock
       ~digest:(repository_digest root)
       ~source_digest:(Artifact.digest source_lock)
       ~package_digest:(Artifact.digest (Filename.concat root "package-universe.lock"))
       ~archive_digest:(Artifact.digest (Filename.concat root "source-archives.lock")))
;;

let test_ios_opam_repository_release_contract () =
  let source_root = source_root (Sys.getcwd ()) in
  let repository = Filename.concat source_root "tool/ios/opam-repository/0.1.0" in
  if not (Sys.file_exists repository)
  then Alcotest.failf "versioned iOS opam repository is missing: %s" repository;
  let lock = Filename.concat repository "repository.sexp" in
  let meta =
    Filename.concat
      repository
      "packages/bonsai_flutter_ios_sdk/bonsai_flutter_ios_sdk.0.1.0~dev.2/opam"
  in
  let cross_compiler_opam =
    Filename.concat repository "packages/ocaml-ios64/ocaml-ios64.5.1.1/opam"
  in
  let ios_configuration_opam =
    Filename.concat repository "packages/conf-ios/conf-ios.4/opam"
  in
  let package_lock = Filename.concat repository "package-universe.lock" in
  let source_archive_lock = Filename.concat repository "source-archives.lock" in
  let framework_url =
    Filename.concat repository "packages/bonsai_flutter/bonsai_flutter.0.1.0~dev/url"
  in
  let sdk_files =
    Filename.concat
      repository
      "packages/bonsai_flutter_ios_sdk/bonsai_flutter_ios_sdk.0.1.0~dev.2/files"
  in
  let sdk_manifest = Filename.concat sdk_files "manifest.sexp" in
  let installed_package_lock = Filename.concat sdk_files "package-lock.sexp" in
  let sdk_builder = Filename.concat sdk_files "build-installed-sdk.sh" in
  Alcotest.(check bool) "repository lock" true (Sys.file_exists lock);
  Alcotest.(check bool) "SDK meta-package" true (Sys.file_exists meta);
  Alcotest.(check bool)
    "fetchable cross compiler source"
    true
    (contains (read_file cross_compiler_opam) "ocaml/archive/5.1.1.tar.gz");
  let ios_configuration = read_file ios_configuration_opam in
  Alcotest.(check bool)
    "fixed iPhoneOS architecture"
    true
    (contains ios_configuration "arm64" && contains ios_configuration "arm-apple-darwin");
  Alcotest.(check bool)
    "fixed iPhoneOS deployment target"
    true
    (contains ios_configuration "miphoneos-version-min=15.0");
  Alcotest.(check bool)
    "configuration has no caller-owned architecture variables"
    false
    (contains ios_configuration "${ARCH}" || contains ios_configuration "${SUBARCH}");
  Alcotest.(check bool) "package universe lock" true (Sys.file_exists package_lock);
  Alcotest.(check bool) "source archive lock" true (Sys.file_exists source_archive_lock);
  let expected_framework_revision = "b570881ba27e8e376dc231ef014506d37ce8e662" in
  let expected_framework_sha256 =
    "253c523dc0fb2d9ea931e82f3b9174613ff6519e3718ad650f550ae02593d4dc"
  in
  let framework_url_contents = read_file framework_url in
  Alcotest.(check bool)
    "framework package source identity"
    true
    (contains framework_url_contents expected_framework_revision
     && contains framework_url_contents expected_framework_sha256);
  Alcotest.(check bool) "installable SDK manifest" true (Sys.file_exists sdk_manifest);
  Alcotest.(check bool)
    "installable SDK package lock"
    true
    (Sys.file_exists installed_package_lock);
  Alcotest.(check bool) "installable SDK builder" true (Sys.file_exists sdk_builder);
  let sdk_manifest_contents = read_file sdk_manifest in
  Alcotest.(check bool)
    "SDK manifest framework source identity and protocol ABI"
    true
    (contains sdk_manifest_contents expected_framework_revision
     && contains sdk_manifest_contents expected_framework_sha256
     && contains sdk_manifest_contents "(abi_version 2)"
     && contains sdk_manifest_contents "(build_recipe_revision 2)");
  Alcotest.(check bool)
    "SDK manifest owns target standard libraries through the cross compiler"
    true
    (contains sdk_manifest_contents "(ocaml-ios64 5.1.1)"
     && contains
          sdk_manifest_contents
          "(threads ocaml-ios64 5.1.1 (threads unix str dynlink))"
     && contains
          sdk_manifest_contents
          "(unix ocaml-ios64 5.1.1 (threads unix str dynlink))"
     && contains
          sdk_manifest_contents
          "(str ocaml-ios64 5.1.1 (threads unix str dynlink))"
     && contains
          sdk_manifest_contents
          "(dynlink ocaml-ios64 5.1.1 (threads unix str dynlink))");
  let lock_contents = read_file lock in
  Alcotest.(check bool)
    "default repository commit"
    true
    (contains lock_contents "9fdd0666a192f1896963cf446f37f0c691bbd3db");
  Alcotest.(check bool)
    "cross repository commit"
    true
    (contains lock_contents "8380b52b0154752c26c6e221c04fbced3320aa48");
  let actual_repository_digest = repository_digest repository in
  Alcotest.(check bool)
    ("repository snapshot digest: " ^ actual_repository_digest)
    true
    (contains lock_contents actual_repository_digest);
  Alcotest.(check bool)
    "source checksum lock digest"
    true
    (contains
       lock_contents
       (Artifact.digest
          (Filename.concat source_root "vendor/opam-ios/runtime-closure.lock")));
  let meta_contents = read_file meta in
  Alcotest.(check bool)
    "all framework source records advertise one identity"
    true
    (contains (read_file source_archive_lock) expected_framework_revision
     && contains (read_file source_archive_lock) expected_framework_sha256
     && contains meta_contents expected_framework_revision
     && contains meta_contents expected_framework_sha256);
  Alcotest.(check bool)
    "meta installs manifest"
    true
    (contains meta_contents "bonsai_flutter_ios_sdk/manifest.sexp");
  Alcotest.(check bool)
    "meta installs package lock"
    true
    (contains meta_contents "bonsai_flutter_ios_sdk/package-lock.sexp");
  Alcotest.(check bool)
    "meta builds target SDK"
    true
    (contains meta_contents "build-installed-sdk.sh");
  Alcotest.(check bool)
    "meta fetches the checksummed framework source before the sandboxed build"
    true
    (contains meta_contents "extra-source \"bonsai_flutter.tar.gz\""
     && contains
          meta_contents
          "https://github.com/RCmerci/bonsai_flutter/archive/b570881ba27e8e376dc231ef014506d37ce8e662.tar.gz"
     && contains
          meta_contents
          "sha256=253c523dc0fb2d9ea931e82f3b9174613ff6519e3718ad650f550ae02593d4dc");
  Alcotest.(check bool)
    "meta fetches checksummed runtime sources before the sandboxed build"
    true
    (contains
       meta_contents
       "extra-source \
        \"runtime-jst-config-2cf345e33bed0ee4c325667e77dfc5bee8f12afd56318b7c9acf81ec875ecf6e.archive\""
     && contains
          meta_contents
          "https://github.com/janestreet/jst-config/archive/refs/tags/v0.17.0.tar.gz"
     && contains
          meta_contents
          "sha256=2cf345e33bed0ee4c325667e77dfc5bee8f12afd56318b7c9acf81ec875ecf6e");
  Alcotest.(check bool)
    "meta merges the SDK contents into the compiler sysroot"
    true
    (contains
       meta_contents
       "[\"cp\" \"-R\" \".bonsai_flutter_ios_sdk/stage/ios-sysroot/.\" \
        \"%{prefix}%/ios-sysroot/\"]");
  Alcotest.(check bool)
    "meta checksums target SDK builder"
    true
    (contains meta_contents "extra-files: ["
     && contains meta_contents "[\"build-installed-sdk.sh\" \"sha256=");
  let sdk_builder_contents = read_file sdk_builder in
  let runtime_builder_contents =
    read_file (Filename.concat sdk_files "build-runtime-package.sh")
  in
  Alcotest.(check bool)
    "builder requires the selected global switch prefix"
    true
    (contains sdk_builder_contents "OPAM_SWITCH_PREFIX");
  Alcotest.(check bool)
    "builder has no removed framework build root"
    false
    (contains sdk_builder_contents "_build/ios"
     || contains sdk_builder_contents "switches/iphoneos");
  Alcotest.(check bool)
    "builder enters the pinned framework source instead of repeating Dune root"
    true
    (contains sdk_builder_contents "cd \"$framework_source\""
     && not (contains sdk_builder_contents "--root=\"$framework_source\""));
  Alcotest.(check bool)
    "builder consumes the opam-fetched framework archive"
    true
    (contains
       sdk_builder_contents
       "framework_archive_source=\"$script_directory/bonsai_flutter.tar.gz\""
     && not (contains sdk_builder_contents "framework_source_url="));
  Alcotest.(check bool)
    "builder verifies the current framework archive"
    true
    (contains
       sdk_builder_contents
       "framework_source_sha256='253c523dc0fb2d9ea931e82f3b9174613ff6519e3718ad650f550ae02593d4dc'");
  Alcotest.(check bool)
    "runtime builder consumes opam-fetched archives"
    true
    (contains
       runtime_builder_contents
       "source_archive_source=\"$SDK_ASSET_ROOT/runtime-$package_name-$source_sha256.archive\""
     && not (contains runtime_builder_contents "curl"));
  Alcotest.(check bool)
    "runtime builder keeps target dependencies in writable package work"
    true
    (contains runtime_builder_contents "SDK_PACKAGE_WORK_ROOT/dependencies/gmp"
     && not (contains runtime_builder_contents "$switch_prefix/ios-deps"));
  Alcotest.(check bool)
    "builder stages the iOS cross-context install tree without nesting the sysroot"
    true
    (contains
       sdk_builder_contents
       "framework_install_root=\"$framework_build/install/default.ios\""
     && contains
          sdk_builder_contents
          "cp -RL \"$framework_install_root/.\" \"$stage_root/ios-sysroot/\""
     && not (contains sdk_builder_contents "dune install"));
  let package_rows =
    read_file package_lock |> non_empty_lines |> List.filter (fun line -> line.[0] <> '#')
  in
  Alcotest.(check int) "complete solved package universe" 243 (List.length package_rows);
  let package_keys = ref [] in
  package_rows
  |> List.iter (fun line ->
    match String.split_on_char '|' line with
    | [ package; version; repository_name; metadata_sha ] ->
      let key = package ^ "." ^ version in
      package_keys := (package, version) :: !package_keys;
      Alcotest.(check bool)
        (key ^ " repository provenance")
        true
        (List.mem repository_name [ "local"; "ios-cross"; "default" ]);
      Alcotest.(check int) (key ^ " metadata SHA-256") 64 (String.length metadata_sha);
      if package <> "bonsai_flutter_ios_sdk"
      then
        Alcotest.(check bool)
          (key ^ " exact meta dependency")
          true
          (contains meta_contents (Printf.sprintf "\"%s\" {= \"%s\"}" package version))
    | _ -> Alcotest.failf "invalid package universe row: %s" line);
  let package_keys = List.rev !package_keys in
  Alcotest.(check (list (pair string string)))
    "sorted unique package universe"
    (List.sort_uniq Stdlib.compare package_keys)
    package_keys;
  Alcotest.(check bool)
    "package universe digest"
    true
    (contains lock_contents (Artifact.digest package_lock));
  read_file source_archive_lock
  |> non_empty_lines
  |> List.filter (fun line -> line.[0] <> '#')
  |> List.iter (fun line ->
    match String.split_on_char '|' line with
    | [ package; version; source; checksum_algorithm; source_checksum ] ->
      Alcotest.(check bool)
        (package ^ "." ^ version ^ " belongs to package universe")
        true
        (List.mem (package, version) package_keys);
      Alcotest.(check bool)
        (package ^ "." ^ version ^ " immutable source URL")
        true
        (contains source "://");
      let expected_checksum_length =
        match checksum_algorithm with
        | "sha256" -> 64
        | "sha512" -> 128
        | algorithm -> Alcotest.failf "unsupported source checksum: %s" algorithm
      in
      Alcotest.(check int)
        (package ^ "." ^ version ^ " source checksum")
        expected_checksum_length
        (String.length source_checksum)
    | _ -> Alcotest.failf "invalid source archive row: %s" line);
  Alcotest.(check bool)
    "source archive digest"
    true
    (contains lock_contents (Artifact.digest source_archive_lock));
  let closure_lock = read_file (Filename.concat sdk_files "supported-closure.lock") in
  let manifest = read_file sdk_manifest |> parse_sdk_manifest in
  Alcotest.(check string)
    "installed package universe digest"
    (Artifact.digest installed_package_lock)
    manifest.package_universe_digest;
  closure_lock
  |> non_empty_lines
  |> List.filter (fun line -> line.[0] <> '#')
  |> List.iter (fun line ->
    match String.split_on_char '|' line with
    | package
      :: version
      :: role
      :: _capability
      :: _mechanism
      :: _source
      :: sha
      :: components
      :: _ ->
      Alcotest.(check int) (package ^ " source SHA-256") 64 (String.length sha);
      if package = "gmp-sys-ios"
      then
        Alcotest.(check bool)
          "target-build pseudo-package source"
          true
          (contains meta_contents ("runtime-gmp-sys-ios-" ^ sha ^ ".archive"))
      else
        Alcotest.(check bool)
          (package ^ " exact meta dependency")
          true
          (contains meta_contents (Printf.sprintf "\"%s\" {= \"%s\"}" package version));
      if List.mem role [ "target-build"; "target-package" ] && components <> "-"
      then (
        let expected_components = String.split_on_char ',' components in
        expected_components
        |> List.iter (fun library ->
          match Sdk.Manifest.String_map.find_opt library manifest.libraries with
          | None -> Alcotest.failf "SDK manifest lacks findlib library %s" library
          | Some mapping ->
            Alcotest.(check string) (library ^ " package") package mapping.package;
            Alcotest.(check string) (library ^ " version") version mapping.version;
            Alcotest.(check (list string))
              (library ^ " components")
              expected_components
              mapping.components))
    | _ -> Alcotest.failf "invalid runtime closure row: %s" line);
  [ "bonsai_flutter.driver"
  ; "bonsai_flutter.native_backend"
  ; "bonsai_flutter.spec_impl"
  ; "bonsai_flutter.ui"
  ]
  |> List.iter (fun library ->
    match Sdk.Manifest.String_map.find_opt library manifest.libraries with
    | None -> Alcotest.failf "SDK manifest lacks framework library %s" library
    | Some mapping ->
      Alcotest.(check string) (library ^ " package") "bonsai_flutter" mapping.package;
      Alcotest.(check string) (library ^ " version") "0.1.0~dev" mapping.version);
  Process_runner.run
    { Plan.program = "opam"
    ; arguments = [ "lint"; meta ]
    ; working_directory = repository
    ; environment = []
    }
  |> get_ok
;;

type toolchain_fixture =
  { toolchain_root : string
  ; toolchain_bin : string
  ; toolchain_prefix : string
  ; toolchain_log : string
  ; toolchain_manifest : string
  }

let create_toolchain_fixture () =
  let toolchain_root =
    Filename.temp_dir "bonsai-flutter-tool" "toolchain" |> Unix.realpath
  in
  let toolchain_bin = Filename.concat toolchain_root "bin" in
  let toolchain_prefix = Filename.concat toolchain_root "switch-prefix" in
  let toolchain_log = Filename.concat toolchain_root "commands.log" in
  let toolchain_manifest =
    Filename.concat toolchain_prefix "share/bonsai_flutter_ios_sdk/manifest.sexp"
  in
  [ "dune"; "ocamlc"; "ocamlfind" ]
  |> List.iter (fun program ->
    write_executable
      (Filename.concat toolchain_prefix ("bin/" ^ program))
      "#!/bin/sh\nexit 0\n");
  write_file toolchain_manifest valid_sdk_manifest;
  write_executable
    (Filename.concat toolchain_bin "opam")
    (command_logger "opam"
     ^ Printf.sprintf
         {|case " $* " in
  *" switch show --switch=bonsai-flutter-ios "*)
    printf '%%s\n' 'bonsai-flutter-ios' ;;
  *" var --switch=bonsai-flutter-ios prefix "*)
    printf '%%s\n' '%s' ;;
  *" exec --switch=bonsai-flutter-ios -- dune --version "*)
    printf '%%s\n' '3.18.2' ;;
  *" exec --switch=bonsai-flutter-ios -- ocamlc -version "*)
    printf '%%s\n' '5.1.1' ;;
  *" exec --switch=bonsai-flutter-ios -- ocamlfind -toolchain ios printconf path "*)
    printf '%%s\n' '%s/lib/ios' ;;
  *" switch remove --yes bonsai-flutter-ios "*)
    exit "${REMOVE_EXIT:-0}" ;;
  *) exit 64 ;;
esac
|}
         toolchain_prefix
         toolchain_prefix);
  { toolchain_root; toolchain_bin; toolchain_prefix; toolchain_log; toolchain_manifest }
;;

let with_toolchain_fixture ?(environment = []) fixture f =
  with_environment
    ([ ( "PATH"
       , fixture.toolchain_bin ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH") )
     ; "COMMAND_LOG", fixture.toolchain_log
     ]
     @ environment)
    f
;;

let test_toolchain_show_and_verify_are_read_only () =
  let fixture = create_toolchain_fixture () in
  let manifest_mtime = (Unix.stat fixture.toolchain_manifest).st_mtime in
  let info =
    with_toolchain_fixture fixture (fun () ->
      Toolchain.show ~working_directory:fixture.toolchain_root |> get_ok)
  in
  Alcotest.(check string) "fixed switch" "bonsai-flutter-ios" info.switch;
  Alcotest.(check string) "switch prefix" fixture.toolchain_prefix info.prefix;
  Alcotest.(check string) "SDK version" "0.1.0~dev" info.bonsai_flutter_version;
  Alcotest.(check string) "target" "iphoneos/arm64" info.target;
  let verified =
    with_toolchain_fixture fixture (fun () ->
      Toolchain.verify ~working_directory:fixture.toolchain_root |> get_ok)
  in
  Alcotest.(check string)
    "show and verify fingerprint"
    info.fingerprint
    verified.fingerprint;
  Alcotest.(check (float 0.))
    "manifest remains untouched"
    manifest_mtime
    (Unix.stat fixture.toolchain_manifest).st_mtime;
  let commands = read_file fixture.toolchain_log |> non_empty_lines in
  Alcotest.(check bool)
    "show and verify never mutate opam"
    false
    (List.exists
       (fun command ->
          contains command "\tinstall\t"
          || contains command "\tremove\t"
          || contains command "\tcreate\t")
       commands)
;;

let test_toolchain_remove_uses_only_fixed_switch () =
  let fixture = create_toolchain_fixture () in
  with_toolchain_fixture fixture (fun () ->
    Toolchain.remove ~working_directory:fixture.toolchain_root |> get_ok);
  Alcotest.(check (list string))
    "fixed destructive command"
    [ String.concat
        "\t"
        [ "opam"
        ; fixture.toolchain_root
        ; "switch"
        ; "remove"
        ; "--yes"
        ; "bonsai-flutter-ios"
        ]
    ]
    (read_file fixture.toolchain_log |> non_empty_lines);
  write_file fixture.toolchain_log "";
  with_toolchain_fixture
    ~environment:[ "REMOVE_EXIT", "31" ]
    fixture
    (fun () ->
       Toolchain.remove ~working_directory:fixture.toolchain_root
       |> check_error_contains "opam exited with status 31")
;;

let test_toolchain_install_uses_locked_repository_and_exact_sdk () =
  let fixture = create_toolchain_fixture () in
  let framework_root = Filename.concat fixture.toolchain_root "framework" in
  let repository = Filename.concat framework_root "tool/ios/opam-repository/0.1.0" in
  write_repository_fixture repository;
  write_file fixture.toolchain_log "";
  write_executable
    (Filename.concat fixture.toolchain_bin "opam")
    (command_logger "opam"
     ^ {|case " $* " in
  *" switch list --short "*)
    test -z "${SWITCH_EXISTS:-}" || printf '%s\n' 'bonsai-flutter-ios' ;;
  *" switch create bonsai-flutter-ios "*) exit 0 ;;
  *" install --switch=bonsai-flutter-ios --yes bonsai_flutter_ios_sdk.0.1.0~dev.2 "*)
    exit "${INSTALL_EXIT:-0}" ;;
  *) exit 64 ;;
esac
|}
    );
  with_toolchain_fixture fixture (fun () ->
    Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root |> get_ok);
  let commands = read_file fixture.toolchain_log |> non_empty_lines in
  Alcotest.(check int) "one check, create, and install" 3 (List.length commands);
  let create = List.nth commands 1 in
  let repository_name =
    "bonsai-flutter-ios-" ^ String.sub (repository_digest repository) 0 12
  in
  Alcotest.(check bool)
    "fixed switch creation"
    true
    (contains create "switch\tcreate\tbonsai-flutter-ios\tocaml-base-compiler.5.1.1");
  Alcotest.(check bool)
    "snapshot-qualified local repository"
    true
    (contains create (repository_name ^ "=file://" ^ repository));
  Alcotest.(check bool)
    "locked default repository commit"
    true
    (contains
       create
       "bonsai-flutter-default=git+https://github.com/RCmerci/opam-repository.git#c98b21e24c088665ccae4c3b53eadadd3b755b15");
  Alcotest.(check bool)
    "locked cross repository commit"
    true
    (contains
       create
       "bonsai-flutter-ios-cross=git+https://github.com/ocaml-cross/opam-cross-ios.git#8380b52b0154752c26c6e221c04fbced3320aa48");
  Alcotest.(check bool)
    "exact SDK meta-package install"
    true
    (contains (List.nth commands 2) "bonsai_flutter_ios_sdk.0.1.0~dev.2");
  Alcotest.(check bool)
    "non-interactive depext handling"
    true
    (contains (List.nth commands 2) "--assume-depexts")
;;

let test_toolchain_install_rejects_existing_switch_and_tampered_repository () =
  let fixture = create_toolchain_fixture () in
  let framework_root = Filename.concat fixture.toolchain_root "framework" in
  let repository = Filename.concat framework_root "tool/ios/opam-repository/0.1.0" in
  write_repository_fixture repository;
  write_file fixture.toolchain_log "";
  write_executable
    (Filename.concat fixture.toolchain_bin "opam")
    (command_logger "opam"
     ^ {|if test "$1" = switch && test "$2" = list; then
  test -z "${SWITCH_EXISTS:-}" || printf '%s\n' 'bonsai-flutter-ios'
  exit 0
fi
exit 64
|}
    );
  with_toolchain_fixture
    ~environment:[ "SWITCH_EXISTS", "true" ]
    fixture
    (fun () ->
       Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root
       |> check_error_contains "already exists");
  Alcotest.(check int)
    "existing switch stops after read-only check"
    1
    (read_file fixture.toolchain_log |> non_empty_lines |> List.length);
  write_file fixture.toolchain_log "";
  write_file (Filename.concat repository "repo") "opam-version: \"2.1\"\n";
  with_toolchain_fixture fixture (fun () ->
    Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root
    |> check_error_contains "repository snapshot digest");
  Alcotest.(check string)
    "tampered repository stops before opam"
    ""
    (read_file fixture.toolchain_log);
  write_repository_fixture repository;
  write_file
    (Filename.concat repository "package-universe.lock")
    "tampered package lock\n";
  with_toolchain_fixture fixture (fun () ->
    Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root
    |> check_error_contains "package universe digest");
  Alcotest.(check string)
    "tampered package universe stops before opam"
    ""
    (read_file fixture.toolchain_log);
  write_repository_fixture repository;
  write_file (Filename.concat repository "source-archives.lock") "tampered archives\n";
  with_toolchain_fixture fixture (fun () ->
    Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root
    |> check_error_contains "source archive digest");
  Alcotest.(check string)
    "tampered source archives stop before opam"
    ""
    (read_file fixture.toolchain_log);
  write_repository_fixture repository;
  let source_lock =
    Filename.concat framework_root "vendor/opam-ios/runtime-closure.lock"
  in
  write_file source_lock "tampered source lock\n";
  with_toolchain_fixture fixture (fun () ->
    Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root
    |> check_error_contains "source lock digest");
  Alcotest.(check string)
    "tampered source lock stops before opam"
    ""
    (read_file fixture.toolchain_log)
;;

let test_feature_validation () =
  let core = [ Config.Feature.Core ] in
  let network = [ Config.Feature.Core; Config.Feature.Network ] in
  let sqlite = [ Config.Feature.Core; Config.Feature.Sqlite ] in
  Feature.validate_packages
    ~target:Plan.Iphoneos
    ~features:network
    [ "tls"; "httpun-eio" ]
  |> get_ok
  |> ignore;
  Feature.validate_packages ~target:Plan.Iphoneos ~features:core [ "tls" ]
  |> check_error_contains "requires the network feature";
  Feature.validate_packages ~target:Plan.Iphoneos ~features:network [ "openssl" ]
  |> check_error_contains "prohibited TLS backend";
  Feature.validate_packages
    ~target:Plan.Iphoneos
    ~features:core
    [ "mirage-crypto-rng.unix" ]
  |> check_error_contains "requires the network feature for entropy";
  Feature.validate_packages ~target:Plan.Iphoneos ~features:core [ "eio_posix" ]
  |> get_ok
  |> ignore;
  Feature.validate_packages
    ~target:Plan.Iphoneos
    ~features:core
    [ "datascript-ocaml-native.sqlite" ]
  |> get_ok
  |> ignore;
  Feature.validate_packages ~target:Plan.Iphoneos ~features:sqlite [ "sqlite3" ]
  |> get_ok
  |> ignore;
  Feature.validate_packages ~target:Plan.Iphoneos ~features:core [ "sqlite3" ]
  |> check_error_contains "requires the sqlite feature";
  Feature.validate_packages
    ~target:Plan.Iphoneos
    ~features:core
    [ "astring"; "bigstringaf"; "cstruct"; "ptime" ]
  |> get_ok
  |> ignore
;;

let test_cache_keys () =
  let config = Config.parse_string valid_config |> get_ok in
  let key = Cache.application_key ~config ~target:Plan.Iphoneos ~profile:Plan.Release in
  let repeated =
    Cache.application_key ~config ~target:Plan.Iphoneos ~profile:Plan.Release
  in
  let macos = Cache.application_key ~config ~target:Plan.Macos ~profile:Plan.Release in
  Alcotest.(check string) "deterministic" key repeated;
  Alcotest.(check bool) "target-sensitive" false (String.equal key macos);
  Alcotest.(check int) "SHA-256 hex length" 64 (String.length key)
;;

let test_generated_host () =
  let config = Config.parse_string valid_config |> get_ok in
  let files = Host.render ~config in
  let pubspec = List.assoc "flutter/pubspec.yaml" files in
  let main = List.assoc "flutter/lib/main.dart" files in
  Alcotest.(check bool)
    "relative native artifacts"
    true
    (contains pubspec "native_artifact_root: ../_build/bonsai-flutter/artifacts/"
     && (not (contains pubspec "native-artifacts"))
     && not
          (contains
             pubspec
             "native_artifact_root: ../_build/bonsai-flutter/artifacts/journal/"));
  Alcotest.(check bool)
    "renderer dependency"
    true
    (contains pubspec "path: ../.bonsai-flutter/flutter-packages/bonsai_flutter");
  Alcotest.(check bool)
    "integration test dependency"
    true
    (contains pubspec "  integration_test:\n    sdk: flutter\n");
  Alcotest.(check bool)
    "macOS deployment target user define"
    true
    (contains pubspec "macos_deployment_target: '26.0'");
  let macos_config_path = "flutter/macos/Runner/Configs/BonsaiFlutter.xcconfig" in
  Alcotest.(check (option string))
    "managed macOS configuration is rendered"
    (Some "MACOSX_DEPLOYMENT_TARGET = 26.0\nARCHS = arm64\n")
    (List.assoc_opt macos_config_path files);
  let native_direct_dependency = Str.regexp "^  bonsai_flutter_native:" in
  Alcotest.(check bool)
    "native package remains transitive"
    false
    (try
       ignore (Str.search_forward native_direct_dependency pubspec 0);
       true
     with
     | Not_found -> false);
  Alcotest.(check bool)
    "no Dart networking"
    false
    (try
       ignore (Str.search_forward (Str.regexp_string "dart:io") main 0);
       true
     with
     | Not_found -> false)
;;

let test_generated_managed_adapter_host () =
  let config = Config.parse_string managed_adapter_config |> get_ok in
  let files = Host.render ~config in
  let main = List.assoc "flutter/lib/main.dart" files in
  let widget_test = List.assoc "flutter/test/widget_test.dart" files in
  [ "import 'application_host_adapter.dart' as application;"
  ; "application.createBonsaiFlutterHostAdapter()"
  ; "await widget.adapter.createApplicationPayload()"
  ; "widget.adapter.createApplicationPlatform()"
  ; "RuntimeBootstrapConfig("
  ; "entrypoint: 'journal_runtime'"
  ; "launchPolicy: RuntimeLaunchPolicy.replaceExisting"
  ; "applicationPayload: applicationPayload"
  ; ").encode()"
  ; "BonsaiFlutterRoot("
  ; "config: prepared.runtimeConfig"
  ; "applicationPlatform: prepared.applicationPlatform"
  ; "widget.adapter.buildHost("
  ]
  |> List.iter (fun expected ->
    Alcotest.(check bool) expected true (contains main expected));
  Alcotest.(check bool)
    "raw entrypoint is absent"
    false
    (contains main "utf8.encode('journal')");
  Alcotest.(check bool)
    "generated Flutter construction test imports adapter"
    true
    (contains widget_test "application_host_adapter.dart");
  Alcotest.(check bool)
    "generated Flutter construction test declares its relative import policy"
    true
    (contains widget_test "// ignore_for_file: avoid_relative_lib_imports");
  Alcotest.(check bool)
    "generated Flutter construction test constructs adapter host"
    true
    (contains
       widget_test
       "BonsaiFlutterHost(adapter: application.createBonsaiFlutterHostAdapter())")
;;

let test_mixed_ownership_pubspec_sync () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "owned-pubspec" in
  let config = Config.parse_string valid_config |> get_ok in
  let pubspec_path = Filename.concat root "flutter/pubspec.yaml" in
  let original = consumer_pubspec () in
  write_file pubspec_path original;
  Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok |> ignore;
  let synchronized = read_file pubspec_path in
  [ "# consumer comment"
  ; "  path_provider: ^2.1.5"
  ; "  unrelated_hook: keep-me"
  ; "  test: ^1.31.0"
  ; "path: ../.bonsai-flutter/flutter-packages/bonsai_flutter"
  ; "native_artifact_root: ../_build/bonsai-flutter/artifacts/"
  ]
  |> List.iter (fun expected ->
    Alcotest.(check bool) expected true (contains synchronized expected));
  Alcotest.(check bool)
    "obsolete package path removed"
    false
    (contains synchronized "old/path");
  Alcotest.(check bool)
    "obsolete artifact root removed"
    false
    (contains synchronized "old/artifacts")
;;

let test_pubspec_marker_validation () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "invalid-markers" in
  let config = Config.parse_string valid_config |> get_ok in
  let pubspec_path = Filename.concat root "flutter/pubspec.yaml" in
  [ ( "missing package marker"
    , replace_once
        (consumer_pubspec ())
        ~pattern:"  # bonsai-flutter:begin packages\n"
        ~replacement:""
    , "packages marker" )
  ; ( "duplicate package marker"
    , replace_once
        (consumer_pubspec ())
        ~pattern:"  # bonsai-flutter:begin packages\n"
        ~replacement:
          "  # bonsai-flutter:begin packages\n  # bonsai-flutter:begin packages\n"
    , "packages marker" )
  ; ( "reversed native marker"
    , consumer_pubspec ()
      |> replace_once
           ~pattern:"# bonsai-flutter:begin native-hook"
           ~replacement:"# bonsai-flutter:temporary native-hook"
      |> replace_once
           ~pattern:"# bonsai-flutter:end native-hook"
           ~replacement:"# bonsai-flutter:begin native-hook"
      |> replace_once
           ~pattern:"# bonsai-flutter:temporary native-hook"
           ~replacement:"# bonsai-flutter:end native-hook"
    , "native-hook marker" )
  ]
  |> List.iter (fun (name, contents, expected) ->
    write_file pubspec_path contents;
    match Host.sync ~project_root:root ~config ~mode:Host.Write with
    | Error message -> Alcotest.(check bool) name true (contains message expected)
    | Ok _ -> Alcotest.failf "%s: expected marker validation failure" name)
;;

let test_pubspec_sync_preserves_crlf () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "crlf-pubspec" in
  let config = Config.parse_string valid_config |> get_ok in
  let pubspec_path = Filename.concat root "flutter/pubspec.yaml" in
  write_file pubspec_path (consumer_pubspec ~line_ending:"\r\n" ());
  Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok |> ignore;
  let synchronized = read_file pubspec_path in
  let without_crlf = Str.global_replace (Str.regexp_string "\r\n") "" synchronized in
  Alcotest.(check bool) "CRLF is retained" false (contains without_crlf "\n")
;;

let test_custom_host_sync_preserves_consumer_source () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "custom-host" in
  let config = Config.parse_string custom_host_config |> get_ok in
  let main_path = Filename.concat root "flutter/lib/main.dart" in
  let test_path = Filename.concat root "flutter/test/custom_host_test.dart" in
  let main = "// consumer-owned main\nvoid main() {}\n" in
  let test = "// consumer-owned test\n" in
  write_file main_path main;
  write_file test_path test;
  write_file (Filename.concat root "flutter/pubspec.yaml") (consumer_pubspec ());
  Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok |> ignore;
  Alcotest.(check string) "custom main" main (read_file main_path);
  Alcotest.(check string) "custom tests" test (read_file test_path);
  Sys.remove main_path;
  Host.sync ~project_root:root ~config ~mode:Host.Write
  |> check_error_contains "Custom host entrypoint is missing"
;;

let test_managed_host_rejects_edited_generated_source () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "managed-edit" in
  let config = Config.parse_string valid_config |> get_ok in
  Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok |> ignore;
  let main_path = Filename.concat root "flutter/lib/main.dart" in
  write_file main_path "// consumer edit\n";
  Host.sync ~project_root:root ~config ~mode:Host.Write
  |> check_error_contains "managed generated file was edited"
;;

let test_ios_privacy_manifest () =
  let config = Config.parse_string valid_config |> get_ok in
  let files = Host.render ~config in
  let privacy = List.assoc "flutter/ios/Runner/PrivacyInfo.xcprivacy" files in
  Alcotest.(check bool)
    "file timestamp reason"
    true
    (contains privacy "NSPrivacyAccessedAPICategoryFileTimestamp");
  Alcotest.(check bool)
    "boot time reason"
    true
    (contains privacy "NSPrivacyAccessedAPICategorySystemBootTime");
  let project =
    "/* Begin PBXBuildFile section */\n\
     /* Begin PBXFileReference section */\n\
     97C147021CF9000F007C117D /* Info.plist */,\n\
     97C146FC1CF9000F007C117D /* Main.storyboard in Resources */,\n"
  in
  let patched = Host.patch_ios_project_contents project |> get_ok in
  Alcotest.(check bool)
    "privacy manifest resource"
    true
    (contains patched "PrivacyInfo.xcprivacy in Resources")
;;

let test_scaffold_preserves_user_source () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "preserve" in
  let app_dir = Filename.concat root "app" in
  Unix.mkdir app_dir 0o755;
  let app_ml = Filename.concat app_dir "application.ml" in
  let channel = open_out app_ml in
  output_string channel "let user_owned = true\n";
  close_out channel;
  let config = Config.parse_string valid_config |> get_ok in
  Scaffold.initialize ~project_root:root ~config |> get_ok;
  let channel = open_in app_ml in
  let preserved = input_line channel in
  close_in channel;
  Alcotest.(check string) "existing app source" "let user_owned = true" preserved;
  Alcotest.(check bool)
    "missing native embed created"
    true
    (Sys.file_exists (Filename.concat app_dir "native_embed.ml"));
  let adapter_path = Filename.concat root "flutter/lib/application_host_adapter.dart" in
  Alcotest.(check bool)
    "missing application-owned adapter created"
    true
    (Sys.file_exists adapter_path);
  Alcotest.(check bool)
    "starter adapter exposes an optional application platform"
    true
    (contains (read_file adapter_path) "createApplicationPlatform() => null");
  let application_owned = "// application-owned after init\n" in
  write_file adapter_path application_owned;
  Scaffold.initialize ~project_root:root ~config |> get_ok;
  Alcotest.(check string)
    "repeated init preserves application-owned adapter"
    application_owned
    (read_file adapter_path)
;;

let test_scaffold_adopts_existing_layout_without_default_app () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "adopt-layout" in
  write_file (Filename.concat root "ocaml/native_embed.ml") "let () = ()\n";
  write_file
    (Filename.concat root "ocaml/dune")
    "(executable (name native_embed) (modules native_embed) (modes (native object)))\n";
  write_file (Filename.concat root "flutter/lib/main.dart") "void main() {}\n";
  write_file (Filename.concat root "flutter/pubspec.yaml") (consumer_pubspec ());
  let config = Config.parse_string custom_host_config |> get_ok in
  Scaffold.adopt_workspace ~project_root:root ~config_text:custom_host_config ~config
  |> get_ok;
  Alcotest.(check bool)
    "default app directory is absent"
    false
    (Sys.file_exists (Filename.concat root "app"));
  Alcotest.(check bool)
    "consumer OCaml entrypoint is preserved"
    true
    (Sys.file_exists (Filename.concat root "ocaml/native_embed.ml"))
;;

let test_scaffold_adoption_rejects_conflicting_config () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "adopt-conflict" in
  write_file (Filename.concat root "bonsai-flutter.sexp") valid_config;
  write_file (Filename.concat root "ocaml/dune") "(executable (name native_embed))\n";
  let config = Config.parse_string custom_host_config |> get_ok in
  Scaffold.adopt_workspace ~project_root:root ~config_text:custom_host_config ~config
  |> check_error_contains "bonsai-flutter.sexp conflicts"
;;

let test_scaffold_generates_and_preserves_application_lock () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "application-lock" in
  let config = Config.parse_string valid_config |> get_ok in
  Scaffold.initialize_workspace ~project_root:root ~config_text:valid_config ~config
  |> get_ok;
  let lock = Filename.concat root "journal.opam.locked" in
  Alcotest.(check bool) "application lock exists" true (Sys.file_exists lock);
  let contents = read_file lock in
  [ "\"base\" {= \"v0.17.3\"}"
  ; "\"bonsai\" {= \"v0.17.0\"}"
  ; "\"bonsai_flutter\" {= \"0.1.0~dev\"}"
  ; "\"incr_dom\" {= \"v0.17.0\"}"
  ; "\"ocaml-ios64\" {= \"5.1.1\"}"
  ; "\"virtual_dom\" {= \"v0.17.0\"}"
  ]
  |> List.iter (fun dependency ->
    Alcotest.(check bool) dependency true (contains contents dependency));
  let application_owned = "application-owned lock\n" in
  write_file lock application_owned;
  Scaffold.initialize_workspace ~project_root:root ~config_text:valid_config ~config
  |> get_ok;
  Alcotest.(check string) "existing application lock" application_owned (read_file lock)
;;

let test_scaffold_generates_dune_native_aliases () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "dune-aliases" in
  let config = Config.parse_string valid_config |> get_ok in
  Scaffold.initialize ~project_root:root ~config |> get_ok;
  let dune_path = Filename.concat root "app/dune" in
  let dune = read_file dune_path in
  Alcotest.(check bool) "application Dune file exists" true (Sys.file_exists dune_path);
  [ "(name native_embed)"
  ; "(name bonsai-flutter-macos)"
  ; "(enabled_if (= %{context_name} default))"
  ; "(name bonsai-flutter-ios)"
  ; "(enabled_if (= %{context_name} default.ios))"
  ; "(deps native_embed.exe.o)"
  ]
  |> List.iter (fun expected ->
    Alcotest.(check bool) expected true (contains dune expected));
  Alcotest.(check bool)
    "generated rules are workspace-relative"
    false
    (contains dune root);
  Alcotest.(check bool)
    "obsolete nested Dune integration is absent"
    false
    (Sys.file_exists (Filename.concat root "app/bonsai_flutter/dune"));
  write_file
    dune_path
    {|(executable
 (name user_owned)
 (modules user_owned))
|};
  Scaffold.initialize ~project_root:root ~config |> get_ok;
  let repaired = read_file dune_path in
  Alcotest.(check bool)
    "repeated initialization preserves user stanzas"
    true
    (contains repaired "(name user_owned)");
  Alcotest.(check bool)
    "repeated initialization repairs generated aliases"
    true
    (contains repaired "(name bonsai-flutter-ios)")
;;

let test_scaffold_quotes_dune_native_target () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "dune-quoted-target" in
  let config =
    valid_config
    |> replace_once
         ~pattern:"app/native_embed.exe.o"
         ~replacement:"\"app/native embed.exe.o\""
    |> Config.parse_string
    |> get_ok
  in
  Scaffold.initialize ~project_root:root ~config |> get_ok;
  Alcotest.(check bool)
    "Dune dependency is quoted"
    true
    (contains
       (read_file (Filename.concat root "app/dune"))
       "(deps \"native embed.exe.o\")")
;;

let test_macos_dune_alias_build_is_incremental () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "dune-incremental" in
  let app_root = Filename.concat root "app" in
  let config = Config.parse_string valid_config |> get_ok in
  write_file
    (Filename.concat root "dune-project")
    "(lang dune 3.17)\n(name dune_incremental_fixture)\n";
  write_file
    (Filename.concat app_root "dune")
    {|(executable
 (name native_embed)
 (modules native_embed)
 (enabled_if
  (= %{env:BONSAI_FLUTTER_EMBED_OCAML=disabled} enabled))
 (modes
  (native object)))
|};
  let source = Filename.concat app_root "native_embed.ml" in
  write_file source "let () = print_endline \"first\"\n";
  Scaffold.initialize ~project_root:root ~config |> get_ok;
  let build =
    Plan.native_build
      ~project_root:root
      ~config
      ~target:Plan.Macos
      ~profile:Plan.Debug
      ~toolchain_fingerprint:"incremental-host"
      ~apple_sdk_root:"/Xcode/MacOSX.sdk"
      ~apple_sdk_version:None
    |> get_ok
  in
  Scaffold.ensure_directory (Filename.dirname build.build_directory);
  Process_runner.run build.command |> get_ok;
  let object_path = build.source_object in
  Alcotest.(check bool)
    "alias builds the complete object"
    true
    (Sys.file_exists object_path);
  let first_mtime = (Unix.stat object_path).st_mtime in
  let first_digest = Digest.file object_path in
  Unix.sleep 1;
  Process_runner.run build.command |> get_ok;
  let second_mtime = (Unix.stat object_path).st_mtime in
  Alcotest.(check (float 0.))
    "unchanged source leaves object untouched"
    first_mtime
    second_mtime;
  Unix.sleep 1;
  write_file source "let () = print_endline \"second\"\n";
  Process_runner.run build.command |> get_ok;
  Alcotest.(check bool)
    "changed OCaml source rebuilds the object"
    true
    (not (String.equal first_digest (Digest.file object_path)))
;;

let test_project_root_discovery () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "root" in
  let config_path = Filename.concat root "bonsai-flutter.sexp" in
  let channel = open_out config_path in
  output_string channel valid_config;
  close_out channel;
  let nested = Filename.concat root "one/two" in
  Scaffold.ensure_directory nested;
  Alcotest.(check (result string string))
    "walks to configuration"
    (Ok (Unix.realpath root))
    (Project.find_root nested)
;;

let test_project_lock_serializes_processes () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "lock" in
  let lock_path = Filename.concat root "_build/bonsai-flutter/locks/test.lock" in
  let read_end, write_end = Unix.pipe () in
  let child = ref None in
  Lock.with_lock lock_path (fun () ->
    match Unix.fork () with
    | 0 ->
      Unix.close read_end;
      let status =
        match
          Lock.with_lock lock_path (fun () ->
            ignore (Unix.write_substring write_end "1" 0 1);
            Ok ())
        with
        | Ok () -> 0
        | Error _ -> 1
      in
      Unix.close write_end;
      Unix._exit status
    | pid ->
      child := Some pid;
      Unix.close write_end;
      let ready, _, _ = Unix.select [ read_end ] [] [] 0.2 in
      Alcotest.(check int) "child waits while locked" 0 (List.length ready);
      Ok ())
  |> get_ok;
  let ready, _, _ = Unix.select [ read_end ] [] [] 2.0 in
  Alcotest.(check int) "child acquires after release" 1 (List.length ready);
  let byte = Bytes.create 1 in
  Alcotest.(check int) "child notification" 1 (Unix.read read_end byte 0 1);
  Unix.close read_end;
  (match !child with
   | None -> Alcotest.fail "child process was not created"
   | Some pid ->
     let _, status = Unix.waitpid [] pid in
     Alcotest.(check int)
       "child exit"
       0
       (match status with
        | Unix.WEXITED code -> code
        | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 1));
  Alcotest.(check bool) "project-local lock file" true (Sys.file_exists lock_path)
;;

let test_clean_removes_only_selected_platform () =
  let project_root = Filename.temp_dir "bonsai-flutter-tool" "clean-platform" in
  let build_root = Filename.concat project_root "_build/bonsai-flutter" in
  let files =
    [ "dune/macos/host/debug/object", "macos"
    ; "artifacts/macos/arm64/debug/native_embed.exe.o", "macos"
    ; "state/macos/debug/build-manifest.sexp", "macos"
    ; "logs/macos/debug.log", "macos"
    ; "locks/macos/debug.lock", "macos"
    ; "dune/iphoneos/sdk/release/object", "iphoneos"
    ; "artifacts/ios/iphoneos/arm64/release/native_embed.exe.o", "iphoneos"
    ; "state/iphoneos/release/build-manifest.sexp", "iphoneos"
    ; "logs/iphoneos/release.log", "iphoneos"
    ; "locks/iphoneos/release.lock", "iphoneos"
    ; "unrelated/keep", "unrelated"
    ]
  in
  List.iter
    (fun (path, contents) -> write_file (Filename.concat build_root path) contents)
    files;
  Clean.run ~project_root Clean.Macos |> get_ok;
  files
  |> List.iter (fun (path, platform) ->
    Alcotest.(check bool)
      path
      (platform <> "macos")
      (Sys.file_exists (Filename.concat build_root path)));
  Clean.run ~project_root Clean.Macos |> get_ok
;;

let test_clean_all_does_not_follow_symlinks () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "clean-symlink" in
  let project_root = Filename.concat root "project" in
  let build_root = Filename.concat project_root "_build/bonsai-flutter" in
  let external_root = Filename.concat root "global-switch" in
  let external_sentinel = Filename.concat external_root "manifest.sexp" in
  write_file external_sentinel "immutable global state";
  write_file (Filename.concat build_root "state/macos/debug/build-manifest.sexp") "state";
  Unix.symlink external_root (Filename.concat build_root "linked-global-state");
  Clean.run ~project_root Clean.All |> get_ok;
  Alcotest.(check bool) "project build root removed" false (Sys.file_exists build_root);
  Alcotest.(check string)
    "symlink target remains untouched"
    "immutable global state"
    (read_file external_sentinel);
  Clean.run ~project_root Clean.All |> get_ok
;;

let test_host_sync_check () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "sync" in
  let config = Config.parse_string valid_config |> get_ok in
  Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok |> ignore;
  let main_path = Filename.concat root "flutter/lib/main.dart" in
  let channel = open_out main_path in
  output_string channel "// drift\n";
  close_out channel;
  Host.sync ~project_root:root ~config ~mode:Host.Check
  |> check_error_contains "Generated host is out of date";
  let channel = open_in main_path in
  let still_drifted = input_line channel in
  close_in channel;
  Alcotest.(check string) "check does not modify" "// drift" still_drifted;
  Host.sync ~project_root:root ~config ~mode:Host.Write
  |> check_error_contains "managed generated file was edited";
  Sys.remove main_path;
  let repaired = Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok in
  Alcotest.(check (list string)) "repairs only drift" [ "flutter/lib/main.dart" ] repaired
;;

let test_host_sync_preserves_consumer_dependency_changes () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "sync-integration-test" in
  let config = Config.parse_string valid_config |> get_ok in
  Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok |> ignore;
  let pubspec_path = Filename.concat root "flutter/pubspec.yaml" in
  let generated = read_file pubspec_path in
  let dependency = "  integration_test:\n    sdk: flutter\n" in
  let missing = replace_once generated ~pattern:dependency ~replacement:"" in
  write_file pubspec_path missing;
  Alcotest.(check (list string))
    "consumer dependency is outside managed regions"
    []
    (Host.sync ~project_root:root ~config ~mode:Host.Check |> get_ok);
  let repaired = Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok in
  Alcotest.(check (list string)) "consumer dependency change is untouched" [] repaired;
  Alcotest.(check string) "preserves consumer pubspec" missing (read_file pubspec_path)
;;

let test_native_sync_only_manages_dune_aliases () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "native-sync" in
  let project_root = Filename.concat root "project" in
  let framework_root = Filename.concat root "framework" in
  let config = Config.parse_string valid_config |> get_ok in
  let pubspec = Filename.concat project_root "flutter/pubspec.yaml" in
  let app_dune = Filename.concat project_root "app/dune" in
  let obsolete_dune = Filename.concat project_root "app/bonsai_flutter/dune" in
  let application_owned_drift = "# existing host state\n" in
  write_file pubspec application_owned_drift;
  write_file
    app_dune
    {|(library
 (name application)
 (libraries base))
|};
  write_file obsolete_dune "; obsolete generated alias file\n";
  [ "bonsai_flutter"; "bonsai_flutter_native" ]
  |> List.iter (fun package ->
    write_file
      (Filename.concat framework_root ("flutter/packages/" ^ package ^ "/pubspec.yaml"))
      ("name: " ^ package ^ "\n"));
  Build_system.synchronize ~framework_root ~project_root ~config |> get_ok;
  Alcotest.(check string)
    "native sync preserves Flutter host"
    application_owned_drift
    (read_file pubspec);
  Alcotest.(check bool)
    "native sync creates macOS alias in app/dune"
    true
    (contains (read_file app_dune) "(name bonsai-flutter-macos)");
  Alcotest.(check bool)
    "native sync creates context-gated iOS alias in app/dune"
    true
    (contains (read_file app_dune) "(enabled_if (= %{context_name} default.ios))");
  Alcotest.(check bool)
    "native sync preserves application Dune stanzas"
    true
    (contains (read_file app_dune) "(name application)");
  Alcotest.(check bool)
    "native sync removes obsolete nested alias file"
    false
    (Sys.file_exists obsolete_dune);
  Alcotest.(check bool)
    "native sync does not copy Flutter packages"
    false
    (Sys.file_exists
       (Filename.concat
          project_root
          ".bonsai-flutter/flutter-packages/bonsai_flutter/pubspec.yaml"))
;;

let test_native_build_rejects_invalid_alias_contract_before_external_tools () =
  let cases =
    [ ( "missing aliases"
      , {|(executable
 (name native_embed)
 (modules native_embed)
 (modes (native object)))
|}
      )
    ; ( "wrong iOS context"
      , {|(alias
 (name bonsai-flutter-macos)
 (enabled_if (= %{context_name} default))
 (deps native_embed.exe.o))

(alias
 (name bonsai-flutter-ios)
 (enabled_if (= %{context_name} default))
 (deps native_embed.exe.o))
|}
      )
    ; ( "wrong dependency"
      , {|(alias
 (name bonsai-flutter-macos)
 (enabled_if (= %{context_name} default))
 (deps another.exe.o))

(alias
 (name bonsai-flutter-ios)
 (enabled_if (= %{context_name} default.ios))
 (deps another.exe.o))
|}
      )
    ]
  in
  cases
  |> List.iter (fun (name, dune) ->
    let root = Filename.temp_dir "bonsai-flutter-tool" "invalid-alias" |> Unix.realpath in
    let bin = Filename.concat root "bin" in
    let command_log = Filename.concat root "commands.log" in
    let config = Config.parse_string valid_config |> get_ok in
    let dune_path = Filename.concat root "app/dune" in
    write_file dune_path dune;
    write_file command_log "";
    write_executable
      (Filename.concat bin "xcrun")
      (command_logger "xcrun"
       ^ {|exit 64
|}
      );
    with_environment
      [ "PATH", bin; "COMMAND_LOG", command_log ]
      (fun () ->
         Build_system.build_native
           ~framework_root:(Filename.concat root "framework")
           ~project_root:root
           ~config
           ~target:Plan.Macos
           ~profile:Plan.Debug
         |> check_error_contains "Invalid application Dune alias contract");
    Alcotest.(check string) (name ^ " preserves app/dune") dune (read_file dune_path);
    Alcotest.(check string)
      (name ^ " stops before external tools")
      ""
      (read_file command_log))
;;

type native_build_fixture =
  { native_project_root : string
  ; native_framework_root : string
  ; native_switch_prefix : string
  ; native_bin : string
  ; native_command_log : string
  ; native_config : Config.t
  ; native_alias_path : string
  }

let rec file_snapshot root path =
  let absolute = Filename.concat root path in
  if Sys.is_directory absolute
  then
    Sys.readdir absolute
    |> Array.to_list
    |> List.sort String.compare
    |> List.concat_map (fun name ->
      file_snapshot root (if path = "" then name else Filename.concat path name))
  else [ path, Digest.file absolute ]
;;

let create_native_build_fixture () =
  let native_root =
    Filename.temp_dir "bonsai-flutter-tool" "native-build" |> Unix.realpath
  in
  let native_project_root = Filename.concat native_root "project" in
  let native_framework_root = Filename.concat native_root "installed-tool-assets" in
  let native_switch_prefix = Filename.concat native_root "global-switch-prefix" in
  let native_bin = Filename.concat native_root "bin" in
  let native_command_log =
    Filename.concat native_project_root "_build/bonsai-flutter/logs/test-commands.log"
  in
  Scaffold.ensure_directory (Filename.dirname native_command_log);
  let native_config = Config.parse_string valid_config |> get_ok in
  let native_alias_path = Filename.concat native_project_root "app/dune" in
  write_file
    native_alias_path
    {|(executable
 (name native_embed)
 (modules native_embed)
 (modes (native object)))

(alias
 (name bonsai-flutter-macos)
 (enabled_if (= %{context_name} default))
 (deps native_embed.exe.o))

(alias
 (name bonsai-flutter-ios)
 (enabled_if (= %{context_name} default.ios))
 (deps native_embed.exe.o))
|};
  write_file
    (Filename.concat native_project_root "journal.opam.locked")
    {|opam-version: "2.0"
name: "journal"
version: "0.1.0"
depends: [
  "base" {= "v0.17.0"}
  "bonsai_flutter" {= "0.1.0~dev"}
]
|};
  [ "dune"; "ocamlc"; "ocamlfind" ]
  |> List.iter (fun program ->
    write_executable
      (Filename.concat native_switch_prefix ("bin/" ^ program))
      "#!/bin/sh\nexit 0\n");
  write_file
    (Filename.concat native_switch_prefix "share/bonsai_flutter_ios_sdk/manifest.sexp")
    valid_sdk_manifest;
  write_executable
    (Filename.concat native_framework_root "tool/ios/verify_complete_object.sh")
    (command_logger "verify_complete_object"
     ^ {|exit "${VERIFY_EXIT:-0}"
|}
    );
  [ "bonsai_flutter"; "bonsai_flutter_native" ]
  |> List.iter (fun package ->
    write_file
      (Filename.concat
         native_framework_root
         ("flutter/packages/" ^ package ^ "/pubspec.yaml"))
      ("name: " ^ package ^ "\nversion: 0.1.0\n"));
  write_executable
    (Filename.concat native_bin "xcrun")
    (command_logger "xcrun"
     ^ {|case "$*" in
  *"macosx --show-sdk-path"*) printf '%s\n' '/Xcode/MacOSX.sdk' ;;
  *"iphoneos --show-sdk-path"*) printf '%s\n' '/Xcode/iPhoneOS.sdk' ;;
  *"iphoneos --show-sdk-version"*) printf '%s\n' '26.0' ;;
  *) exit 64 ;;
esac
|}
    );
  write_executable
    (Filename.concat native_bin "opam")
    (command_logger "opam"
     ^ Printf.sprintf
         {|case " $* " in
  *" switch show --switch=bonsai-flutter-ios "*)
    printf '%%s\n' 'bonsai-flutter-ios' ;;
  *" var --switch=bonsai-flutter-ios prefix "*)
    printf '%%s\n' '%s' ;;
  *" exec --switch=bonsai-flutter-ios -- dune --version "*|*" exec -- dune --version "*)
    printf '%%s\n' '3.18.2' ;;
  *" exec --switch=bonsai-flutter-ios -- dune describe external-lib-deps "*)
    build_directory=''
    for argument in "$@"; do
      case "$argument" in
        --build-dir=*) build_directory="${argument#--build-dir=}" ;;
      esac
    done
    test -n "$build_directory"
    test -d "$(dirname "$build_directory")"
    printf '%%s\n' '(11:default.ios((11:executables((5:names(12:native_embed))(10:extensions(6:.exe.o))(7:package())(10:source_dir3:app)(13:external_deps((4:base8:required)(17:bonsai_flutter.ui8:required)))(13:internal_deps())))))' ;;
  *" exec --switch=bonsai-flutter-ios -- ocamlc -version "*|*" exec -- ocamlc -version "*)
    printf '%%s\n' '5.1.1' ;;
  *" exec --switch=bonsai-flutter-ios -- ocamlfind -toolchain ios printconf path "*)
    printf '%%s\n' '%s/lib/ios' ;;
  *" exec -- ocamlfind query -format %%v bonsai_flutter "*)
    printf '%%s\n' '0.1.0~dev' ;;
  *" dune build "*)
    build_directory=''
    context='default'
    for argument in "$@"; do
      case "$argument" in
        --build-dir=*) build_directory="${argument#--build-dir=}" ;;
        @app/bonsai-flutter-ios) context='default.ios' ;;
      esac
    done
    test -n "$build_directory"
    object="$build_directory/$context/app/native_embed.exe.o"
    mkdir -p "$(dirname "$object")"
    if test ! -f "$object" || test "${REWRITE_OBJECT:-false}" = true; then
      printf '%%s' "${OBJECT_CONTENT:-complete-object}" > "$object"
    fi ;;
  *) exit 64 ;;
esac
|}
         native_switch_prefix
         native_switch_prefix);
  let gmp_directory = Filename.concat native_root "static-gmp" in
  write_file (Filename.concat gmp_directory "libgmp.a") "static-gmp";
  write_executable
    (Filename.concat native_bin "pkg-config")
    (command_logger "pkg-config" ^ Printf.sprintf "printf '%%s\\n' '%s'\n" gmp_directory);
  write_executable
    (Filename.concat native_bin "clang")
    (command_logger "clang"
     ^ {|source=''
output=''
previous=''
for argument in "$@"; do
  if test "$previous" = -o; then output=$argument; fi
  case "$argument" in
    *.exe.o) if test -z "$source"; then source=$argument; fi ;;
  esac
  previous=$argument
done
test -n "$source"
test -n "$output"
cp "$source" "$output"
|}
    );
  write_executable (Filename.concat native_bin "nm") (command_logger "nm" ^ "exit 0\n");
  { native_project_root
  ; native_framework_root
  ; native_switch_prefix
  ; native_bin
  ; native_command_log
  ; native_config
  ; native_alias_path
  }
;;

let with_native_build_fixture ?(environment = []) fixture f =
  with_environment
    ([ "PATH", fixture.native_bin ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH")
     ; "COMMAND_LOG", fixture.native_command_log
     ]
     @ environment)
    f
;;

let run_native_build fixture target profile =
  Build_system.build_native
    ~framework_root:fixture.native_framework_root
    ~project_root:fixture.native_project_root
    ~config:fixture.native_config
    ~target
    ~profile
;;

let test_native_builds_use_project_local_dune_workspaces () =
  [ Plan.Macos, Plan.Debug; Plan.Iphoneos, Plan.Release ]
  |> List.iter (fun (target, profile) ->
    let fixture = create_native_build_fixture () in
    let installed_tool_before = file_snapshot fixture.native_framework_root "" in
    let global_switch_before = file_snapshot fixture.native_switch_prefix "" in
    let alias_before = read_file fixture.native_alias_path in
    let artifact =
      with_native_build_fixture fixture (fun () ->
        run_native_build fixture target profile |> get_ok)
    in
    Alcotest.(check bool)
      "staged artifact is project-local"
      true
      (String.starts_with
         ~prefix:(fixture.native_project_root ^ "/_build/bonsai-flutter/artifacts/")
         artifact);
    Alcotest.(check string) "staged content" "complete-object" (read_file artifact);
    Alcotest.(check string)
      "normal build does not synchronize Dune files"
      alias_before
      (read_file fixture.native_alias_path);
    Alcotest.(check bool)
      "installed tool assets are read-only inputs"
      true
      (installed_tool_before = file_snapshot fixture.native_framework_root "");
    Alcotest.(check bool)
      "global switch is a read-only input"
      true
      (global_switch_before = file_snapshot fixture.native_switch_prefix "");
    let commands = read_file fixture.native_command_log |> non_empty_lines in
    let dune_builds =
      List.filter (fun command -> contains command "\tdune\tbuild\t") commands
    in
    Alcotest.(check int) "exactly one Dune build" 1 (List.length dune_builds);
    (match target with
     | Plan.Macos -> ()
     | Plan.Iphoneos ->
       let closure_queries =
         List.filter
           (fun command -> contains command "\tdune\tdescribe\texternal-lib-deps\t")
           commands
       in
       Alcotest.(check int) "one reachable closure query" 1 (List.length closure_queries);
       let closure_query = List.hd closure_queries in
       Alcotest.(check bool)
         "iOS closure context"
         true
         (contains closure_query "--context=default.ios"
          && contains closure_query "\t-x\tios"
          && contains closure_query ("--root=" ^ fixture.native_project_root)
          && contains
               closure_query
               (fixture.native_project_root ^ "/_build/bonsai-flutter/dune/iphoneos/")));
    let dune_build = List.hd dune_builds in
    Alcotest.(check bool)
      "application is the Dune root"
      true
      (contains dune_build ("--root=" ^ fixture.native_project_root));
    Alcotest.(check bool)
      "physical build directory is project-local"
      true
      (contains
         dune_build
         ("--build-dir=" ^ fixture.native_project_root ^ "/_build/bonsai-flutter/dune/"));
    Alcotest.(check bool)
      "removed shared workspace paths are absent"
      false
      (contains dune_build "external_apps"
       || contains dune_build "sdk-cache"
       || contains dune_build fixture.native_framework_root))
;;

let test_iphoneos_build_requires_committed_application_lock () =
  let fixture = create_native_build_fixture () in
  Sys.remove (Filename.concat fixture.native_project_root "journal.opam.locked");
  with_native_build_fixture fixture (fun () ->
    run_native_build fixture Plan.Iphoneos Plan.Release
    |> check_error_contains "Application opam lock is missing");
  let commands = read_file fixture.native_command_log |> non_empty_lines in
  Alcotest.(check bool)
    "closure is resolved before subset validation"
    true
    (List.exists
       (fun command -> contains command "\tdune\tdescribe\texternal-lib-deps\t")
       commands);
  Alcotest.(check bool)
    "missing lock stops before Dune build"
    false
    (List.exists (fun command -> contains command "\tdune\tbuild\t") commands)
;;

let test_unchanged_native_build_preserves_outputs () =
  let fixture = create_native_build_fixture () in
  let artifact =
    with_native_build_fixture fixture (fun () ->
      run_native_build fixture Plan.Iphoneos Plan.Release |> get_ok)
  in
  let manifest =
    Filename.concat
      fixture.native_project_root
      "_build/bonsai-flutter/state/iphoneos/release/build-manifest.sexp"
  in
  Alcotest.(check bool) "build manifest exists" true (Sys.file_exists manifest);
  Alcotest.(check bool)
    "manifest records artifact digest"
    true
    (contains (read_file manifest) "(artifact_digest ");
  Unix.utimes artifact 100.0 100.0;
  Unix.utimes manifest 100.0 100.0;
  with_native_build_fixture fixture (fun () ->
    run_native_build fixture Plan.Iphoneos Plan.Release |> get_ok |> ignore);
  Alcotest.(check (float 0.))
    "unchanged staged artifact is untouched"
    100.0
    (Unix.stat artifact).st_mtime;
  Alcotest.(check (float 0.))
    "unchanged build manifest is untouched"
    100.0
    (Unix.stat manifest).st_mtime
;;

type exec_fixture =
  { exec_native : native_build_fixture
  ; exec_working_directory : string
  ; exec_log : string
  ; exec_pub_get_log : string
  ; exec_ready : string
  ; exec_result : string
  ; exec_pubspec : string
  ; exec_artifact : string
  }

let create_exec_fixture () =
  let exec_native = create_native_build_fixture () in
  let project_root = exec_native.native_project_root in
  let config = exec_native.native_config in
  Host.render ~config
  |> List.iter (fun (relative_path, contents) ->
    write_file (Filename.concat project_root relative_path) contents);
  let exec_working_directory = Filename.concat project_root "flutter/macos" in
  let exec_log = Filename.concat project_root "exec.log" in
  let exec_pub_get_log = Filename.concat project_root "pub-get.log" in
  let exec_ready = Filename.concat project_root "exec.ready" in
  let exec_result = Filename.concat project_root "exec.result" in
  let exec_pubspec = Filename.concat project_root "flutter/pubspec.yaml" in
  let exec_artifact =
    Filename.concat
      project_root
      "_build/bonsai-flutter/artifacts/macos/arm64/debug/native_embed.exe.o"
  in
  Scaffold.ensure_directory exec_working_directory;
  write_executable
    (Filename.concat exec_native.native_bin "flutter")
    {|#!/bin/sh
set -eu
if test "${1:-}" = pub && test "${2:-}" = get; then
  mkdir -p .dart_tool
  printf '%s\n' '{"configVersion":2}' > .dart_tool/package_config.json
  printf '%s\n' 'pub get' >> "$EXEC_PUB_GET_LOG"
  exit 0
fi
test -f "$EXEC_ARTIFACT"
grep -q 'native_artifact_profile: debug' "$EXEC_PUBSPEC"
{
  printf 'cwd=%s\n' "$PWD"
  for argument in "$@"; do
    printf 'argument=%s\n' "$argument"
  done
} > "$EXEC_LOG"
if test -n "${EXEC_READY:-}"; then
  : > "$EXEC_READY"
fi
if test "${EXEC_WAIT:-false}" = true; then
  trap 'exit 130' INT
  while :; do
    sleep 1
  done
fi
exit "${EXEC_EXIT:-0}"
|};
  { exec_native
  ; exec_working_directory
  ; exec_log
  ; exec_pub_get_log
  ; exec_ready
  ; exec_result
  ; exec_pubspec
  ; exec_artifact
  }
;;

let with_exec_fixture ?(environment = []) fixture f =
  with_native_build_fixture
    ~environment:
      ([ "EXEC_ARTIFACT", fixture.exec_artifact
       ; "EXEC_PUBSPEC", fixture.exec_pubspec
       ; "EXEC_LOG", fixture.exec_log
       ; "EXEC_PUB_GET_LOG", fixture.exec_pub_get_log
       ]
       @ environment)
    fixture.exec_native
    f
;;

let run_exec fixture command =
  Build_system.exec
    ~framework_root:fixture.exec_native.native_framework_root
    ~project_root:fixture.exec_native.native_project_root
    ~config:fixture.exec_native.native_config
    ~profile:Plan.Debug
    ~working_directory:fixture.exec_working_directory
    ~command
;;

let check_exec_host_is_canonical fixture =
  Alcotest.(check string)
    "canonical pubspec is restored"
    (Host.pubspec fixture.exec_native.native_config)
    (read_file fixture.exec_pubspec);
  Alcotest.(check (list string))
    "sync-host check is clean"
    []
    (Host.sync
       ~project_root:fixture.exec_native.native_project_root
       ~config:fixture.exec_native.native_config
       ~mode:Host.Check
     |> get_ok)
;;

let test_exec_builds_injects_and_runs_command_verbatim () =
  let fixture = create_exec_fixture () in
  let command = [ "flutter"; "test"; "--no-pub"; "test"; "argument with spaces" ] in
  let status = with_exec_fixture fixture (fun () -> run_exec fixture command |> get_ok) in
  Alcotest.(check int) "successful child status" 0 status;
  Alcotest.(check (list string))
    "pub get runs before the child command"
    [ "pub get" ]
    (read_file fixture.exec_pub_get_log |> non_empty_lines);
  Alcotest.(check (list string))
    "cwd and arguments"
    [ "cwd=" ^ fixture.exec_working_directory
    ; "argument=test"
    ; "argument=--no-pub"
    ; "argument=test"
    ; "argument=argument with spaces"
    ]
    (read_file fixture.exec_log |> non_empty_lines);
  Alcotest.(check bool)
    "debug artifact was built"
    true
    (Sys.file_exists fixture.exec_artifact);
  Alcotest.(check bool)
    "Flutter build lock was acquired"
    true
    (Sys.file_exists
       (Filename.concat
          fixture.exec_native.native_project_root
          "_build/bonsai-flutter/locks/flutter.lock"));
  check_exec_host_is_canonical fixture
;;

let test_exec_preserves_child_failure_status_and_restores_pubspec () =
  let fixture = create_exec_fixture () in
  let status =
    with_exec_fixture
      ~environment:[ "EXEC_EXIT", "37" ]
      fixture
      (fun () -> run_exec fixture [ "flutter"; "test" ] |> get_ok)
  in
  Alcotest.(check int) "child failure status" 37 status;
  check_exec_host_is_canonical fixture
;;

let rec wait_for_file path attempts =
  if Sys.file_exists path
  then true
  else if attempts = 0
  then false
  else (
    Unix.sleepf 0.01;
    wait_for_file path (attempts - 1))
;;

let test_exec_forwards_interrupt_and_restores_pubspec () =
  let fixture = create_exec_fixture () in
  match Unix.fork () with
  | 0 ->
    let status =
      with_exec_fixture
        ~environment:[ "EXEC_READY", fixture.exec_ready; "EXEC_WAIT", "true" ]
        fixture
        (fun () -> run_exec fixture [ "flutter"; "test" ] |> get_ok)
    in
    write_file fixture.exec_result (string_of_int status);
    Unix._exit 0
  | pid ->
    if not (wait_for_file fixture.exec_ready 500)
    then (
      Unix.kill pid Sys.sigkill;
      ignore (Unix.waitpid [] pid);
      Alcotest.fail "timed out waiting for exec child command");
    Unix.kill pid Sys.sigint;
    let _, child_status = Unix.waitpid [] pid in
    Alcotest.(check int)
      "exec process completed cleanup"
      0
      (match child_status with
       | Unix.WEXITED code -> code
       | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> 128 + signal);
    Alcotest.(check string) "interrupt status" "130" (read_file fixture.exec_result);
    check_exec_host_is_canonical fixture
;;

let test_exec_stops_before_command_when_native_build_fails () =
  let fixture = create_exec_fixture () in
  with_exec_fixture
    ~environment:[ "VERIFY_EXIT", "55" ]
    fixture
    (fun () ->
       run_exec fixture [ "flutter"; "test" ]
       |> check_error_contains "verify_complete_object");
  Alcotest.(check bool)
    "child command was not run"
    false
    (Sys.file_exists fixture.exec_log);
  check_exec_host_is_canonical fixture
;;

let test_exec_rejects_an_empty_command () =
  let fixture = create_exec_fixture () in
  with_exec_fixture fixture (fun () ->
    run_exec fixture [] |> check_error_contains "command is required");
  Alcotest.(check bool)
    "native build was not started"
    false
    (Sys.file_exists fixture.exec_artifact);
  check_exec_host_is_canonical fixture
;;

let test_managed_adapter_sync_preserves_application_code () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "managed-sync" in
  let config = Config.parse_string managed_adapter_config |> get_ok in
  let adapter_path = Filename.concat root "flutter/lib/application_host_adapter.dart" in
  let application_owned = "// application-owned adapter\nfinal sentinel = 42;\n" in
  write_file adapter_path application_owned;
  let first = Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok in
  Alcotest.(check bool)
    "adapter is not a generated output"
    false
    (List.mem "flutter/lib/application_host_adapter.dart" first);
  Alcotest.(check string)
    "first sync preserves adapter"
    application_owned
    (read_file adapter_path);
  let second = Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok in
  Alcotest.(check (list string)) "second sync is idempotent" [] second;
  Host.sync ~project_root:root ~config ~mode:Host.Check |> get_ok |> ignore;
  Alcotest.(check string)
    "check preserves adapter"
    application_owned
    (read_file adapter_path);
  Host.render ~config
  |> List.iter (fun (relative, expected) ->
    Alcotest.(check string)
      ("write/render parity for " ^ relative)
      expected
      (read_file (Filename.concat root relative)));
  let main_path = Filename.concat root "flutter/lib/main.dart" in
  write_file main_path "// generated host drift\n";
  Host.sync ~project_root:root ~config ~mode:Host.Check
  |> check_error_contains "flutter/lib/main.dart";
  Alcotest.(check string)
    "drift check does not touch adapter"
    application_owned
    (read_file adapter_path)
;;

let test_macos_host_settings_sync () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "macos-sync" in
  let config = Config.parse_string valid_config |> get_ok in
  let configs_root = Filename.concat root "flutter/macos/Runner/Configs" in
  let debug = Filename.concat configs_root "Debug.xcconfig" in
  let release = Filename.concat configs_root "Release.xcconfig" in
  let app_info = Filename.concat configs_root "AppInfo.xcconfig" in
  write_file debug "#include \"../../Flutter/Flutter-Debug.xcconfig\"\n";
  write_file release "#include \"../../Flutter/Flutter-Release.xcconfig\"\n";
  write_file app_info "PRODUCT_NAME = journal\n";
  let project = Filename.concat root "flutter/macos/Runner.xcodeproj/project.pbxproj" in
  write_file project "buildSettings = {\n\tMACOSX_DEPLOYMENT_TARGET = 10.15;\n};\n";
  Host.sync ~project_root:root ~config ~mode:Host.Check
  |> check_error_contains "Debug.xcconfig";
  Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok |> ignore;
  [ debug; release; app_info ]
  |> List.iter (fun path ->
    Alcotest.(check bool)
      "managed include"
      true
      (contains (read_file path) "#include \"BonsaiFlutter.xcconfig\""));
  Alcotest.(check bool)
    "obsolete project deployment target is removed"
    false
    (contains (read_file project) "MACOSX_DEPLOYMENT_TARGET = 10.15");
  let managed = Filename.concat configs_root "BonsaiFlutter.xcconfig" in
  write_file managed "MACOSX_DEPLOYMENT_TARGET = 25.0\nARCHS = x86_64\n";
  Host.sync ~project_root:root ~config ~mode:Host.Check
  |> check_error_contains "BonsaiFlutter.xcconfig"
;;

let test_host_scopes_artifact_profile_to_flutter_invocation () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "artifact-profile" in
  let config = Config.parse_string valid_config |> get_ok in
  let pubspec_path = Filename.concat root "flutter/pubspec.yaml" in
  write_file pubspec_path (Host.pubspec config);
  Host.with_artifact_profile ~project_root:root ~config ~profile:"profile" (fun () ->
    Alcotest.(check bool)
      "profile is visible to Native Assets"
      true
      (contains (read_file pubspec_path) "native_artifact_profile: profile");
    Ok ())
  |> get_ok;
  Alcotest.(check string)
    "canonical pubspec is restored"
    (Host.pubspec config)
    (read_file pubspec_path)
;;

let test_flutter_plans () =
  let config = Config.parse_string valid_config |> get_ok in
  let run =
    Plan.flutter
      ~project_root:"/work/journal"
      ~config
      ~action:Plan.Run
      ~platform:Plan.Macos_platform
      ~profile:Plan.Debug
      ~device:None
      ~no_codesign:false
      ~forwarded:[ "--dart-define=environment=development" ]
  in
  Alcotest.(check string) "Flutter cwd" "/work/journal/flutter" run.working_directory;
  Alcotest.(check (list string))
    "macOS run"
    [ "run"; "-d"; "macos"; "--dart-define=environment=development" ]
    run.arguments;
  Alcotest.(check (list (pair string string))) "debug artifact profile" [] run.environment;
  let ios_debug =
    Plan.flutter
      ~project_root:"/work/journal"
      ~config
      ~action:Plan.Run
      ~platform:Plan.Ios_platform
      ~profile:Plan.Debug
      ~device:(Some "physical-device")
      ~no_codesign:false
      ~forwarded:[ "--dart-define=environment=development" ]
  in
  Alcotest.(check (list string))
    "iOS debug continues through flutter run"
    [ "run"; "-d"; "physical-device"; "--dart-define=environment=development" ]
    ios_debug.arguments;
  Alcotest.(check (list (pair string string)))
    "iOS debug artifact profile"
    []
    ios_debug.environment;
  let ios =
    Plan.flutter
      ~project_root:"/work/journal"
      ~config
      ~action:Plan.Build
      ~platform:Plan.Ios_platform
      ~profile:Plan.Release
      ~device:None
      ~no_codesign:true
      ~forwarded:[]
  in
  Alcotest.(check (list string))
    "unsigned iOS release"
    [ "build"; "ios"; "--release"; "--no-codesign"; "--no-tree-shake-icons" ]
    ios.arguments;
  Alcotest.(check (list (pair string string)))
    "release artifact profile"
    []
    ios.environment;
  let profile =
    Plan.flutter
      ~project_root:"/work/journal"
      ~config
      ~action:Plan.Build
      ~platform:Plan.Macos_platform
      ~profile:Plan.Profile
      ~device:None
      ~no_codesign:false
      ~forwarded:[]
  in
  Alcotest.(check (list (pair string string)))
    "profile artifact profile"
    []
    profile.environment
;;

let count_argument expected arguments =
  arguments |> List.filter (String.equal expected) |> List.length
;;

let flutter_plan ~action ~platform ~profile ~forwarded =
  Plan.flutter
    ~project_root:"/work/journal"
    ~config:(Config.parse_string valid_config |> get_ok)
    ~action
    ~platform
    ~profile
    ~device:None
    ~no_codesign:false
    ~forwarded
;;

let check_icon_tree_shaking_disabled name command =
  Alcotest.(check int)
    (name ^ " has one disabling flag")
    1
    (count_argument "--no-tree-shake-icons" command.Plan.arguments);
  Alcotest.(check int)
    (name ^ " has no enabling flag")
    0
    (count_argument "--tree-shake-icons" command.arguments)
;;

let check_icon_tree_shaking_flags_absent name command =
  Alcotest.(check int)
    (name ^ " has no disabling build flag")
    0
    (count_argument "--no-tree-shake-icons" command.Plan.arguments);
  Alcotest.(check int)
    (name ^ " has no enabling build flag")
    0
    (count_argument "--tree-shake-icons" command.arguments)
;;

let test_flutter_builds_preserve_runtime_material_icons () =
  [ "macOS Profile", Plan.Macos_platform, Plan.Profile
  ; "macOS Release", Plan.Macos_platform, Plan.Release
  ; "iOS Profile", Plan.Ios_platform, Plan.Profile
  ; "iOS Release", Plan.Ios_platform, Plan.Release
  ]
  |> List.iter (fun (name, platform, profile) ->
    flutter_plan ~action:Plan.Build ~platform ~profile ~forwarded:[]
    |> check_icon_tree_shaking_disabled name)
;;

let test_flutter_runs_omit_build_only_icon_flags () =
  [ "macOS Profile", Plan.Macos_platform, Plan.Profile
  ; "macOS Release", Plan.Macos_platform, Plan.Release
  ; "iOS Profile", Plan.Ios_platform, Plan.Profile
  ; "iOS Release", Plan.Ios_platform, Plan.Release
  ]
  |> List.iter (fun (name, platform, profile) ->
    flutter_plan ~action:Plan.Run ~platform ~profile ~forwarded:[]
    |> check_icon_tree_shaking_flags_absent name)
;;

let test_flutter_run_preserves_forwarded_arguments () =
  let command =
    flutter_plan
      ~action:Plan.Run
      ~platform:Plan.Macos_platform
      ~profile:Plan.Release
      ~forwarded:[ "--dart-define=environment=development"; "--route"; "/journal" ]
  in
  Alcotest.(check (list string))
    "run arguments are forwarded without build-only icon flags"
    [ "run"
    ; "-d"
    ; "macos"
    ; "--release"
    ; "--dart-define=environment=development"
    ; "--route"
    ; "/journal"
    ]
    command.arguments
;;

let test_flutter_icon_protection_preserves_forwarded_arguments () =
  let command =
    flutter_plan
      ~action:Plan.Build
      ~platform:Plan.Macos_platform
      ~profile:Plan.Release
      ~forwarded:[ "--dart-define=environment=development"; "--"; "application-value" ]
  in
  Alcotest.(check (list string))
    "framework flag precedes untouched forwarded arguments"
    [ "build"
    ; "macos"
    ; "--release"
    ; "--no-tree-shake-icons"
    ; "--dart-define=environment=development"
    ; "--"
    ; "application-value"
    ]
    command.arguments
;;

let test_flutter_icon_protection_normalizes_conflicting_arguments () =
  let command =
    flutter_plan
      ~action:Plan.Build
      ~platform:Plan.Ios_platform
      ~profile:Plan.Profile
      ~forwarded:
        [ "--no-tree-shake-icons"
        ; "--dart-define=environment=development"
        ; "--tree-shake-icons"
        ; "--no-tree-shake-icons"
        ]
  in
  Alcotest.(check (list string))
    "unsafe and duplicate flags are normalized"
    [ "build"
    ; "ios"
    ; "--profile"
    ; "--no-tree-shake-icons"
    ; "--dart-define=environment=development"
    ]
    command.arguments
;;

let test_flutter_debug_and_generated_host_remain_unchanged () =
  let debug =
    flutter_plan
      ~action:Plan.Build
      ~platform:Plan.Macos_platform
      ~profile:Plan.Debug
      ~forwarded:[ "--dart-define=environment=development" ]
  in
  Alcotest.(check (list string))
    "Debug needs no explicit icon retention flag"
    [ "build"; "macos"; "--debug"; "--dart-define=environment=development" ]
    debug.arguments;
  let pubspec = Host.pubspec (Config.parse_string valid_config |> get_ok) in
  Alcotest.(check bool)
    "generated pubspec contains no icon tree-shaking policy"
    false
    (contains pubspec "tree-shake-icons")
;;

let test_flutter_pub_get_runs_only_when_dependency_inputs_change () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "flutter-pub-get" |> Unix.realpath in
  let project_root = Filename.concat root "project" in
  let flutter_root = Filename.concat project_root "flutter" in
  let packages_root = Filename.concat project_root ".bonsai-flutter/flutter-packages" in
  let bonsai_flutter_pubspec =
    Filename.concat packages_root "bonsai_flutter/pubspec.yaml"
  in
  let native_pubspec =
    Filename.concat packages_root "bonsai_flutter_native/pubspec.yaml"
  in
  let package_config = Filename.concat flutter_root ".dart_tool/package_config.json" in
  let state =
    Filename.concat project_root "_build/bonsai-flutter/state/flutter/pub-get.sexp"
  in
  let bin = Filename.concat root "bin" in
  let command_log = Filename.concat root "commands.log" in
  let config = Config.parse_string valid_config |> get_ok in
  write_file (Filename.concat flutter_root "pubspec.yaml") "name: journal\n";
  write_file bonsai_flutter_pubspec "name: bonsai_flutter\nversion: 0.1.0\n";
  write_file native_pubspec "name: bonsai_flutter_native\nversion: 0.1.0\n";
  write_file command_log "";
  write_executable
    (Filename.concat bin "flutter")
    (command_logger "flutter"
     ^ {|mkdir -p .dart_tool
printf '%s\n' '{"configVersion":2}' > .dart_tool/package_config.json
|}
    );
  let path = bin ^ ":" ^ Sys.getenv "PATH" in
  with_environment
    [ "PATH", path; "COMMAND_LOG", command_log ]
    (fun () ->
       Build_system.flutter_pub_get ~project_root ~config |> get_ok;
       Alcotest.(check int)
         "first run"
         1
         (List.length (non_empty_lines (read_file command_log)));
       Alcotest.(check bool) "state written" true (Sys.file_exists state);
       Unix.utimes state 100. 100.;
       Build_system.flutter_pub_get ~project_root ~config |> get_ok;
       Alcotest.(check int)
         "unchanged inputs skip pub get"
         1
         (List.length (non_empty_lines (read_file command_log)));
       Alcotest.(check (float 0.))
         "unchanged state timestamp"
         100.
         (Unix.stat state).st_mtime;
       write_file bonsai_flutter_pubspec "name: bonsai_flutter\nversion: 0.2.0\n";
       Build_system.flutter_pub_get ~project_root ~config |> get_ok;
       Alcotest.(check int)
         "path package change reruns pub get"
         2
         (List.length (non_empty_lines (read_file command_log)));
       Sys.remove package_config;
       Build_system.flutter_pub_get ~project_root ~config |> get_ok;
       Alcotest.(check int)
         "missing package config reruns pub get"
         3
         (List.length (non_empty_lines (read_file command_log))))
;;

let test_flutter_pub_get_requires_project_pubspec () =
  let project_root = Filename.temp_dir "bonsai-flutter-tool" "missing-pubspec" in
  let config = Config.parse_string valid_config |> get_ok in
  Scaffold.ensure_directory (Filename.concat project_root config.Config.flutter_root);
  Build_system.flutter_pub_get ~project_root ~config
  |> check_error_contains "Flutter dependency input is missing"
;;

let test_ios_app_bundle_paths () =
  let config = Config.parse_string valid_config |> get_ok in
  [ Plan.Debug, "Debug-iphoneos"
  ; Plan.Profile, "Profile-iphoneos"
  ; Plan.Release, "Release-iphoneos"
  ]
  |> List.iter (fun (profile, configuration) ->
    Alcotest.(check string)
      (Plan.profile_name profile)
      ("/work/journal/flutter/build/ios/" ^ configuration ^ "/Runner.app")
      (Plan.ios_app_bundle ~project_root:"/work/journal" ~config ~profile))
;;

let test_ios_device_command_plans () =
  let config = Config.parse_string valid_config |> get_ok in
  let app_bundle =
    Plan.ios_app_bundle ~project_root:"/work/journal" ~config ~profile:Plan.Release
  in
  let bundle_identifier =
    Plan.ios_bundle_identifier ~project_root:"/work/journal" ~app_bundle
  in
  Alcotest.(check string) "bundle identifier program" "plutil" bundle_identifier.program;
  Alcotest.(check (list string))
    "bundle identifier arguments"
    [ "-extract"
    ; "CFBundleIdentifier"
    ; "raw"
    ; "-o"
    ; "-"
    ; Filename.concat app_bundle "Info.plist"
    ]
    bundle_identifier.arguments;
  let install =
    Plan.ios_device_install
      ~project_root:"/work/journal"
      ~device:"00008110-000A71C414BB801E"
      ~app_bundle
  in
  Alcotest.(check string) "install program" "xcrun" install.program;
  Alcotest.(check string) "install cwd" "/work/journal" install.working_directory;
  Alcotest.(check (list string))
    "install arguments"
    [ "devicectl"
    ; "device"
    ; "install"
    ; "app"
    ; "--device"
    ; "00008110-000A71C414BB801E"
    ; app_bundle
    ]
    install.arguments;
  let launch =
    Plan.ios_device_launch
      ~project_root:"/work/journal"
      ~device:"00008110-000A71C414BB801E"
      ~bundle_identifier:"com.example.journal"
  in
  Alcotest.(check string) "launch program" "xcrun" launch.program;
  Alcotest.(check (list string))
    "launch arguments"
    [ "devicectl"
    ; "device"
    ; "process"
    ; "launch"
    ; "--device"
    ; "00008110-000A71C414BB801E"
    ; "--terminate-existing"
    ; "com.example.journal"
    ]
    launch.arguments
;;

let test_ios_release_device_run () =
  let fixture = create_ios_tool_fixture () in
  let app_bundle = create_ios_app_bundle fixture Plan.Release in
  with_ios_tool_fixture
    ~environment:[ "BUNDLE_IDENTIFIER", "com.acme.release-journal" ]
    fixture
    (fun () ->
       run_ios_device
         fixture
         ~profile:Plan.Release
         ~device:"00008110-000A71C414BB801E"
         ~forwarded:[ "--dart-define=environment=production"; "--verbose" ]
       |> get_ok);
  let flutter_root = Filename.concat fixture.project_root "flutter" in
  Alcotest.(check (list string))
    "release build, verify, identifier, install, and launch"
    [ String.concat
        "\t"
        [ "flutter"
        ; flutter_root
        ; "build"
        ; "ios"
        ; "--release"
        ; "--no-tree-shake-icons"
        ; "--dart-define=environment=production"
        ; "--verbose"
        ]
    ; String.concat
        "\t"
        [ "verify_app_bundle"; fixture.project_root; app_bundle; "require-sqlite" ]
    ; String.concat
        "\t"
        [ "plutil"
        ; fixture.project_root
        ; "-extract"
        ; "CFBundleIdentifier"
        ; "raw"
        ; "-o"
        ; "-"
        ; Filename.concat app_bundle "Info.plist"
        ]
    ; String.concat
        "\t"
        [ "xcrun"
        ; fixture.project_root
        ; "devicectl"
        ; "device"
        ; "install"
        ; "app"
        ; "--device"
        ; "00008110-000A71C414BB801E"
        ; app_bundle
        ]
    ; String.concat
        "\t"
        [ "xcrun"
        ; fixture.project_root
        ; "devicectl"
        ; "device"
        ; "process"
        ; "launch"
        ; "--device"
        ; "00008110-000A71C414BB801E"
        ; "--terminate-existing"
        ; "com.acme.release-journal"
        ]
    ]
    (read_file fixture.command_log |> non_empty_lines)
;;

let test_ios_profile_device_run () =
  let fixture = create_ios_tool_fixture () in
  let app_bundle = create_ios_app_bundle fixture Plan.Profile in
  with_ios_tool_fixture fixture (fun () ->
    run_ios_device
      fixture
      ~profile:Plan.Profile
      ~device:"profile-device"
      ~forwarded:[ "--flavor"; "internal" ]
    |> get_ok);
  let commands = read_file fixture.command_log |> non_empty_lines in
  Alcotest.(check string)
    "profile build preserves profile mode and forwarded arguments"
    (String.concat
       "\t"
       [ "flutter"
       ; Filename.concat fixture.project_root "flutter"
       ; "build"
       ; "ios"
       ; "--profile"
       ; "--no-tree-shake-icons"
       ; "--flavor"
       ; "internal"
       ])
    (List.hd commands);
  Alcotest.(check bool)
    "profile bundle is verified"
    true
    (List.mem
       (String.concat
          "\t"
          [ "verify_app_bundle"; fixture.project_root; app_bundle; "require-sqlite" ])
       commands)
;;

let test_ios_device_run_reports_missing_bundle () =
  let fixture = create_ios_tool_fixture () in
  let expected_bundle =
    Plan.ios_app_bundle
      ~project_root:fixture.project_root
      ~config:fixture.config
      ~profile:Plan.Release
  in
  with_ios_tool_fixture fixture (fun () ->
    run_ios_device
      fixture
      ~profile:Plan.Release
      ~device:"missing-bundle-device"
      ~forwarded:[]
    |> check_error_contains expected_bundle);
  Alcotest.(check int)
    "stops after Flutter build"
    1
    (read_file fixture.command_log |> non_empty_lines |> List.length)
;;

let test_ios_device_run_propagates_flutter_failure () =
  let fixture = create_ios_tool_fixture () in
  ignore (create_ios_app_bundle fixture Plan.Release);
  with_ios_tool_fixture
    ~environment:[ "FLUTTER_EXIT", "17" ]
    fixture
    (fun () ->
       run_ios_device
         fixture
         ~profile:Plan.Release
         ~device:"flutter-failure-device"
         ~forwarded:[]
       |> check_error_contains "flutter exited with status 17");
  Alcotest.(check int)
    "does not verify or install after failed build"
    1
    (read_file fixture.command_log |> non_empty_lines |> List.length)
;;

let test_ios_device_run_propagates_install_failure () =
  let fixture = create_ios_tool_fixture () in
  ignore (create_ios_app_bundle fixture Plan.Release);
  with_ios_tool_fixture
    ~environment:[ "INSTALL_EXIT", "23" ]
    fixture
    (fun () ->
       run_ios_device
         fixture
         ~profile:Plan.Release
         ~device:"install-failure-device"
         ~forwarded:[]
       |> check_error_contains "xcrun exited with status 23");
  let commands = read_file fixture.command_log |> non_empty_lines in
  Alcotest.(check int) "launch is not attempted" 4 (List.length commands)
;;

let test_ios_device_run_rejects_empty_bundle_identifier () =
  let fixture = create_ios_tool_fixture () in
  ignore (create_ios_app_bundle fixture Plan.Release);
  with_ios_tool_fixture
    ~environment:[ "BUNDLE_IDENTIFIER", " " ]
    fixture
    (fun () ->
       run_ios_device
         fixture
         ~profile:Plan.Release
         ~device:"empty-identifier-device"
         ~forwarded:[]
       |> check_error_contains "CFBundleIdentifier");
  let commands = read_file fixture.command_log |> non_empty_lines in
  Alcotest.(check int) "install is not attempted" 3 (List.length commands)
;;

let test_artifact_layout () =
  let config = Config.parse_string valid_config |> get_ok in
  let build =
    Plan.native_build
      ~project_root:"/work/journal"
      ~config
      ~target:Plan.Iphoneos
      ~profile:Plan.Release
      ~toolchain_fingerprint:"sdk-fingerprint"
      ~apple_sdk_root:"/Xcode/iPhoneOS.sdk"
      ~apple_sdk_version:(Some "26.0")
    |> get_ok
  in
  Alcotest.(check string)
    "source follows custom Dune build directory"
    "/work/journal/_build/bonsai-flutter/dune/iphoneos/sdk-fingerprint/release/default.ios/app/native_embed.exe.o"
    build.source_object;
  Alcotest.(check string)
    "staged artifact includes profile"
    "/work/journal/_build/bonsai-flutter/artifacts/ios/iphoneos/arm64/release/native_embed.exe.o"
    build.staged_object
;;

let test_macos_artifact_staging_contract () =
  let fixture = create_native_build_fixture () in
  let destination =
    with_native_build_fixture fixture (fun () ->
      run_native_build fixture Plan.Macos Plan.Release |> get_ok)
  in
  let verifier_commands =
    read_file fixture.native_command_log
    |> non_empty_lines
    |> List.filter (fun command -> contains command "verify_complete_object")
  in
  Alcotest.(check bool)
    "verifier receives staged sibling and platform contract"
    true
    (List.exists
       (fun command ->
          contains command "\tMACOS\t26.0\tarm64"
          && not (contains command ("\t" ^ destination ^ "\t")))
       verifier_commands);
  with_native_build_fixture
    ~environment:
      [ "OBJECT_CONTENT", "rejected-complete-object"
      ; "REWRITE_OBJECT", "true"
      ; "VERIFY_EXIT", "9"
      ]
    fixture
    (fun () ->
       run_native_build fixture Plan.Macos Plan.Release
       |> check_error_contains "exited with status 9");
  Alcotest.(check string)
    "failed verification preserves previous artifact"
    "complete-object"
    (read_file destination);
  let siblings = Sys.readdir (Filename.dirname destination) |> Array.to_list in
  Alcotest.(check bool)
    "failed staging removes temporary sibling"
    false
    (List.exists
       (fun name -> String.starts_with ~prefix:".native_embed.exe.o.tmp" name)
       siblings)
;;

let test_macos_network_artifact_embeds_static_gmp () =
  let fixture = create_native_build_fixture () in
  let config =
    { fixture.native_config with
      features = [ Config.Feature.Core; Config.Feature.Network ]
    }
  in
  let gmp_directory = Filename.concat fixture.native_project_root "static-gmp" in
  let gmp_archive = Filename.concat gmp_directory "libgmp.a" in
  write_file gmp_archive "static-gmp";
  write_executable
    (Filename.concat fixture.native_bin "pkg-config")
    (command_logger "pkg-config" ^ Printf.sprintf "printf '%%s\\n' '%s'\n" gmp_directory);
  write_executable
    (Filename.concat fixture.native_bin "clang")
    (command_logger "clang"
     ^ {|output=''
previous=''
for argument in "$@"; do
  if test "$previous" = -o; then output=$argument; fi
  previous=$argument
done
test -n "$output"
printf '%s' 'complete-object-with-static-gmp' > "$output"
|}
    );
  write_executable
    (Filename.concat fixture.native_bin "nm")
    (command_logger "nm" ^ "exit 0\n");
  let destination =
    with_native_build_fixture fixture (fun () ->
      Build_system.build_native
        ~framework_root:fixture.native_framework_root
        ~project_root:fixture.native_project_root
        ~config
        ~target:Plan.Macos
        ~profile:Plan.Release
      |> get_ok)
  in
  Alcotest.(check string)
    "staged network object contains static GMP"
    "complete-object-with-static-gmp"
    (read_file destination);
  let commands = read_file fixture.native_command_log |> non_empty_lines in
  Alcotest.(check bool)
    "GMP archive is resolved with pkg-config"
    true
    (List.exists
       (fun command ->
          contains command "pkg-config" && contains command "\t--variable=libdir\tgmp")
       commands);
  Alcotest.(check bool)
    "network object is relocatably linked with static GMP"
    true
    (List.exists
       (fun command ->
          contains command "clang"
          && contains command "\t-r\t-target\tarm64-apple-macos26.0"
          && contains command gmp_archive)
       commands)
;;

let dune_description source =
  let length = String.length source in
  let buffer = Buffer.create length in
  let rec loop index =
    if index = length
    then Buffer.contents buffer
    else (
      match source.[index] with
      | ' ' | '\n' | '\r' | '\t' -> loop (index + 1)
      | ('(' | ')') as delimiter ->
        Buffer.add_char buffer delimiter;
        loop (index + 1)
      | _ ->
        let stop = ref index in
        while
          !stop < length
          && not (List.mem source.[!stop] [ ' '; '\n'; '\r'; '\t'; '('; ')' ])
        do
          incr stop
        done;
        let atom = String.sub source index (!stop - index) in
        Buffer.add_string buffer (string_of_int (String.length atom));
        Buffer.add_char buffer ':';
        Buffer.add_string buffer atom;
        loop !stop)
  in
  loop 0
;;

let resolve_dune_closure ?(target = "app/native_embed.exe.o") source =
  Dune_closure.resolve_csexp ~target (dune_description source)
;;

let check_dune_closure expected source =
  Alcotest.(check (result (list string) string))
    "external dependency closure"
    (Ok expected)
    (resolve_dune_closure source)
;;

let test_dune_closure_follows_local_app () =
  check_dune_closure
    [ "datascript-ocaml-native" ]
    {|
      (default
       ((library
         ((names (app))
          (extensions ())
          (package ())
          (source_dir app)
          (external_deps ((datascript-ocaml-native required)))
          (internal_deps ())))
        (executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ())
          (internal_deps ((app required)))))))
    |}
;;

let test_dune_closure_follows_arbitrary_local_library () =
  check_dune_closure
    [ "base" ]
    {|
      (default
       ((executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ())
          (internal_deps ((journal_core required)))))
        (library
         ((names (journal_core))
          (extensions ())
          (package ())
          (source_dir journal)
          (external_deps ((base required)))
          (internal_deps ())))))
    |}
;;

let test_dune_closure_excludes_local_component_roots () =
  check_dune_closure
    [ "datascript-ocaml-native.sqlite" ]
    {|
      (default
       ((library
         ((names (journal_core))
          (extensions ())
          (package ())
          (source_dir lib)
          (external_deps ((datascript-ocaml-native.sqlite required)))
          (internal_deps ())))
        (executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ((datascript-ocaml-native.sqlite required)))
          (internal_deps ((journal_core required)))))))
    |}
;;

let test_dune_closure_follows_transitive_local_chain () =
  check_dune_closure
    [ "uutf" ]
    {|
      (default
       ((library
         ((names (domain))
          (extensions ())
          (package ())
          (source_dir domain)
          (external_deps ((uutf required)))
          (internal_deps ())))
        (executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ())
          (internal_deps ((application required)))))
        (library
         ((names (application))
          (extensions ())
          (package ())
          (source_dir application)
          (external_deps ())
          (internal_deps ((domain required)))))))
    |}
;;

let test_dune_closure_ignores_unreachable_stanzas () =
  check_dune_closure
    [ "base" ]
    {|
      (default
       ((tests
         ((names (application_test))
          (extensions (.exe))
          (package ())
          (source_dir test)
          (external_deps ((alcotest required) (ppx_expect required)))
          (internal_deps ((application required)))))
        (executables
         ((names (benchmark))
          (extensions (.exe))
          (package ())
          (source_dir bench)
          (external_deps ((core_bench required)))
          (internal_deps ((application required)))))
        (library
         ((names (application))
          (extensions ())
          (package ())
          (source_dir app)
          (external_deps ((base required)))
          (internal_deps ())))
        (executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ())
          (internal_deps ((application required)))))))
    |}
;;

let test_dune_closure_combines_direct_and_indirect_external_dependencies () =
  check_dune_closure
    [ "bonsai_flutter.driver"; "core"; "uucp" ]
    {|
      (default
       ((executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ((core required) (bonsai_flutter.driver required)))
          (internal_deps ((application required)))))
        (library
         ((names (application))
          (extensions ())
          (package ())
          (source_dir app)
          (external_deps ((uucp required) (core required)))
          (internal_deps ())))))
    |}
;;

let test_dune_closure_keeps_ppx_only_stanzas_host_only () =
  check_dune_closure
    [ "base" ]
    {|
      (default
       ((tests
         ((names (ppx_test))
          (extensions (.exe))
          (package ())
          (source_dir test)
          (external_deps ((ppx_expect required)))
          (internal_deps ())))
        (executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ((base required)))
          (internal_deps ())))))
    |}
;;

let test_dune_closure_reports_missing_local_stanza () =
  let actual =
    resolve_dune_closure
      {|
        (default
         ((executables
           ((names (native_embed))
            (extensions (.exe.o))
            (package ())
            (source_dir app)
            (external_deps ())
            (internal_deps ((missing_local required)))))))
      |}
  in
  Alcotest.(check (result (list string) string))
    "workspace diagnostic"
    (Error
       "Dune workspace dependency graph references a missing local stanza: missing_local")
    actual
;;

let test_dune_closure_accepts_selected_ios_context () =
  let description =
    dune_description
      {|
        (default.ios
         ((executables
           ((names (native_embed))
            (extensions (.exe.o))
            (package ())
            (source_dir app)
            (external_deps ((bonsai_flutter.ui required)))
            (internal_deps ())))))
      |}
  in
  Alcotest.(check (result (list string) string))
    "iOS context dependency closure"
    (Ok [ "bonsai_flutter.ui" ])
    (Dune_closure.resolve_csexp
       ~context:"default.ios"
       ~target:"app/native_embed.exe.o"
       description)
;;

let test_dune_closure_rejects_invalid_semantic_output () =
  let expected = Error "Malformed Dune external dependency description" in
  Alcotest.(check (result (list string) string))
    "malformed output"
    expected
    (Dune_closure.resolve_csexp ~target:"app/native_embed.exe.o" "(4:atom");
  let unsupported = dune_description "(future ())" in
  Alcotest.(check (result (list string) string))
    "unsupported output"
    (Error "Unsupported Dune external dependency description")
    (Dune_closure.resolve_csexp ~target:"app/native_embed.exe.o" unsupported)
;;

let test_dune_closure_output_is_deterministic () =
  let first =
    {|
      (default
       ((library
         ((names (application)) (extensions ()) (package ()) (source_dir app)
          (external_deps ((uutf required) (base required))) (internal_deps ())))
        (executables
         ((names (native_embed)) (extensions (.exe.o)) (package ()) (source_dir app)
          (external_deps ((core required)))
          (internal_deps ((application required)))))))
    |}
  in
  let second =
    {|
      (default
       ((executables
         ((internal_deps ((application required)))
          (external_deps ((core required))) (source_dir app) (package ())
          (extensions (.exe.o)) (names (native_embed))))
        (library
         ((internal_deps ()) (external_deps ((base required) (uutf required)))
          (source_dir app) (package ()) (extensions ()) (names (application))))))
    |}
  in
  Alcotest.(check (result (list string) string))
    "ordering independent"
    (resolve_dune_closure first)
    (resolve_dune_closure second);
  Alcotest.(check (result (list string) string))
    "canonical ordering"
    (Ok [ "base"; "core"; "uutf" ])
    (resolve_dune_closure first)
;;

let () =
  Alcotest.run
    "bonsai_flutter_tool"
    [ ( "config"
      , [ Alcotest.test_case "valid" `Quick test_parse_valid_config
        ; Alcotest.test_case "invalid" `Quick test_invalid_configs
        ; Alcotest.test_case
            "managed adapter validation"
            `Quick
            test_managed_adapter_config_validation
        ; Alcotest.test_case
            "custom host validation"
            `Quick
            test_custom_host_config_validation
        ; Alcotest.test_case
            "missing host migration"
            `Quick
            test_missing_host_requires_migration
        ] )
    ; ( "plan"
      , [ Alcotest.test_case "native build layout" `Quick test_command_plans
        ; Alcotest.test_case "fixed iPhoneOS switch" `Quick test_fixed_iphoneos_switch
        ] )
    ; ( "sdk-manifest"
      , [ Alcotest.test_case "contract" `Quick test_sdk_manifest_contract
        ; Alcotest.test_case
            "canonical fingerprint"
            `Quick
            test_sdk_manifest_fingerprint_is_canonical
        ; Alcotest.test_case
            "framework source drift"
            `Quick
            test_sdk_rejects_framework_source_drift
        ; Alcotest.test_case
            "missing framework source identity"
            `Quick
            test_sdk_rejects_unadvertised_framework_source_identity
        ; Alcotest.test_case "read-only preflight" `Quick test_sdk_preflight_is_read_only
        ; Alcotest.test_case
            "reachable application lock subset"
            `Quick
            test_sdk_validates_only_reachable_application_lock_subset
        ; Alcotest.test_case
            "missing switch"
            `Quick
            test_sdk_preflight_reports_missing_switch
        ] )
    ; ( "toolchain"
      , [ Alcotest.test_case
            "versioned repository contract"
            `Quick
            test_ios_opam_repository_release_contract
        ; Alcotest.test_case
            "show and verify"
            `Quick
            test_toolchain_show_and_verify_are_read_only
        ; Alcotest.test_case
            "fixed remove"
            `Quick
            test_toolchain_remove_uses_only_fixed_switch
        ; Alcotest.test_case
            "locked install"
            `Quick
            test_toolchain_install_uses_locked_repository_and_exact_sdk
        ; Alcotest.test_case
            "install rejection"
            `Quick
            test_toolchain_install_rejects_existing_switch_and_tampered_repository
        ] )
    ; "features", [ Alcotest.test_case "target closure" `Quick test_feature_validation ]
    ; "cache", [ Alcotest.test_case "deterministic keys" `Quick test_cache_keys ]
    ; ( "host"
      , [ Alcotest.test_case "generated host" `Quick test_generated_host
        ; Alcotest.test_case
            "generated managed adapter host"
            `Quick
            test_generated_managed_adapter_host
        ; Alcotest.test_case
            "mixed-ownership pubspec"
            `Quick
            test_mixed_ownership_pubspec_sync
        ; Alcotest.test_case
            "pubspec marker validation"
            `Quick
            test_pubspec_marker_validation
        ; Alcotest.test_case "CRLF pubspec" `Quick test_pubspec_sync_preserves_crlf
        ; Alcotest.test_case
            "custom source ownership"
            `Quick
            test_custom_host_sync_preserves_consumer_source
        ; Alcotest.test_case
            "managed edit rejection"
            `Quick
            test_managed_host_rejects_edited_generated_source
        ; Alcotest.test_case
            "scoped artifact profile"
            `Quick
            test_host_scopes_artifact_profile_to_flutter_invocation
        ] )
    ; ( "ios-host"
      , [ Alcotest.test_case "privacy manifest" `Quick test_ios_privacy_manifest ] )
    ; ( "init"
      , [ Alcotest.test_case "preserves source" `Quick test_scaffold_preserves_user_source
        ; Alcotest.test_case
            "adopts existing layout"
            `Quick
            test_scaffold_adopts_existing_layout_without_default_app
        ; Alcotest.test_case
            "adoption conflict"
            `Quick
            test_scaffold_adoption_rejects_conflicting_config
        ; Alcotest.test_case
            "application lock"
            `Quick
            test_scaffold_generates_and_preserves_application_lock
        ; Alcotest.test_case
            "generates Dune native aliases"
            `Quick
            test_scaffold_generates_dune_native_aliases
        ; Alcotest.test_case
            "Dune native alias is incremental"
            `Quick
            test_macos_dune_alias_build_is_incremental
        ; Alcotest.test_case
            "quotes Dune native target"
            `Quick
            test_scaffold_quotes_dune_native_target
        ] )
    ; ( "project"
      , [ Alcotest.test_case "find root" `Quick test_project_root_discovery
        ; Alcotest.test_case
            "project lock serialization"
            `Quick
            test_project_lock_serializes_processes
        ] )
    ; ( "clean"
      , [ Alcotest.test_case
            "selected platform"
            `Quick
            test_clean_removes_only_selected_platform
        ; Alcotest.test_case
            "all without symlink traversal"
            `Quick
            test_clean_all_does_not_follow_symlinks
        ] )
    ; ( "sync"
      , [ Alcotest.test_case "check and repair" `Quick test_host_sync_check
        ; Alcotest.test_case
            "consumer dependency preservation"
            `Quick
            test_host_sync_preserves_consumer_dependency_changes
        ; Alcotest.test_case
            "native build only manages Dune aliases"
            `Quick
            test_native_sync_only_manages_dune_aliases
        ; Alcotest.test_case
            "invalid alias contract stops before tools"
            `Quick
            test_native_build_rejects_invalid_alias_contract_before_external_tools
        ; Alcotest.test_case
            "project-local native builds"
            `Quick
            test_native_builds_use_project_local_dune_workspaces
        ; Alcotest.test_case
            "committed application lock"
            `Quick
            test_iphoneos_build_requires_committed_application_lock
        ; Alcotest.test_case
            "unchanged native outputs"
            `Quick
            test_unchanged_native_build_preserves_outputs
        ; Alcotest.test_case
            "macOS platform settings"
            `Quick
            test_macos_host_settings_sync
        ; Alcotest.test_case
            "managed adapter preservation"
            `Quick
            test_managed_adapter_sync_preserves_application_code
        ] )
    ; ( "flutter"
      , [ Alcotest.test_case "command plans" `Quick test_flutter_plans
        ; Alcotest.test_case
            "runtime icons in builds"
            `Quick
            test_flutter_builds_preserve_runtime_material_icons
        ; Alcotest.test_case
            "runs omit build-only icon flags"
            `Quick
            test_flutter_runs_omit_build_only_icon_flags
        ; Alcotest.test_case
            "run argument forwarding"
            `Quick
            test_flutter_run_preserves_forwarded_arguments
        ; Alcotest.test_case
            "icon-safe argument forwarding"
            `Quick
            test_flutter_icon_protection_preserves_forwarded_arguments
        ; Alcotest.test_case
            "icon flag normalization"
            `Quick
            test_flutter_icon_protection_normalizes_conflicting_arguments
        ; Alcotest.test_case
            "Debug and generated host"
            `Quick
            test_flutter_debug_and_generated_host_remain_unchanged
        ; Alcotest.test_case
            "incremental pub get"
            `Quick
            test_flutter_pub_get_runs_only_when_dependency_inputs_change
        ; Alcotest.test_case
            "missing project pubspec"
            `Quick
            test_flutter_pub_get_requires_project_pubspec
        ; Alcotest.test_case "iOS bundle paths" `Quick test_ios_app_bundle_paths
        ; Alcotest.test_case "iOS device commands" `Quick test_ios_device_command_plans
        ] )
    ; ( "exec"
      , [ Alcotest.test_case
            "build, inject, and preserve argv"
            `Quick
            test_exec_builds_injects_and_runs_command_verbatim
        ; Alcotest.test_case
            "child failure status"
            `Quick
            test_exec_preserves_child_failure_status_and_restores_pubspec
        ; Alcotest.test_case
            "interrupt cleanup"
            `Quick
            test_exec_forwards_interrupt_and_restores_pubspec
        ; Alcotest.test_case
            "native build failure"
            `Quick
            test_exec_stops_before_command_when_native_build_fails
        ; Alcotest.test_case "empty command" `Quick test_exec_rejects_an_empty_command
        ] )
    ; ( "ios-device-run"
      , [ Alcotest.test_case "release" `Quick test_ios_release_device_run
        ; Alcotest.test_case "profile" `Quick test_ios_profile_device_run
        ; Alcotest.test_case
            "missing bundle"
            `Quick
            test_ios_device_run_reports_missing_bundle
        ; Alcotest.test_case
            "Flutter failure"
            `Quick
            test_ios_device_run_propagates_flutter_failure
        ; Alcotest.test_case
            "install failure"
            `Quick
            test_ios_device_run_propagates_install_failure
        ; Alcotest.test_case
            "empty bundle identifier"
            `Quick
            test_ios_device_run_rejects_empty_bundle_identifier
        ] )
    ; ( "artifact"
      , [ Alcotest.test_case "layout" `Quick test_artifact_layout
        ; Alcotest.test_case
            "macOS staging contract"
            `Quick
            test_macos_artifact_staging_contract
        ; Alcotest.test_case
            "macOS network static GMP"
            `Quick
            test_macos_network_artifact_embeds_static_gmp
        ] )
    ; ( "dune-closure"
      , [ Alcotest.test_case "local app" `Quick test_dune_closure_follows_local_app
        ; Alcotest.test_case
            "arbitrary local library"
            `Quick
            test_dune_closure_follows_arbitrary_local_library
        ; Alcotest.test_case
            "local component exclusion"
            `Quick
            test_dune_closure_excludes_local_component_roots
        ; Alcotest.test_case
            "transitive local chain"
            `Quick
            test_dune_closure_follows_transitive_local_chain
        ; Alcotest.test_case
            "unreachable stanzas"
            `Quick
            test_dune_closure_ignores_unreachable_stanzas
        ; Alcotest.test_case
            "direct and indirect dependencies"
            `Quick
            test_dune_closure_combines_direct_and_indirect_external_dependencies
        ; Alcotest.test_case
            "PPX-only stanzas"
            `Quick
            test_dune_closure_keeps_ppx_only_stanzas_host_only
        ; Alcotest.test_case
            "missing local stanza"
            `Quick
            test_dune_closure_reports_missing_local_stanza
        ; Alcotest.test_case
            "selected iOS context"
            `Quick
            test_dune_closure_accepts_selected_ios_context
        ; Alcotest.test_case
            "invalid semantic output"
            `Quick
            test_dune_closure_rejects_invalid_semantic_output
        ; Alcotest.test_case
            "deterministic output"
            `Quick
            test_dune_closure_output_is_deterministic
        ] )
    ]
;;
