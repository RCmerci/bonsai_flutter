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
    -> icon:Widget.t
    -> on_press:Event.Handler.t
    -> label:string
    -> unit
    -> Widget.t
end

module Navigation_destination : sig
  type t

  val create
    :  ?selected_icon:Widget.t
    -> ?badge_count:int
    -> ?badge_dot:bool
    -> ?semantic_label:string
    -> icon:Widget.t
    -> label:string
    -> unit
    -> t
end

type navigation_bar_layout =
  | Auto
  | Compact
  | Wide

type navigation_bar_visibility =
  | Always
  | Selected
  | Never

type navigation_bar_alignment =
  | Start
  | Center
  | End

type navigation_bar_size =
  | Small
  | Medium

type navigation_bar_shape =
  | Round
  | Square

type navigation_bar_density =
  | Regular
  | Compact_density

val navigation_bar
  :  ?key:Key.t
  -> ?layout:navigation_bar_layout
  -> ?alignment:navigation_bar_alignment
  -> ?label_behavior:navigation_bar_visibility
  -> ?icon_behavior:navigation_bar_visibility
  -> ?size:navigation_bar_size
  -> ?shape:navigation_bar_shape
  -> ?density:navigation_bar_density
  -> ?safe_area:bool
  -> ?semantic_label:string
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

  val segment : id:int64 -> ?icon:Widget.t -> label:string -> unit -> segment

  val create
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?multi_selection_enabled:bool
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

type slider_kind =
  | Standard
  | Centered
  | Wavy
  | Wavy_centered
  | Vertical
  | Vertical_centered

type range_slider_kind =
  | Flat
  | Wavy

val slider
  :  ?key:Key.t
  -> ?min:float
  -> ?max:float
  -> ?divisions:int
  -> ?label:string
  -> ?enabled:bool
  -> ?kind:slider_kind
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
  -> ?kind:range_slider_kind
  -> ?on_change:Event.Handler.t
  -> value:Range.t
  -> on_change_end:Event.Handler.t
  -> unit
  -> Widget.t

module Chip : sig
  type presentation =
    | Flat
    | Elevated

  val assist
    :  ?key:Key.t
    -> ?presentation:presentation
    -> ?enabled:bool
    -> ?leading:Widget.t
    -> ?selected:bool
    -> on_press:Event.Handler.t
    -> label:string
    -> unit
    -> Widget.t

  val suggestion
    :  ?key:Key.t
    -> ?presentation:presentation
    -> ?enabled:bool
    -> ?leading:Widget.t
    -> ?selected:bool
    -> on_press:Event.Handler.t
    -> label:string
    -> unit
    -> Widget.t

  val filter
    :  ?key:Key.t
    -> ?presentation:presentation
    -> ?enabled:bool
    -> ?leading:Widget.t
    -> selected:bool
    -> on_press:Event.Handler.t
    -> label:string
    -> unit
    -> Widget.t

  val input
    :  ?key:Key.t
    -> ?presentation:presentation
    -> ?enabled:bool
    -> ?leading:Widget.t
    -> selected:bool
    -> on_press:Event.Handler.t
    -> ?on_delete:Event.Handler.t
    -> label:string
    -> unit
    -> Widget.t
end

module Tooltip : sig
  val plain : ?key:Key.t -> message:string -> Widget.t -> Widget.t

  val rich
    :  ?key:Key.t
    -> ?title:string
    -> message:string
    -> actions:Widget.t list
    -> Widget.t
    -> Widget.t
end

val search_bar
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?read_only:bool
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
  -> ?leading:Widget.t
  -> ?trailing:Widget.t list
  -> ?hint_text:string
  -> ?on_tap:Event.Handler.t
  -> unit
  -> Widget.t

module Data_table : sig
  type column
  type row
  type cell

  val column
    :  id:int64
    -> ?tooltip:string
    -> ?numeric:bool
    -> ?sortable:bool
    -> label:Widget.t
    -> unit
    -> column

  val cell
    :  ?placeholder:bool
    -> ?show_edit_icon:bool
    -> ?activatable:bool
    -> Widget.t
    -> cell

  val row : id:int64 -> ?selected:bool -> ?selection_enabled:bool -> cell list -> row

  val create
    :  ?key:Key.t
    -> ?sort_column_id:int64
    -> ?sort_ascending:bool
    -> ?selected_row_ids:int64 list
    -> ?on_sort:Event.Handler.t
    -> ?on_row_selected:Event.Handler.t
    -> ?on_select_all:Event.Handler.t
    -> ?on_cell_activate:Event.Handler.t
    -> columns:column list
    -> rows:row list
    -> unit
    -> Widget.t
end

module Stepper : sig
  type orientation =
    | Vertical
    | Horizontal

  type state =
    | Indexed
    | Editing
    | Complete
    | Disabled
    | Error

  type step

  val step
    :  id:int64
    -> title:Widget.t
    -> content:Widget.t
    -> ?subtitle:Widget.t
    -> ?label:Widget.t
    -> ?active:bool
    -> ?state:state
    -> unit
    -> step

  val create
    :  ?key:Key.t
    -> ?orientation:orientation
    -> current_step_id:int64
    -> ?on_step_selected:Event.Handler.t
    -> ?on_continue:Event.Handler.t
    -> ?on_cancel:Event.Handler.t
    -> step list
    -> unit
    -> Widget.t
end

module Expansion_panel_list : sig
  type policy =
    | Multiple
    | Single

  type panel

  val panel
    :  id:int64
    -> header:Widget.t
    -> body:Widget.t
    -> ?enabled:bool
    -> ?can_tap_on_header:bool
    -> unit
    -> panel

  val create
    :  ?key:Key.t
    -> ?policy:policy
    -> expanded_ids:int64 list
    -> on_expansion_changed:Event.Handler.t
    -> panel list
    -> unit
    -> Widget.t
end

module Dialog : sig
  type option_

  val option : id:int64 -> ?enabled:bool -> label:Widget.t -> unit -> option_

  val alert
    :  ?key:Key.t
    -> ?icon:Widget.t
    -> ?content:Widget.t
    -> ?top_divider:bool
    -> ?bottom_divider:bool
    -> title:string
    -> actions:Widget.t list
    -> unit
    -> Widget.t

  val simple
    :  ?key:Key.t
    -> ?title:Widget.t
    -> on_select:Event.Handler.t
    -> option_ list
    -> unit
    -> Widget.t

  val fullscreen : ?key:Key.t -> Widget.t -> Widget.t
end

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

type text_field_variant =
  | Filled
  | Outlined

val text_field
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?read_only:bool
  -> ?obscure_text:bool
  -> ?keyboard_type:Text_editing.keyboard_type
  -> ?input_action:Text_editing.input_action
  -> ?max_utf8_bytes:int
  -> ?variant:text_field_variant
  -> ?label:string
  -> ?supporting_text:string
  -> ?error_text:string
  -> ?leading:Widget.t
  -> ?trailing:Widget.t
  -> ?max_lines:int
  -> ?autofocus:bool
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
  -> ?supporting_text:string
  -> ?overline:string
  -> ?leading:Widget.t
  -> ?trailing:Widget.t
  -> on_press:Event.Handler.t
  -> headline:string
  -> unit
  -> Widget.t

type divider_orientation =
  | Horizontal
  | Vertical

type card_variant =
  | Elevated
  | Filled
  | Outlined

val divider
  :  ?key:Key.t
  -> ?orientation:divider_orientation
  -> ?thickness:float
  -> ?spacing:float
  -> ?indent:float
  -> ?end_indent:float
  -> unit
  -> Widget.t

val card : ?key:Key.t -> ?variant:card_variant -> ?elevation:float -> Widget.t -> Widget.t

type progress_kind =
  | Flat
  | Wavy

val circular_progress_indicator
  :  ?key:Key.t
  -> ?kind:progress_kind
  -> ?value:float
  -> unit
  -> Widget.t

val linear_progress_indicator
  :  ?key:Key.t
  -> ?kind:progress_kind
  -> ?value:float
  -> unit
  -> Widget.t

module Menu : sig
  type entry

  val entry : id:int64 -> label:string -> ?enabled:bool -> unit -> entry

  val selectable
    :  id:int64
    -> label:string
    -> selected:bool
    -> ?enabled:bool
    -> unit
    -> entry

  val toggleable
    :  id:int64
    -> label:string
    -> checked:bool
    -> ?enabled:bool
    -> unit
    -> entry

  val divider : entry
  val group : ?label:string -> entry list -> entry
  val submenu : id:int64 -> label:string -> ?enabled:bool -> entry list -> entry

  val create
    :  ?key:Key.t
    -> on_select:Event.Handler.t
    -> entries:entry list
    -> anchor:Widget.t
    -> unit
    -> Widget.t
end

module Fab_menu : sig
  type position =
    | Left
    | Right

  type item

  val item : id:int64 -> icon:Widget.t -> label:string -> ?enabled:bool -> unit -> item

  val create
    :  ?key:Key.t
    -> ?position:position
    -> expand_icon:Widget.t
    -> collapse_icon:Widget.t
    -> on_select:Event.Handler.t
    -> item list
    -> unit
    -> Widget.t
end

module Button_group : sig
  type group_type =
    | Standard
    | Connected

  type button_style =
    | Filled
    | Tonal
    | Elevated
    | Outlined
    | Text

  type size =
    | Extra_small
    | Small
    | Medium
    | Large
    | Extra_large

  type shape =
    | Round
    | Square

  type overflow =
    | Wrap
    | Scroll
    | Menu

  type selection =
    | No_selection
    | Single of int64 option
    | Multiple of int64 list

  type action

  val action
    :  id:int64
    -> ?icon:Widget.t
    -> ?label:string
    -> ?enabled:bool
    -> unit
    -> action

  val create
    :  ?key:Key.t
    -> ?group_type:group_type
    -> ?style:button_style
    -> ?size:size
    -> ?shape:shape
    -> ?axis:Layout.Axis.t
    -> ?overflow:overflow
    -> selection:selection
    -> on_selection_changed:Event.Handler.t
    -> action list
    -> unit
    -> Widget.t
end

module Toggle_button : sig
  type style =
    | Filled
    | Tonal
    | Elevated
    | Outlined
    | Text

  val create
    :  ?key:Key.t
    -> ?style:style
    -> ?enabled:bool
    -> checked:bool
    -> on_changed:Event.Handler.t
    -> ?icon:Widget.t
    -> ?checked_icon:Widget.t
    -> ?label:Widget.t
    -> unit
    -> Widget.t
end

module Split_button : sig
  type style =
    | Filled
    | Tonal
    | Elevated
    | Outlined

  val create
    :  ?key:Key.t
    -> ?style:style
    -> ?enabled:bool
    -> label:string
    -> on_press:Event.Handler.t
    -> on_select:Event.Handler.t
    -> menu:Menu.entry list
    -> unit
    -> Widget.t
end

module Dropdown_menu : sig
  type item

  type content =
    | Items of item list
    | Loading
    | Empty of string
    | Error of string

  type selection =
    | Single of int64 option
    | Multiple of int64 list

  val item : id:int64 -> label:string -> ?enabled:bool -> unit -> item

  val create
    :  ?key:Key.t
    -> ?searchable:bool
    -> ?query:string
    -> ?on_query_changed:Event.Handler.t
    -> selection:selection
    -> on_selection_changed:Event.Handler.t
    -> content
    -> unit
    -> Widget.t
end

module Date : sig
  type t

  val create : year:int -> month:int -> day:int -> t
end

module Date_picker : sig
  type mode =
    | Day
    | Year

  val calendar
    :  ?key:Key.t
    -> ?current:Date.t
    -> ?mode:mode
    -> ?selectable_dates:Date.t list
    -> selected:Date.t
    -> first:Date.t
    -> last:Date.t
    -> on_select:Event.Handler.t
    -> unit
    -> Widget.t
end

module Time : sig
  type t

  val create : hour:int -> minute:int -> t
end

module Time_picker : sig
  type format =
    | Hour_12
    | Hour_24

  val dial
    :  ?key:Key.t
    -> ?format:format
    -> value:Time.t
    -> on_changed:Event.Handler.t
    -> unit
    -> Widget.t
end

module Carousel : sig
  type layout =
    | Hero
    | Contained
    | Uncontained

  type hero_alignment =
    | Start
    | Center
    | End

  type item

  val item : id:int64 -> Widget.t -> item

  val create
    :  ?key:Key.t
    -> ?layout:layout
    -> ?axis:Layout.Axis.t
    -> ?hero_alignment:hero_alignment
    -> on_select:Event.Handler.t
    -> on_layout_changed:Event.Handler.t
    -> item list
    -> unit
    -> Widget.t
end

module Card_list : sig
  type item

  val item : id:int64 -> Widget.t -> item
  val finite : ?key:Key.t -> on_select:Event.Handler.t -> item list -> unit -> Widget.t

  val scrollable
    :  ?key:Key.t
    -> on_select:Event.Handler.t
    -> item list
    -> unit
    -> Widget.t

  val sliver
    :  ?key:Key.t
    -> on_select:Event.Handler.t
    -> item list
    -> unit
    -> Widget.Sliver.t
end

module Selection : sig
  (** [leading] flips between the normal and selected faces and emits [id] when
      the user requests a toggle. Selection remains controlled by OCaml. *)
  val leading
    :  ?key:Key.t
    -> id:int64
    -> selected:bool
    -> on_toggle:Event.Handler.t
    -> unselected:Widget.t
    -> selected_child:Widget.t
    -> unit
    -> Widget.t

  val create
    :  ?key:Key.t
    -> ?idle:Widget.t
    -> ?actions:Widget.t list
    -> ?show_select_all:bool
    -> item_ids:int64 list
    -> selected_ids:int64 list
    -> on_selection_changed:Event.Handler.t
    -> Widget.t
    -> Widget.t
end

module Dismissible_list : sig
  type request_state =
    | Ready
    | Pending
    | Accepted
    | Rejected

  type item

  val item : id:int64 -> Widget.t -> item

  val column
    :  ?key:Key.t
    -> request_token:int64
    -> request_state:request_state
    -> on_dismiss_request:Event.Handler.t
    -> item list
    -> unit
    -> Widget.t

  val horizontal
    :  ?key:Key.t
    -> request_token:int64
    -> request_state:request_state
    -> on_dismiss_request:Event.Handler.t
    -> item list
    -> unit
    -> Widget.t
end

module Expandable_list : sig
  type policy =
    | Multiple
    | Single

  type item

  val item : id:int64 -> header:string -> body:Widget.t -> unit -> item

  val finite
    :  ?key:Key.t
    -> ?policy:policy
    -> expanded_ids:int64 list
    -> on_expansion_changed:Event.Handler.t
    -> item list
    -> unit
    -> Widget.t

  val scrollable
    :  ?key:Key.t
    -> ?policy:policy
    -> expanded_ids:int64 list
    -> on_expansion_changed:Event.Handler.t
    -> item list
    -> unit
    -> Widget.t

  val sliver
    :  ?key:Key.t
    -> ?policy:policy
    -> expanded_ids:int64 list
    -> on_expansion_changed:Event.Handler.t
    -> item list
    -> unit
    -> Widget.Sliver.t
end

module Bottom_sheet : sig
  val surface : ?key:Key.t -> ?show_handle:bool -> Widget.t -> Widget.t
end

module Side_sheet : sig
  val surface : ?key:Key.t -> title:Widget.t -> body:Widget.t -> unit -> Widget.t
end

module App_bar : sig
  type search_suggestion

  val search_suggestion
    :  id:int64
    -> label:string
    -> ?enabled:bool
    -> unit
    -> search_suggestion

  type sliver_variant =
    | Small
    | Medium
    | Large

  type sliver_shape =
    | Round
    | Square

  type sliver_density =
    | Regular
    | Compact

  val top
    :  ?key:Key.t
    -> ?center_title:bool
    -> ?leading:Widget.t
    -> ?actions:Widget.t list
    -> ?safe_area:bool
    -> ?semantic_label:string
    -> title:Widget.t
    -> unit
    -> Widget.t

  val sliver
    :  ?key:Key.t
    -> ?pinned:bool
    -> ?floating:bool
    -> ?snap:bool
    -> ?center_title:bool
    -> ?background_color:int32
    -> ?foreground_color:int32
    -> ?leading:Widget.t
    -> ?actions:Widget.t list
    -> ?variant:sliver_variant
    -> ?shape:sliver_shape
    -> ?density:sliver_density
    -> ?semantic_label:string
    -> title:Widget.t
    -> unit
    -> Widget.Sliver.t

  val bottom
    :  ?key:Key.t
    -> ?floating_action_button:Widget.t
    -> ?safe_area:bool
    -> actions:Widget.t list
    -> unit
    -> Widget.t

  val search
    :  ?key:Key.t
    -> ?full_screen:bool
    -> ?center_title:bool
    -> ?leading:Widget.t
    -> ?actions:Widget.t list
    -> ?bar_leading:Widget.t
    -> ?bar_trailing:Widget.t list
    -> ?hint_text:string
    -> ?enabled:bool
    -> ?keyboard_type:Text_editing.keyboard_type
    -> ?input_action:Text_editing.input_action
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
    -> ?on_open:Event.Handler.t
    -> ?on_close:Event.Handler.t
    -> on_select:Event.Handler.t
    -> search_suggestion list
    -> unit
    -> Widget.t
end

module Tabs : sig
  type variant =
    | Primary
    | Secondary

  type tab

  val tab : id:int64 -> label:string -> ?icon:Widget.t -> unit -> tab

  val create
    :  ?key:Key.t
    -> ?variant:variant
    -> selected_id:int64
    -> on_select:Event.Handler.t
    -> tab list
    -> unit
    -> Widget.t
end

module Navigation_rail : sig
  type modality =
    | Standard
    | Modal

  type destination
  type section
  type fab

  val destination : id:int64 -> icon:Widget.t -> label:string -> unit -> destination
  val section : destination list -> section
  val fab : id:int64 -> icon:Widget.t -> label:string -> ?enabled:bool -> unit -> fab

  val create
    :  ?key:Key.t
    -> ?modality:modality
    -> ?trailing:Widget.t
    -> ?trailing_at_bottom:bool
    -> ?fab:fab
    -> expanded:bool
    -> selected_id:int64
    -> on_select:Event.Handler.t
    -> on_expanded_changed:Event.Handler.t
    -> section list
    -> unit
    -> Widget.t
end

module Navigation_drawer : sig
  type destination

  val destination : id:int64 -> icon:Widget.t -> label:string -> unit -> destination

  val create
    :  ?key:Key.t
    -> headline:string
    -> selected_id:int64
    -> on_select:Event.Handler.t
    -> destination list
    -> unit
    -> Widget.t
end

module Toolbar : sig
  type placement =
    | Floating
    | Docked

  type icon =
    | Add
    | Edit
    | Delete
    | Favorite
    | More
    | Search
    | Share

  type action
  type fab

  val action : id:int64 -> icon:icon -> ?label:string -> ?enabled:bool -> unit -> action
  val fab : id:int64 -> icon:Widget.t -> label:string -> ?enabled:bool -> unit -> fab

  val create
    :  ?key:Key.t
    -> ?placement:placement
    -> ?axis:Layout.Axis.t
    -> ?max_inline_actions:int
    -> ?fab:fab
    -> expanded:bool
    -> active_action_id:int64 option
    -> on_action:Event.Handler.t
    -> on_expanded_changed:Event.Handler.t
    -> on_active_action_changed:Event.Handler.t
    -> action list
    -> unit
    -> Widget.t
end

type badge_alignment =
  | Top_left
  | Top_center
  | Top_right

val badge : ?key:Key.t -> ?alignment:badge_alignment -> ?count:int -> Widget.t -> Widget.t

type loading_indicator_variant =
  | Uncontained
  | Contained

val loading_indicator
  :  ?key:Key.t
  -> ?variant:loading_indicator_variant
  -> ?progress:float
  -> unit
  -> Widget.t

module Refresh_indicator : sig
  type variant =
    | Expressive
    | Contained
    | Material
    | Adaptive
    | No_spinner

  type request_state =
    | Ready
    | Pending
    | Completed

  val create
    :  ?key:Key.t
    -> ?variant:variant
    -> ?show_token:int64
    -> request_token:int64
    -> request_state:request_state
    -> on_refresh_request:Event.Handler.t
    -> Widget.t
    -> Widget.t
end

module Search_anchor : sig
  type presentation =
    | Full_screen
    | Docked

  type suggestion

  val suggestion : id:int64 -> label:string -> ?enabled:bool -> unit -> suggestion

  val create
    :  ?key:Key.t
    -> ?presentation:presentation
    -> ?bar_leading:Widget.t
    -> ?bar_trailing:Widget.t list
    -> ?hint_text:string
    -> ?enabled:bool
    -> ?keyboard_type:Text_editing.keyboard_type
    -> ?input_action:Text_editing.input_action
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
    -> ?on_open:Event.Handler.t
    -> ?on_close:Event.Handler.t
    -> on_select:Event.Handler.t
    -> suggestion list
    -> unit
    -> Widget.t
end
