open Bonsai_flutter_tool

let valid_config =
  {|
(lang 1)

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
  (minimum_version 13.0))
 (ios
  (minimum_version 15.0)
  (architectures arm64)))
|}
;;

let managed_adapter_config =
  {|
(lang 1)

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
  (minimum_version 13.0))
 (ios
  (minimum_version 15.0)
  (architectures arm64)))
|}
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
  Alcotest.(check string) "macOS minimum" "13.0" config.macos.minimum_version;
  Alcotest.(check string) "iOS minimum" "15.0" config.ios.minimum_version;
  Alcotest.(check (list string)) "iOS architectures" [ "arm64" ] config.ios.architectures
;;

let test_invalid_configs () =
  [ ( "unsupported schema"
    , replace_once valid_config ~pattern:"(lang 1)" ~replacement:"(lang 2)"
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
  ; ( "unsupported architecture"
    , replace_once
        valid_config
        ~pattern:"(architectures arm64)"
        ~replacement:"(architectures x86_64)"
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

let test_missing_host_requires_migration () =
  let without_host =
    {|
(lang 1)

(app
 (name journal)
 (flutter_root flutter)
 (native_target app/native_embed.exe.o)
 (features network sqlite)
 (macos
  (minimum_version 13.0))
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
    Plan.build_native
      ~project_root:"/work/journal"
      ~config
      ~target:Plan.Macos
      ~profile:Plan.Debug
  in
  Alcotest.(check string) "macOS executable" "dune" macos.program;
  Alcotest.(check (list string))
    "macOS args"
    [ "build"; "app/native_embed.exe.o" ]
    macos.arguments;
  Alcotest.(check (pair string string))
    "embed env"
    ("BONSAI_FLUTTER_EMBED_OCAML", "enabled")
    (List.assoc "BONSAI_FLUTTER_EMBED_OCAML" macos.environment
     |> fun value -> "BONSAI_FLUTTER_EMBED_OCAML", value);
  let ios =
    Plan.build_native
      ~project_root:"/work/journal"
      ~config
      ~target:Plan.Iphoneos
      ~profile:Plan.Release
  in
  Alcotest.(check string) "iOS executable" "dune" ios.program;
  Alcotest.(check bool) "iOS cross context" true (List.mem "-x" ios.arguments);
  Alcotest.(check bool)
    "release profile"
    true
    (List.mem "--profile=release" ios.arguments)
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
    (contains
       pubspec
       "native_artifact_root: ../_build/bonsai-flutter/native-artifacts/journal/");
  Alcotest.(check bool)
    "renderer dependency"
    true
    (contains pubspec "path: ../.bonsai-flutter/flutter-packages/bonsai_flutter");
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
    "generated Flutter construction test constructs adapter host"
    true
    (contains
       widget_test
       "BonsaiFlutterHost(adapter: application.createBonsaiFlutterHostAdapter())")
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

let test_host_sync_check () =
  let root = Filename.temp_dir "bonsai-flutter-tool" "sync" in
  let config = Config.parse_string valid_config |> get_ok in
  let changed = Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok in
  Alcotest.(check int) "initial generated files" 4 (List.length changed);
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
  let repaired = Host.sync ~project_root:root ~config ~mode:Host.Write |> get_ok in
  Alcotest.(check (list string)) "repairs only drift" [ "flutter/lib/main.dart" ] repaired
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
    [ "build"; "ios"; "--release"; "--no-codesign" ]
    ios.arguments
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
  Alcotest.(check string)
    "macOS source"
    "/work/journal/_build/default/app/native_embed.exe.o"
    (Artifact.source
       ~project_root:"/work/journal"
       ~config
       ~target:Plan.Macos
       ~profile:Plan.Debug);
  Alcotest.(check string)
    "iPhoneOS destination"
    "/work/journal/_build/bonsai-flutter/native-artifacts/journal/ios/iphoneos/arm64/native_embed.exe.o"
    (Artifact.destination
       ~project_root:"/work/journal"
       ~config
       ~target:Plan.Iphoneos
       ~profile:Plan.Release)
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
            "missing host migration"
            `Quick
            test_missing_host_requires_migration
        ] )
    ; "plan", [ Alcotest.test_case "stable commands" `Quick test_command_plans ]
    ; "features", [ Alcotest.test_case "target closure" `Quick test_feature_validation ]
    ; "cache", [ Alcotest.test_case "deterministic keys" `Quick test_cache_keys ]
    ; ( "host"
      , [ Alcotest.test_case "generated host" `Quick test_generated_host
        ; Alcotest.test_case
            "generated managed adapter host"
            `Quick
            test_generated_managed_adapter_host
        ] )
    ; ( "ios-host"
      , [ Alcotest.test_case "privacy manifest" `Quick test_ios_privacy_manifest ] )
    ; ( "init"
      , [ Alcotest.test_case "preserves source" `Quick test_scaffold_preserves_user_source
        ] )
    ; "project", [ Alcotest.test_case "find root" `Quick test_project_root_discovery ]
    ; ( "sync"
      , [ Alcotest.test_case "check and repair" `Quick test_host_sync_check
        ; Alcotest.test_case
            "managed adapter preservation"
            `Quick
            test_managed_adapter_sync_preserves_application_code
        ] )
    ; ( "flutter"
      , [ Alcotest.test_case "command plans" `Quick test_flutter_plans
        ; Alcotest.test_case "iOS bundle paths" `Quick test_ios_app_bundle_paths
        ; Alcotest.test_case "iOS device commands" `Quick test_ios_device_command_plans
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
    ; "artifact", [ Alcotest.test_case "layout" `Quick test_artifact_layout ]
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
