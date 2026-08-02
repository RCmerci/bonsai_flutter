module ID = Bonsai_flutter_spec.Id

let quoted value = Printf.sprintf "%S" value

let write_widget output widget =
  let view = Widget.Private.view widget in
  Buffer.add_string output (Widget.Private.Kind.to_string view.kind);
  (match view.key with
   | None -> ()
   | Some key ->
     Buffer.add_string output " key=";
     Buffer.add_string output (Key.to_debug_string key));
  (match view.test_id with
   | None -> ()
   | Some test_id ->
     Buffer.add_string output " test_id=";
     Buffer.add_string output (Test_id.to_string test_id));
  (match view.props with
   | Widget.Private.Text_props { value; _ } ->
     Buffer.add_char output ' ';
     Buffer.add_string output (quoted value)
   | Native_widget_props { kind_id; version; _ } ->
     Printf.bprintf
       output
       " native_kind=%d version=%d"
       (ID.Native_widget.Kind_id.to_int kind_id)
       version
   | _ -> ());
  if Array.length view.event_bindings > 0
  then (
    Buffer.add_string output " events=[";
    Array.iteri
      (fun index binding ->
         if index > 0 then Buffer.add_string output ",";
         Buffer.add_string output (Event.Tag.to_string binding.Widget.Private.tag))
      view.event_bindings;
    Buffer.add_char output ']')
;;

let dump_widget widget =
  let output = Buffer.create 64 in
  write_widget output widget;
  Buffer.contents output
;;

let dump_tree root =
  let output = Buffer.create 256 in
  let rec write depth widget =
    let view = Widget.Private.view widget in
    if Buffer.length output > 0 then Buffer.add_char output '\n';
    Buffer.add_string output (String.make (depth * 2) ' ');
    write_widget output widget;
    Array.iter (fun child -> write (depth + 1) child.Widget.Private.widget) view.children
  in
  write 0 root;
  Buffer.contents output
;;
