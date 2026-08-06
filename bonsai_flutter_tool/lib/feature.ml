let network_packages =
  [ "tls"
  ; "tls-eio"
  ; "ca-certs-nss"
  ; "x509"
  ; "mirage-crypto-rng"
  ; "httpun"
  ; "httpun-eio"
  ; "httpun-ws"
  ; "gluten"
  ; "gluten-eio"
  ; "digestif"
  ; "domain-name"
  ; "ptime"
  ; "uri"
  ; "bigstringaf"
  ; "cstruct"
  ]
;;

let core_packages =
  [ "base"
  ; "bonsai"
  ; "bonsai_flutter"
  ; "core"
  ; "dune"
  ; "eio"
  ; "eio_posix"
  ; "incr_dom"
  ; "mtime"
  ; "ocaml"
  ; "ppx_jane"
  ; "virtual_dom"
  ]
;;

let prohibited = [ "openssl"; "conf-openssl"; "eio-ssl"; "piaf" ]
let has_feature features feature = List.exists (Config.Feature.equal feature) features

let validate_package ~features package =
  if List.mem package prohibited
  then Error (Printf.sprintf "Package %s uses a prohibited TLS backend" package)
  else if List.mem package core_packages
  then Ok ()
  else if List.mem package network_packages
  then
    if has_feature features Config.Feature.Network
    then Ok ()
    else Error (Printf.sprintf "Package %s requires the network feature" package)
  else if package = "sqlite3"
  then
    if has_feature features Config.Feature.Sqlite
    then Ok ()
    else Error "Package sqlite3 requires the sqlite feature"
  else Error (Printf.sprintf "Package %s is not available in the iPhoneOS SDK" package)
;;

let validate_packages ~target ~features packages =
  match target with
  | Plan.Macos -> Ok ()
  | Plan.Iphoneos ->
    List.fold_left
      (fun result package ->
         match result with
         | Error _ -> result
         | Ok () -> validate_package ~features package)
      (Ok ())
      packages
;;
