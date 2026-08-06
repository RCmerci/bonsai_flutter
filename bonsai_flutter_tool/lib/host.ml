let project_relative_prefix flutter_root =
  flutter_root
  |> String.split_on_char '/'
  |> List.filter (fun component -> component <> "" && component <> ".")
  |> List.map (fun _ -> "..")
  |> String.concat "/"
;;

let pubspec config =
  let prefix = project_relative_prefix config.Config.flutter_root in
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
      native_artifact_root: %s/_build/bonsai-flutter/native-artifacts/%s/
      ios_deployment_target: '%s'
      require_ocaml_backend: true
%s
dependencies:
  bonsai_flutter:
    path: %s/.bonsai-flutter/flutter-packages/bonsai_flutter
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_lints: ^6.0.0
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
|}
    config.name
    config.name
    prefix
    config.name
    config.ios.minimum_version
    sqlite_define
    prefix
;;

let main_dart config =
  Printf.sprintf
    {|import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const BonsaiFlutterHost());
}

final class BonsaiFlutterHost extends StatelessWidget {
  const BonsaiFlutterHost({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '%s',
    home: BonsaiFlutterRoot(
      config: Uint8List.fromList(utf8.encode('%s')),
    ),
  );
}
|}
    config.Config.name
    config.name
;;

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

let host_test config =
  Printf.sprintf
    {|import 'package:bonsai_flutter_%s_host/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mechanical host can be constructed', () {
    expect(const BonsaiFlutterHost(), isNotNull);
  });
}
|}
    config.Config.name
;;

let render ~config =
  [ Filename.concat config.Config.flutter_root "pubspec.yaml", pubspec config
  ; Filename.concat config.flutter_root "lib/main.dart", main_dart config
  ; ( Filename.concat config.flutter_root "ios/Runner/PrivacyInfo.xcprivacy"
    , privacy_manifest )
  ; Filename.concat config.flutter_root "test/widget_test.dart", host_test config
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
    match project_drift with
    | Error _ as error -> error
    | Ok project_drift ->
      let drift = generated_drift @ project_drift in
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
