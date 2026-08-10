type target =
  | Macos
  | Iphoneos

type profile =
  | Debug
  | Profile
  | Release

type action =
  | Run
  | Build

type platform =
  | Macos_platform
  | Ios_platform

type command =
  { program : string
  ; arguments : string list
  ; working_directory : string
  ; environment : (string * string) list
  }

type native_build =
  { command : command
  ; build_directory : string
  ; source_object : string
  ; staged_object : string
  ; manifest : string
  ; log : string
  ; lock : string
  }

let iphoneos_switch = "bonsai-flutter-ios"

let target_name = function
  | Macos -> "macos"
  | Iphoneos -> "iphoneos"
;;

let profile_name = function
  | Debug -> "debug"
  | Profile -> "profile"
  | Release -> "release"
;;

let ios_configuration_name = function
  | Debug -> "Debug"
  | Profile -> "Profile"
  | Release -> "Release"
;;

let ios_app_bundle ~project_root ~config ~profile =
  Filename.concat
    (Filename.concat project_root config.Config.flutter_root)
    (Printf.sprintf "build/ios/%s-iphoneos/Runner.app" (ios_configuration_name profile))
;;

let ios_bundle_identifier ~project_root ~app_bundle =
  { program = "plutil"
  ; arguments =
      [ "-extract"
      ; "CFBundleIdentifier"
      ; "raw"
      ; "-o"
      ; "-"
      ; Filename.concat app_bundle "Info.plist"
      ]
  ; working_directory = project_root
  ; environment = []
  }
;;

let ios_device_install ~project_root ~device ~app_bundle =
  { program = "xcrun"
  ; arguments =
      [ "devicectl"; "device"; "install"; "app"; "--device"; device; app_bundle ]
  ; working_directory = project_root
  ; environment = []
  }
;;

let ios_device_launch ~project_root ~device ~bundle_identifier =
  { program = "xcrun"
  ; arguments =
      [ "devicectl"
      ; "device"
      ; "process"
      ; "launch"
      ; "--device"
      ; device
      ; "--terminate-existing"
      ; bundle_identifier
      ]
  ; working_directory = project_root
  ; environment = []
  }
;;

let valid_path_component value =
  value <> ""
  && value <> "."
  && value <> ".."
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' -> true
         | _ -> false)
       value
;;

let only_architecture = function
  | [ architecture ] -> architecture
  | _ -> invalid_arg "validated platform must contain exactly one architecture"
;;

let native_build
      ~project_root
      ~(config : Config.t)
      ~target
      ~profile
      ~toolchain_fingerprint
      ~apple_sdk_root
      ~apple_sdk_version
  =
  if Filename.is_relative project_root
  then Error "The project root must be absolute"
  else if not (valid_path_component toolchain_fingerprint)
  then Error (Printf.sprintf "Invalid toolchain fingerprint: %s" toolchain_fingerprint)
  else (
    let platform, context, alias, architecture, deployment_environment =
      match target with
      | Macos ->
        ( "macos"
        , "default"
        , "bonsai-flutter-macos"
        , only_architecture config.macos.architectures
        , [ "MACOSX_DEPLOYMENT_TARGET", config.macos.minimum_version ] )
      | Iphoneos ->
        ( "iphoneos"
        , "default.ios"
        , "bonsai-flutter-ios"
        , only_architecture config.ios.architectures
        , [ "VER", config.ios.minimum_version ] )
    in
    let profile_name = profile_name profile in
    let build_directory =
      Filename.concat
        project_root
        (Printf.sprintf
           "_build/bonsai-flutter/dune/%s/%s/%s"
           platform
           toolchain_fingerprint
           profile_name)
    in
    let native_directory = Filename.dirname config.native_target in
    let qualified_alias =
      if native_directory = "."
      then "@" ^ alias
      else Printf.sprintf "@%s/%s" native_directory alias
    in
    let dune_arguments =
      [ "dune"
      ; "build"
      ; "--root=" ^ project_root
      ; "--build-dir=" ^ build_directory
      ; "--profile=" ^ profile_name
      ]
      @ (match target with
         | Macos -> []
         | Iphoneos -> [ "-x"; "ios" ])
      @ [ qualified_alias ]
    in
    let arguments =
      match target with
      | Macos -> [ "exec"; "--" ] @ dune_arguments
      | Iphoneos -> [ "exec"; "--switch=" ^ iphoneos_switch; "--" ] @ dune_arguments
    in
    let sdk_environment =
      match target, apple_sdk_version with
      | Macos, _ -> Ok []
      | Iphoneos, Some version -> Ok [ "SDK", version ]
      | Iphoneos, None -> Error "The iPhoneOS SDK version is required"
    in
    match sdk_environment with
    | Error _ as error -> error
    | Ok sdk_environment ->
      let artifact_platform =
        match target with
        | Macos -> "macos/" ^ architecture
        | Iphoneos -> "ios/iphoneos/" ^ architecture
      in
      let state_platform =
        match target with
        | Macos -> "macos"
        | Iphoneos -> "iphoneos"
      in
      let build_root = Filename.concat project_root "_build/bonsai-flutter" in
      Ok
        { command =
            { program = "opam"
            ; arguments
            ; working_directory = project_root
            ; environment =
                [ "BONSAI_FLUTTER_EMBED_OCAML", "enabled"
                ; "BONSAI_FLUTTER_APPLE_SDK_ROOT", apple_sdk_root
                ; "BUILD_PATH_PREFIX_MAP", project_root ^ "=."
                ]
                @ deployment_environment
                @ sdk_environment
            }
        ; build_directory
        ; source_object =
            Filename.concat build_directory (Filename.concat context config.native_target)
        ; staged_object =
            Filename.concat
              build_root
              (Printf.sprintf
                 "artifacts/%s/%s/%s"
                 artifact_platform
                 profile_name
                 (Filename.basename config.native_target))
        ; manifest =
            Filename.concat
              build_root
              (Printf.sprintf
                 "state/%s/%s/build-manifest.sexp"
                 state_platform
                 profile_name)
        ; log =
            Filename.concat
              build_root
              (Printf.sprintf "logs/%s/%s.log" state_platform profile_name)
        ; lock =
            Filename.concat
              build_root
              (Printf.sprintf "locks/%s/%s.lock" state_platform profile_name)
        })
;;

let preserve_runtime_material_icons action profile forwarded =
  match action, profile with
  | Build, (Profile | Release) ->
    "--no-tree-shake-icons"
    :: List.filter
         (fun argument ->
            argument <> "--no-tree-shake-icons" && argument <> "--tree-shake-icons")
         forwarded
  | Run, _ | Build, Debug -> forwarded
;;

let flutter
      ~project_root
      ~config
      ~action
      ~platform
      ~profile
      ~device
      ~no_codesign
      ~forwarded
  =
  let profile_flag = "--" ^ profile_name profile in
  let forwarded = preserve_runtime_material_icons action profile forwarded in
  let arguments =
    match action, platform with
    | Run, Macos_platform ->
      [ "run"; "-d"; Option.value ~default:"macos" device ]
      @ (match profile with
         | Debug -> []
         | Profile | Release -> [ profile_flag ])
      @ forwarded
    | Run, Ios_platform ->
      [ "run"; "-d"; Option.value ~default:"ios" device ]
      @ (match profile with
         | Debug -> []
         | Profile | Release -> [ profile_flag ])
      @ forwarded
    | Build, Macos_platform -> [ "build"; "macos"; profile_flag ] @ forwarded
    | Build, Ios_platform ->
      [ "build"; "ios"; profile_flag ]
      @ (if no_codesign then [ "--no-codesign" ] else [])
      @ forwarded
  in
  { program = "flutter"
  ; arguments
  ; working_directory = Filename.concat project_root config.Config.flutter_root
  ; environment = []
  }
;;
