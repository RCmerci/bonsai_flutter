(** Material widgets represented by renderer-independent logical nodes. *)

type floating_action_button_location =
  | Start_float
  | Center_float
  | End_float
  | Start_docked
  | Center_docked
  | End_docked

val scaffold
  :  ?key:Key.t
  -> ?app_bar:Widget.t
  -> ?floating_action_button:Widget.t
  -> ?floating_action_button_location:floating_action_button_location
  -> ?bottom_navigation_bar:Widget.t
  -> ?bottom_sheet:Widget.t
  -> body:Widget.Body.t
  -> unit
  -> Widget.t

val app_bar : ?key:Key.t -> ?center_title:bool -> title:Widget.t -> unit -> Widget.t

val elevated_button
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?autofocus:bool
  -> on_press:Event.Handler.t
  -> child:Widget.t
  -> unit
  -> Widget.t

val filled_button
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?autofocus:bool
  -> on_press:Event.Handler.t
  -> child:Widget.t
  -> unit
  -> Widget.t

val filled_tonal_button
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?autofocus:bool
  -> on_press:Event.Handler.t
  -> child:Widget.t
  -> unit
  -> Widget.t

val outlined_button
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

module Floating_action_button : sig
  type size =
    | Small
    | Standard
    | Large

  val icon
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?autofocus:bool
    -> ?size:size
    -> on_press:Event.Handler.t
    -> icon:Widget.t
    -> unit
    -> Widget.t

  val extended
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?autofocus:bool
    -> ?icon:Widget.t
    -> on_press:Event.Handler.t
    -> label:Widget.t
    -> unit
    -> Widget.t
end

module Navigation_destination : sig
  type t

  val create
    :  ?enabled:bool
    -> ?selected_icon:Widget.t
    -> icon:Widget.t
    -> label:string
    -> unit
    -> t
end

val navigation_bar
  :  ?key:Key.t
  -> selected_index:int
  -> on_select:Event.Handler.t
  -> Navigation_destination.t list
  -> unit
  -> Widget.t

module Radio_group : sig
  type t

  val option : id:int64 -> ?enabled:bool -> ?label:Widget.t -> unit -> t

  val create
    :  ?key:Key.t
    -> selected_id:int64 option
    -> on_select:Event.Handler.t
    -> t list
    -> unit
    -> Widget.t
end

module Segmented_button : sig
  type segment

  val segment
    :  id:int64
    -> ?enabled:bool
    -> ?icon:Widget.t
    -> ?label:Widget.t
    -> ?tooltip:string
    -> unit
    -> segment

  val create
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?direction:Layout.Axis.t
    -> ?multi_selection_enabled:bool
    -> ?empty_selection_allowed:bool
    -> ?expanded_insets:Layout.Edge_insets.t
    -> ?show_selected_icon:bool
    -> ?selected_icon:Widget.t
    -> selected_ids:int64 list
    -> on_selection_changed:Event.Handler.t
    -> segment list
    -> unit
    -> Widget.t
end

module Range : sig
  type t

  val create : start:float -> end_:float -> t
end

val slider
  :  ?key:Key.t
  -> ?min:float
  -> ?max:float
  -> ?divisions:int
  -> ?label:string
  -> ?enabled:bool
  -> ?on_change:Event.Handler.t
  -> value:float
  -> on_change_end:Event.Handler.t
  -> unit
  -> Widget.t

val range_slider
  :  ?key:Key.t
  -> ?min:float
  -> ?max:float
  -> ?divisions:int
  -> ?label_start:string
  -> ?label_end:string
  -> ?enabled:bool
  -> ?on_change:Event.Handler.t
  -> value:Range.t
  -> on_change_end:Event.Handler.t
  -> unit
  -> Widget.t

val action_chip
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?avatar:Widget.t
  -> on_press:Event.Handler.t
  -> label:Widget.t
  -> unit
  -> Widget.t

val filter_chip
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?avatar:Widget.t
  -> selected:bool
  -> on_selected:Event.Handler.t
  -> label:Widget.t
  -> unit
  -> Widget.t

val choice_chip
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?avatar:Widget.t
  -> selected:bool
  -> on_selected:Event.Handler.t
  -> label:Widget.t
  -> unit
  -> Widget.t

val input_chip
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?avatar:Widget.t
  -> ?delete_icon:Widget.t
  -> ?on_press:Event.Handler.t
  -> ?on_selected:Event.Handler.t
  -> ?on_delete:Event.Handler.t
  -> selected:bool
  -> label:Widget.t
  -> unit
  -> Widget.t

val alert_dialog
  :  ?key:Key.t
  -> ?icon:Widget.t
  -> ?title:Widget.t
  -> ?content:Widget.t
  -> actions:Widget.t list
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
val circular_progress_indicator : ?key:Key.t -> ?value:float -> unit -> Widget.t
val linear_progress_indicator : ?key:Key.t -> ?value:float -> unit -> Widget.t
