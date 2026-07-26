type t =
  | String of string
  | Int64 of int64

let string value = String value
let int value = Int64 (Int64.of_int value)
let int64 value = Int64 value
let compare left right = Stdlib.compare left right
let equal left right = compare left right = 0
let hash value = Hashtbl.hash value

let to_debug_string = function
  | String value -> Printf.sprintf "%S" value
  | Int64 value -> Int64.to_string value
;;
