(** Material widgets represented by renderer-independent logical nodes. *)

val scaffold : ?key:Key.t -> ?app_bar:Widget.t -> body:Widget.t -> unit -> Widget.t
val app_bar : ?key:Key.t -> ?center_title:bool -> title:Widget.t -> unit -> Widget.t

val elevated_button
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?autofocus:bool
  -> on_press:Event.Handler.t
  -> child:Widget.t
  -> unit
  -> Widget.t

val text_button
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?autofocus:bool
  -> on_press:Event.Handler.t
  -> child:Widget.t
  -> unit
  -> Widget.t

val icon_button
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?autofocus:bool
  -> on_press:Event.Handler.t
  -> icon:Widget.t
  -> unit
  -> Widget.t

val checkbox
  :  ?key:Key.t
  -> ?enabled:bool
  -> value:bool
  -> on_changed:Event.Handler.t
  -> unit
  -> Widget.t

val switch
  :  ?key:Key.t
  -> ?enabled:bool
  -> value:bool
  -> on_changed:Event.Handler.t
  -> unit
  -> Widget.t

val text_field
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?read_only:bool
  -> ?obscure_text:bool
  -> ?keyboard_type:Text_editing.keyboard_type
  -> ?input_action:Text_editing.input_action
  -> ?autofocus:bool
  -> ?max_utf8_bytes:int
  -> session_id:Bonsai_flutter_spec.Id.Text_input.session_id
  -> document_revision:Bonsai_flutter_spec.Id.Text_input.document_revision
  -> accepted_local_revision:Bonsai_flutter_spec.Id.Text_input.local_revision
  -> update_mode:Text_editing.update_mode
  -> value:Text_editing.Value.t
  -> on_edit:Event.Handler.t
  -> on_submit:Event.Handler.t
  -> on_focus_changed:Event.Handler.t
  -> ?on_limit_reached:Event.Handler.t
  -> unit
  -> Widget.t

val list_tile
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?selected:bool
  -> ?subtitle:Widget.t
  -> ?leading:Widget.t
  -> ?trailing:Widget.t
  -> on_press:Event.Handler.t
  -> title:Widget.t
  -> unit
  -> Widget.t

val divider : ?key:Key.t -> ?thickness:float -> unit -> Widget.t
val card : ?key:Key.t -> ?elevation:float -> Widget.t -> Widget.t
val dialog : ?key:Key.t -> ?barrier_dismissible:bool -> Widget.t -> Widget.t
val circular_progress_indicator : ?key:Key.t -> ?value:float -> unit -> Widget.t
