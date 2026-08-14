# MessageComposer adaptive demo

This temporary Flutter application demonstrates the adaptive `MessageComposer`.
It starts as a compact pill, expands while focused or populated, sends local
messages, demonstrates custom leading and trailing action buttons, and supports
light and dark themes. Swipe downward to collapse it without discarding the
current draft, then tap the editor to expand it again.

Run the macOS demo:

```sh
cd tool/message_composer_demo
flutter run -d macos
```

Run it on a connected physical iPhone:

```sh
flutter run -d <physical-device-id>
```

Run its widget tests:

```sh
flutter test
```

The native widget is created from OCaml with arbitrary button content:

```ocaml
module Composer = Ui.Native_widget.Message_composer

let send_button =
  Composer.button
    ~id:1
    ~tooltip:"Send message"
    ~visibility:Composer.When_non_empty
    ~style:Composer.Filled
    ~child:(Ui.Widget.text "Send")
    ()

let composer =
  Composer.create
    ~buttons:[ send_button ]
    ~on_event:(function
      | Composer.Text_changed text -> update_draft text
      | Composer.Button_pressed { button_id = 1; text } -> send_message text
      | Composer.Button_pressed _ -> ())
    ()
```
