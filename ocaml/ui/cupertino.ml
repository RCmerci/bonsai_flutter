let button ?key ?enabled on_press ~child () =
  Widget.Private.cupertino_button ?key ?enabled ~on_press ~child ()
;;

let switch ?key ?enabled ~value ~on_changed () =
  Widget.Private.cupertino_switch ?key ?enabled ~value ~on_changed ()
;;
