module Runtime = Bonsai_flutter_runtime
module Ui = Bonsai_flutter_ui

type t =
  | Test_id of Ui.Test_id.t
  | Key of Ui.Key.t
  | Role of string
  | Visible_text of string
  | Semantics_label of string
  | Kind of string

let normalized value = String.lowercase_ascii value
let test_id value = Test_id (Ui.Test_id.string value)
let key value = Key value
let role value = Role (normalized value)
let visible_text value = Visible_text value
let semantics_label value = Semantics_label value
let kind value = Kind (normalized value)

let kind_name node =
  Ui.Widget.Private.Kind.to_string node.Runtime.Mounted_tree.Snapshot.kind |> normalized
;;

let node_role node =
  match node.Runtime.Mounted_tree.Snapshot.kind, node.props with
  | Ui.Widget.Private.Kind.Button, _ -> Some "button"
  | Material_checkbox, _ -> Some "checkbox"
  | Text_input, _ -> Some "text_field"
  | Semantics, Semantics_props { role; _ } -> Some (Ui.Semantics.Role.to_string role)
  | _ -> None
;;

let matches query node =
  match query with
  | Test_id test_id ->
    (match node.Runtime.Mounted_tree.Snapshot.test_id with
     | Some candidate -> Ui.Test_id.equal test_id candidate
     | None -> false)
  | Key key ->
    (match node.Runtime.Mounted_tree.Snapshot.key with
     | Some candidate -> Ui.Key.equal key candidate
     | None -> false)
  | Role role ->
    (match node_role node with
     | Some candidate -> String.equal role candidate
     | None -> false)
  | Visible_text text ->
    (match node.Runtime.Mounted_tree.Snapshot.props with
     | Ui.Widget.Private.Text_props { value; _ } -> String.equal value text
     | _ -> false)
  | Semantics_label label ->
    (match node.Runtime.Mounted_tree.Snapshot.props with
     | Ui.Widget.Private.Semantics_props { label = Some value; _ } ->
       String.equal value label
     | _ -> false)
  | Kind expected -> String.equal expected (kind_name node)
;;

module Private = struct
  let matches = matches
end
