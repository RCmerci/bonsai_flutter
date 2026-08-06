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
  let minimum_version =
    match target with
    | Macos -> config.macos.minimum_version
    | Iphoneos -> config.ios.minimum_version
  in
  { program = "dune"
  ; arguments
  ; working_directory = project_root
  ; environment =
      [ "BONSAI_FLUTTER_EMBED_OCAML", "enabled"
      ; "BONSAI_FLUTTER_TARGET", target_name target
      ; "BONSAI_FLUTTER_MINIMUM_VERSION", minimum_version
      ]
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
