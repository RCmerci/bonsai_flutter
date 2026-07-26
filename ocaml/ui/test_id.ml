type t = string

let string value =
  if String.length value = 0 then invalid_arg "Test_id.string: value must not be empty";
  value
;;

let equal = String.equal
let to_string t = t
