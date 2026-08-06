open Bonsai_flutter_tool

let valid_config =
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
  Feature.validate_packages ~target:Plan.Iphoneos ~features:core [ "unknown-package" ]
  |> check_error_contains "not available in the iPhoneOS SDK"
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
    (Sys.file_exists (Filename.concat app_dir "native_embed.ml"))
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

let () =
  Alcotest.run
    "bonsai_flutter_tool"
    [ ( "config"
      , [ Alcotest.test_case "valid" `Quick test_parse_valid_config
        ; Alcotest.test_case "invalid" `Quick test_invalid_configs
        ] )
    ; "plan", [ Alcotest.test_case "stable commands" `Quick test_command_plans ]
    ; "features", [ Alcotest.test_case "target closure" `Quick test_feature_validation ]
    ; "cache", [ Alcotest.test_case "deterministic keys" `Quick test_cache_keys ]
    ; "host", [ Alcotest.test_case "generated host" `Quick test_generated_host ]
    ; ( "ios-host"
      , [ Alcotest.test_case "privacy manifest" `Quick test_ios_privacy_manifest ] )
    ; ( "init"
      , [ Alcotest.test_case "preserves source" `Quick test_scaffold_preserves_user_source
        ] )
    ; "project", [ Alcotest.test_case "find root" `Quick test_project_root_discovery ]
    ; "sync", [ Alcotest.test_case "check and repair" `Quick test_host_sync_check ]
    ; "flutter", [ Alcotest.test_case "command plans" `Quick test_flutter_plans ]
    ; "artifact", [ Alcotest.test_case "layout" `Quick test_artifact_layout ]
    ]
;;
