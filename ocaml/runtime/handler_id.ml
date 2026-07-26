type t = int64

let compare = Int64.compare
let equal = Int64.equal
let to_int64 value = value

module Private = struct
  let of_int64 value =
    if Int64.compare value 0L < 0 then invalid_arg "Handler_id: negative value";
    value
  ;;
end
