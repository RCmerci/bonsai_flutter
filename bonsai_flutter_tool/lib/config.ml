module Feature = struct
  type t =
    | Core
    | Network
    | Sqlite

  let equal left right = left = right

  let to_string = function
    | Core -> "core"
    | Network -> "network"
    | Sqlite -> "sqlite"
  ;;

  let of_string = function
    | "core" -> Ok Core
    | "network" -> Ok Network
    | "sqlite" -> Ok Sqlite
    | value -> Error (Printf.sprintf "Unsupported feature: %s" value)
  ;;
end

type platform = { minimum_version : string }

type ios =
  { minimum_version : string
  ; architectures : string list
  }

type launch_policy =
  | Fresh
  | Replace_existing

type managed_adapter =
  { adapter : string
  ; entrypoint : string
  ; launch_policy : launch_policy
  }

type t =
  { name : string
  ; flutter_root : string
  ; native_target : string
  ; features : Feature.t list
  ; host : managed_adapter
  ; macos : platform
  ; ios : ios
  }

exception Invalid of string

let invalid format = Printf.ksprintf (fun message -> raise (Invalid message)) format

let atom = function
  | Sexplib.Sexp.Atom value -> value
  | sexp -> invalid "Expected an atom, found %s" (Sexplib.Sexp.to_string_hum sexp)
;;

let named_fields ~scope fields =
  let add acc = function
    | Sexplib.Sexp.List (Sexplib.Sexp.Atom name :: values) ->
      if List.mem_assoc name acc then invalid "Duplicate %s field: %s" scope name;
      (name, values) :: acc
    | sexp -> invalid "Invalid %s field: %s" scope (Sexplib.Sexp.to_string_hum sexp)
  in
  List.fold_left add [] fields |> List.rev
;;

let take_field ~scope ~name fields =
  match List.assoc_opt name fields with
  | Some values -> values
  | None -> invalid "Missing %s field: %s" scope name
;;

let reject_unknown ~scope ~known fields =
  List.iter
    (fun (name, _) ->
       if not (List.mem name known) then invalid "Unknown %s field: %s" scope name)
    fields
;;

let single_atom ~scope ~name fields =
  match take_field ~scope ~name fields with
  | [ value ] -> atom value
  | _ -> invalid "%s.%s must contain exactly one value" scope name
;;

let valid_version value =
  match String.split_on_char '.' value with
  | [ major; minor ] ->
    let digits part =
      String.length part > 0
      && String.for_all
           (function
             | '0' .. '9' -> true
             | _ -> false)
           part
    in
    digits major && digits minor
  | _ -> false
;;

let validate_relative_path ~field value =
  if not (Filename.is_relative value) then invalid "%s must be a relative path" field;
  if value = "" then invalid "%s must not be empty" field;
  if List.mem ".." (String.split_on_char '/' value)
  then invalid "%s must not contain parent traversal" field
;;

let validate_name value =
  let valid_first = function
    | 'a' .. 'z' -> true
    | _ -> false
  in
  let valid_rest = function
    | 'a' .. 'z' | '0' .. '9' | '_' -> true
    | _ -> false
  in
  if
    String.length value = 0
    || (not (valid_first value.[0]))
    || not (String.for_all valid_rest value)
  then invalid "Invalid application name: %s" value
;;

let validate_host_entrypoint value =
  if value = "" then invalid "host.entrypoint must not be empty";
  if String.length value > 255
  then invalid "host.entrypoint must be at most 255 UTF-8 bytes";
  if not (String.is_valid_utf_8 value) then invalid "host.entrypoint must be valid UTF-8";
  String.iter
    (fun character ->
       if Char.code character < 32 || Char.code character = 127
       then invalid "host.entrypoint must not contain control characters")
    value
;;

let validate_adapter_path value =
  if String.contains value '\\' then invalid "host.adapter must use forward slashes";
  validate_relative_path ~field:"host.adapter" value;
  if not (String.starts_with ~prefix:"lib/" value)
  then invalid "host.adapter must be inside flutter lib";
  if String.equal value "lib/main.dart"
  then invalid "host.adapter must not be the generated host";
  if not (String.ends_with ~suffix:".dart" value)
  then invalid "host.adapter must name a .dart file";
  let valid_component component =
    String.length component > 0
    && (match component.[0] with
        | 'a' .. 'z' -> true
        | _ -> false)
    && String.for_all
         (function
           | 'a' .. 'z' | '0' .. '9' | '_' -> true
           | _ -> false)
         component
  in
  let components = String.split_on_char '/' value in
  let directories, filename =
    match List.rev components with
    | filename :: directories -> List.rev directories, filename
    | [] -> assert false
  in
  let basename = Filename.remove_extension filename in
  if
    not
      (List.for_all valid_component directories
       && valid_component basename
       && String.equal (Filename.extension filename) ".dart")
  then invalid "host.adapter must use lower_snake_case path components"
;;

let parse_host values =
  let scope = "host" in
  let fields = named_fields ~scope values in
  reject_unknown ~scope ~known:[ "mode"; "adapter"; "entrypoint"; "launch_policy" ] fields;
  let mode = single_atom ~scope ~name:"mode" fields in
  if not (String.equal mode "managed_adapter")
  then invalid "Unsupported host mode: %s" mode;
  let adapter = single_atom ~scope ~name:"adapter" fields in
  validate_adapter_path adapter;
  let entrypoint = single_atom ~scope ~name:"entrypoint" fields in
  validate_host_entrypoint entrypoint;
  let launch_policy =
    match single_atom ~scope ~name:"launch_policy" fields with
    | "fresh" -> Fresh
    | "replace_existing" -> Replace_existing
    | value -> invalid "Unsupported host launch policy: %s" value
  in
  { adapter; entrypoint; launch_policy }
;;

let parse_platform ~scope values =
  let fields = named_fields ~scope values in
  reject_unknown ~scope ~known:[ "minimum_version" ] fields;
  let minimum_version = single_atom ~scope ~name:"minimum_version" fields in
  if not (valid_version minimum_version)
  then invalid "%s.minimum_version must be a major.minor version" scope;
  { minimum_version }
;;

let parse_ios values =
  let scope = "ios" in
  let fields = named_fields ~scope values in
  reject_unknown ~scope ~known:[ "minimum_version"; "architectures" ] fields;
  let minimum_version = single_atom ~scope ~name:"minimum_version" fields in
  if not (valid_version minimum_version)
  then invalid "ios.minimum_version must be a major.minor version";
  let architectures = List.map atom (take_field ~scope ~name:"architectures" fields) in
  if architectures = [] then invalid "ios.architectures must not be empty";
  List.iter
    (fun architecture ->
       if architecture <> "arm64"
       then invalid "Unsupported iOS architecture: %s" architecture)
    architectures;
  if
    List.length architectures <> List.length (List.sort_uniq String.compare architectures)
  then invalid "Duplicate iOS architecture";
  { minimum_version; architectures }
;;

let parse_features values =
  let features = List.map (fun value -> Feature.of_string (atom value)) values in
  let features =
    List.map
      (function
        | Ok feature -> feature
        | Error message -> raise (Invalid message))
      features
  in
  if List.exists (Feature.equal Feature.Core) features
  then invalid "The core feature is implicit and must not be listed";
  let names = List.map Feature.to_string features in
  if List.length names <> List.length (List.sort_uniq String.compare names)
  then invalid "Duplicate feature";
  Feature.Core :: features
;;

let parse_app values =
  let scope = "app" in
  let fields = named_fields ~scope values in
  reject_unknown
    ~scope
    ~known:[ "name"; "flutter_root"; "native_target"; "features"; "host"; "macos"; "ios" ]
    fields;
  let name = single_atom ~scope ~name:"name" fields in
  validate_name name;
  let flutter_root = single_atom ~scope ~name:"flutter_root" fields in
  validate_relative_path ~field:"flutter_root" flutter_root;
  let native_target = single_atom ~scope ~name:"native_target" fields in
  validate_relative_path ~field:"native_target" native_target;
  if not (String.ends_with ~suffix:".exe.o" native_target)
  then invalid "native_target must end in .exe.o";
  let features = parse_features (take_field ~scope ~name:"features" fields) in
  let host =
    match List.assoc_opt "host" fields with
    | None -> invalid "app.host is required; configure managed_adapter"
    | Some values -> parse_host values
  in
  let macos = parse_platform ~scope:"macos" (take_field ~scope ~name:"macos" fields) in
  let ios = parse_ios (take_field ~scope ~name:"ios" fields) in
  { name; flutter_root; native_target; features; host; macos; ios }
;;

let parse_string input =
  try
    match Sexplib.Sexp.of_string_many input with
    | [ Sexplib.Sexp.List [ Sexplib.Sexp.Atom "lang"; Sexplib.Sexp.Atom "1" ]
      ; Sexplib.Sexp.List (Sexplib.Sexp.Atom "app" :: values)
      ] -> Ok (parse_app values)
    | Sexplib.Sexp.List [ Sexplib.Sexp.Atom "lang"; Sexplib.Sexp.Atom version ] :: _ ->
      Error (Printf.sprintf "Unsupported schema version: %s" version)
    | _ -> Error "Expected exactly (lang 1) followed by one (app ...) form"
  with
  | Invalid message -> Error message
  | exn ->
    Error
      (Printf.sprintf "Invalid S-expression configuration: %s" (Printexc.to_string exn))
;;

let parse_file path =
  try
    let channel = open_in_bin path in
    let length = in_channel_length channel in
    let input = really_input_string channel length in
    close_in channel;
    parse_string input
  with
  | Sys_error message -> Error message
;;
