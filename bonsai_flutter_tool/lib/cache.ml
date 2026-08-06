let application_key ~config ~target ~profile =
  let features =
    config.Config.features |> List.map Config.Feature.to_string |> String.concat ","
  in
  let canonical =
    String.concat
      "\000"
      [ "bonsai-flutter-application-cache-v1"
      ; config.name
      ; config.flutter_root
      ; config.native_target
      ; features
      ; Plan.target_name target
      ; Plan.profile_name profile
      ; config.macos.minimum_version
      ; config.ios.minimum_version
      ; String.concat "," config.ios.architectures
      ]
  in
  Digestif.SHA256.(to_hex (digest_string canonical))
;;
