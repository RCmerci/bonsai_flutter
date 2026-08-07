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

let build_native ~project_root ~config ~target ~profile =
  let arguments =
    match target with
    | Macos -> [ "build"; config.Config.native_target ]
    | Iphoneos ->
      [ "build"
      ; config.native_target
      ; Printf.sprintf "--build-dir=%s" (Filename.concat project_root "_build/iphoneos")
      ; Printf.sprintf "--profile=%s" (profile_name profile)
      ; "-x"
      ; "ios"
      ]
  in
  let platform_environment =
    match target with
    | Macos -> [ "MACOSX_DEPLOYMENT_TARGET", config.macos.minimum_version ]
    | Iphoneos -> []
  in
  { program = "dune"
  ; arguments
  ; working_directory = project_root
  ; environment =
      [ "BONSAI_FLUTTER_EMBED_OCAML", "enabled"
      ; "BONSAI_FLUTTER_TARGET", target_name target
      ]
      @ platform_environment
  }
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
