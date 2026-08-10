let project_relative_prefix flutter_root =
  flutter_root
  |> String.split_on_char '/'
  |> List.filter (fun component -> component <> "" && component <> ".")
  |> List.map (fun _ -> "..")
  |> String.concat "/"
;;

let pubspec ?artifact_profile config =
  let prefix = project_relative_prefix config.Config.flutter_root in
  let artifact_profile_define =
    match artifact_profile with
    | None -> ""
    | Some profile -> Printf.sprintf "      native_artifact_profile: %s\n" profile
  in
  let sqlite_define =
    if List.exists (Config.Feature.equal Config.Feature.Sqlite) config.features
    then "      link_system_sqlite3: true\n"
    else ""
  in
  Printf.sprintf
    {|name: bonsai_flutter_%s_host
description: Mechanical Flutter host for the OCaml-owned %s application.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.12.2
  flutter: ">=3.44.0"

hooks:
  user_defines:
    bonsai_flutter_native:
      native_artifact_root: %s/_build/bonsai-flutter/artifacts/
      macos_deployment_target: '%s'
      ios_deployment_target: '%s'
      require_ocaml_backend: true
%s%s
dependencies:
  bonsai_flutter:
    path: %s/.bonsai-flutter/flutter-packages/bonsai_flutter
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_lints: ^6.0.0
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter

flutter:
  uses-material-design: true
|}
    config.name
    config.name
    prefix
    config.macos.minimum_version
    config.ios.minimum_version
    artifact_profile_define
    sqlite_define
    prefix
;;

let strip_lib_prefix path = String.sub path 4 (String.length path - 4)

let dart_single_quoted value =
  let buffer = Buffer.create (String.length value + 2) in
  Buffer.add_char buffer '\'';
  String.iter
    (function
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\'' -> Buffer.add_string buffer "\\'"
      | '$' -> Buffer.add_string buffer "\\$"
      | character -> Buffer.add_char buffer character)
    value;
  Buffer.add_char buffer '\'';
  Buffer.contents buffer
;;

let managed_main_dart config adapter =
  let launch_policy =
    match adapter.Config.launch_policy with
    | Config.Fresh -> "fresh"
    | Config.Replace_existing -> "replaceExisting"
  in
  Printf.sprintf
    {|import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

import '%s' as application;

void main() {
  final adapter = application.createBonsaiFlutterHostAdapter();
  runApp(BonsaiFlutterHost(adapter: adapter));
}

final class BonsaiFlutterHost extends StatefulWidget {
  const BonsaiFlutterHost({required this.adapter, super.key});

  final BonsaiFlutterHostAdapter adapter;

  @override
  State<BonsaiFlutterHost> createState() => _BonsaiFlutterHostState();
}

final class _PreparedRuntime {
  const _PreparedRuntime({
    required this.runtimeConfig,
    required this.applicationPlatform,
  });

  final Uint8List runtimeConfig;
  final BonsaiFlutterApplicationPlatform? applicationPlatform;
}

final class _BonsaiFlutterHostState extends State<BonsaiFlutterHost> {
  late Future<_PreparedRuntime> _preparedRuntime;

  @override
  void initState() {
    super.initState();
    _preparedRuntime = _prepareRuntime();
  }

  @override
  void didUpdateWidget(covariant BonsaiFlutterHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.adapter, oldWidget.adapter)) {
      _preparedRuntime = _prepareRuntime();
    }
  }

  Future<_PreparedRuntime> _prepareRuntime() async {
    final applicationPayload = await widget.adapter.createApplicationPayload();
    final applicationPlatform = widget.adapter.createApplicationPlatform();
    return _PreparedRuntime(
      runtimeConfig: RuntimeBootstrapConfig(
        entrypoint: %s,
        launchPolicy: RuntimeLaunchPolicy.%s,
        applicationPayload: applicationPayload,
      ).encode(),
      applicationPlatform: applicationPlatform,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_PreparedRuntime>(
    future: _preparedRuntime,
    builder: (context, snapshot) {
      final prepared = snapshot.data;
      final Widget home;
      if (snapshot.error case final error?) {
        home = Center(child: Text('Unable to prepare application: $error'));
      } else if (prepared == null) {
        home = const Center(child: CircularProgressIndicator());
      } else {
        home = BonsaiFlutterRoot(
          config: prepared.runtimeConfig,
          applicationPlatform: prepared.applicationPlatform,
        );
      }
      return widget.adapter.buildHost(
        context: context,
        child: MaterialApp(title: %s, home: home),
      );
    },
  );
}
|}
    (strip_lib_prefix adapter.adapter)
    (dart_single_quoted adapter.entrypoint)
    launch_policy
    (dart_single_quoted config.Config.name)
;;

let main_dart config = managed_main_dart config config.Config.host

let privacy_manifest =
  {|<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>C617.1</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategorySystemBootTime</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>35F9.1</string>
			</array>
		</dict>
	</array>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyTracking</key>
	<false/>
</dict>
</plist>
|}
;;

let managed_host_test config adapter =
  Printf.sprintf
    {|import 'package:bonsai_flutter_%s_host/%s' as application;
import 'package:bonsai_flutter_%s_host/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed host can be constructed', () {
    expect(
      BonsaiFlutterHost(adapter: application.createBonsaiFlutterHostAdapter()),
      isNotNull,
    );
  });
}
|}
    config.Config.name
    (strip_lib_prefix adapter.Config.adapter)
    config.name
;;

let host_test config = managed_host_test config config.Config.host

let macos_xcconfig config =
  Printf.sprintf
    "MACOSX_DEPLOYMENT_TARGET = %s\nARCHS = %s\n"
    config.Config.macos.minimum_version
    (String.concat " " config.macos.architectures)
;;

let render ~config =
  [ Filename.concat config.Config.flutter_root "pubspec.yaml", pubspec config
  ; Filename.concat config.flutter_root "lib/main.dart", main_dart config
  ; ( Filename.concat config.flutter_root "ios/Runner/PrivacyInfo.xcprivacy"
    , privacy_manifest )
  ; Filename.concat config.flutter_root "test/widget_test.dart", host_test config
  ; ( Filename.concat config.flutter_root "macos/Runner/Configs/BonsaiFlutter.xcconfig"
    , macos_xcconfig config )
  ]
;;

let find_substring contents pattern =
  let pattern_length = String.length pattern in
  let rec search index =
    if index + pattern_length > String.length contents
    then None
    else if String.sub contents index pattern_length = pattern
    then Some index
    else search (index + 1)
  in
  search 0
;;

let replace_after contents ~anchor ~addition =
  match find_substring contents anchor with
  | None ->
    Error (Printf.sprintf "The generated Xcode project is missing anchor: %s" anchor)
  | Some index ->
    let boundary = index + String.length anchor in
    Ok
      (String.sub contents 0 boundary
       ^ addition
       ^ String.sub contents boundary (String.length contents - boundary))
;;

let patch_ios_project_contents contents =
  if Option.is_some (find_substring contents "BF1000010000000000000001")
  then Ok contents
  else (
    let ( let* ) result f =
      match result with
      | Ok value -> f value
      | Error _ as error -> error
    in
    let* contents =
      replace_after
        contents
        ~anchor:"/* Begin PBXBuildFile section */"
        ~addition:
          "\n\
           \t\tBF1000020000000000000001 /* PrivacyInfo.xcprivacy in Resources */ = {isa \
           = PBXBuildFile; fileRef = BF1000010000000000000001 /* PrivacyInfo.xcprivacy \
           */; };"
    in
    let* contents =
      replace_after
        contents
        ~anchor:"/* Begin PBXFileReference section */"
        ~addition:
          "\n\
           \t\tBF1000010000000000000001 /* PrivacyInfo.xcprivacy */ = {isa = \
           PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; \
           sourceTree = \"<group>\"; };"
    in
    let* contents =
      replace_after
        contents
        ~anchor:"97C147021CF9000F007C117D /* Info.plist */,"
        ~addition:"\n\t\t\t\tBF1000010000000000000001 /* PrivacyInfo.xcprivacy */,"
    in
    replace_after
      contents
      ~anchor:"97C146FC1CF9000F007C117D /* Main.storyboard in Resources */,"
      ~addition:
        "\n\t\t\t\tBF1000020000000000000001 /* PrivacyInfo.xcprivacy in Resources */,")
;;

let managed_macos_include = "#include \"BonsaiFlutter.xcconfig\""

let patch_macos_xcconfig_contents contents =
  if
    contents
    |> String.split_on_char '\n'
    |> List.exists (fun line -> String.equal (String.trim line) managed_macos_include)
  then contents
  else
    contents
    ^ (if String.ends_with ~suffix:"\n" contents then "" else "\n")
    ^ managed_macos_include
    ^ "\n"
;;

let patch_macos_project_contents contents =
  contents
  |> String.split_on_char '\n'
  |> List.filter (fun line ->
    Option.is_none (find_substring line "MACOSX_DEPLOYMENT_TARGET ="))
  |> String.concat "\n"
;;

type sync_mode =
  | Check
  | Write

let read_file path =
  if not (Sys.file_exists path)
  then None
  else (
    let channel = open_in_bin path in
    let contents = really_input_string channel (in_channel_length channel) in
    close_in channel;
    Some contents)
;;

let rec ensure_directory path =
  if path = "" || path = Filename.dirname path || Sys.file_exists path
  then ()
  else (
    ensure_directory (Filename.dirname path);
    Unix.mkdir path 0o755)
;;

let write_atomically path contents =
  ensure_directory (Filename.dirname path);
  let temporary = path ^ ".bonsai-flutter.tmp" in
  let channel = open_out_bin temporary in
  output_string channel contents;
  close_out channel;
  Unix.rename temporary path
;;

let with_artifact_profile ~project_root ~config ~profile f =
  let path = Filename.concat project_root (Filename.concat config.Config.flutter_root "pubspec.yaml") in
  try
    match read_file path with
    | None -> Error (Printf.sprintf "Generated Flutter pubspec is missing: %s" path)
    | Some original ->
      write_atomically path (pubspec ~artifact_profile:profile config);
      Fun.protect ~finally:(fun () -> write_atomically path original) f
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let sync ~project_root ~config ~mode : (string list, string) result =
  try
    let generated_drift =
      render ~config
      |> List.filter_map (fun (relative_path, expected) ->
        let path = Filename.concat project_root relative_path in
        match read_file path with
        | Some actual when String.equal actual expected -> None
        | None | Some _ -> Some (relative_path, path, expected))
    in
    let project_relative =
      Filename.concat config.Config.flutter_root "ios/Runner.xcodeproj/project.pbxproj"
    in
    let project_path = Filename.concat project_root project_relative in
    let project_drift =
      match read_file project_path with
      | None -> Ok []
      | Some contents ->
        (match patch_ios_project_contents contents with
         | Error _ as error -> error
         | Ok patched when String.equal contents patched -> Ok []
         | Ok patched -> Ok [ project_relative, project_path, patched ])
    in
    let macos_config_drift =
      [ "Debug.xcconfig"; "Release.xcconfig"; "AppInfo.xcconfig" ]
      |> List.filter_map (fun filename ->
        let relative_path =
          Filename.concat
            config.Config.flutter_root
            (Filename.concat "macos/Runner/Configs" filename)
        in
        let path = Filename.concat project_root relative_path in
        match read_file path with
        | None -> None
        | Some contents ->
          let patched = patch_macos_xcconfig_contents contents in
          if String.equal contents patched
          then None
          else Some (relative_path, path, patched))
    in
    let macos_project_relative =
      Filename.concat config.Config.flutter_root "macos/Runner.xcodeproj/project.pbxproj"
    in
    let macos_project_path = Filename.concat project_root macos_project_relative in
    let macos_project_drift =
      match read_file macos_project_path with
      | None -> []
      | Some contents ->
        let patched = patch_macos_project_contents contents in
        if String.equal contents patched
        then []
        else [ macos_project_relative, macos_project_path, patched ]
    in
    match project_drift with
    | Error _ as error -> error
    | Ok project_drift ->
      let drift =
        generated_drift @ project_drift @ macos_config_drift @ macos_project_drift
      in
      let changed = List.map (fun (relative, _, _) -> relative) drift in
      (match mode, drift with
       | Check, [] -> Ok []
       | Check, _ ->
         Error
           (Printf.sprintf
              "Generated host is out of date: %s"
              (String.concat ", " changed))
       | Write, _ ->
         List.iter (fun (_, path, contents) -> write_atomically path contents) drift;
         Ok changed)
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;
