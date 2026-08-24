# bonsai_flutter Integration Application

This deployable Flutter host exercises the aggregate OCaml application object,
the generated C ABI, the dedicated Dart runtime isolate, reconciliation, and
real Flutter widgets.

The `ocaml/` directory owns integration-only snapshots of the example
components exercised by this aggregate host. They are local Dune modules, not
dependencies on sibling example packages, so both macOS and iPhoneOS builds
remain self-contained consumer builds. Update a snapshot deliberately when an
integration assertion adopts changed example behavior.

Run the verified macOS suite from the repository root:

```sh
make integration-test
```

Build the unsigned iPhoneOS application:

```sh
cd flutter/integration_test
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

The signed physical-device matrix is:

```sh
make ci-ios-device IOS_DEVICE_ID=<physical-device-id>
```

It requires the external signing inputs described in
`docs/ios-device-testing.md`. iOS Simulator is unsupported; run the signed
suite on an explicitly selected physical iPhone.

Run the warmed Mail interaction performance gate on the same device:

```sh
../../_build/default/bonsai_flutter_tool/bin/main.exe exec --profile=profile -- \
  flutter drive --profile --no-dds \
  -d <physical-device-id> \
  --target integration_test/mail_profile_test.dart \
  --driver test_driver/mail_profile_test.dart \
  --timeout 600
```

The driver performs two warm-up repetitions and measures twenty repetitions
for each route and swipe interaction group. It writes the verified frame
summary to `build/mail_profile_summary.json`.

The Mail Profile run also records startup samples, distance, and latency for
the real OCaml Mail row in `mail_real_row_startup`.

Compare stock `flutter_slidable` gesture startup with a pure reference fixture
on the same physical iPhone:

```sh
bonsai-flutter exec --profile=profile -- \
  flutter drive --profile --no-dds \
  -d <physical-device-id> \
  --target integration_test/slidable_stock_gesture_device_test.dart \
  --driver test_driver/slidable_stock_gesture_device_test.dart \
  --timeout 600
```

The test records three trials for slow, normal, and fast vertical delivery
schedules against otherwise identical pure and stock-Slidable-wrapped
representative rows. It also verifies eventual vertical scrolling, horizontal
and near-diagonal opening, RTL logical start, and non-touch pointer behavior.
The emitted `representative_row_startup` lines complement the real Mail-row
samples and are characterization evidence; parity is not a gate.

Run the modal-sheet keyboard choreography gate in Profile mode on a physical
iPhone:

```sh
../../_build/default/bonsai_flutter_tool/bin/main.exe exec --profile=profile -- \
  flutter drive --profile --no-dds \
  -d <physical-device-id> \
  --target integration_test/bottom_sheet_keyboard_profile_test.dart \
  --driver test_driver/bottom_sheet_keyboard_profile_test.dart \
  --timeout 600
```

The test samples route progress, focus, keyboard inset, and sheet geometry. It
requires automatic focus to begin only after the fixed large sheet entrance
completes, keeps the settled sheet shell stationary while the keyboard covers
its lower region, and enforces 90th-percentile build and raster times below 16
milliseconds. The driver writes the aggregate, non-content summary to
`build/bottom_sheet_keyboard_profile_summary.json`.

To record a pre-change comparison without enforcing the staged-focus
assertion, add `--dart-define=BONSAI_RECORD_KEYBOARD_BASELINE=true` to the
`flutter drive` command. The baseline driver output uses
`build/bottom_sheet_keyboard_profile_baseline.json`.

The 2026-08-11 same-device run on a physical iPhone with iOS 26.6 recorded the
following non-content aggregates:

| Run | First-focus route progress | Build p90 | Raster p90 | Missed build/raster budgets |
| --- | ---: | ---: | ---: | ---: |
| Pre-change baseline | `0.0` | `1.878 ms` | `0.860 ms` | `0 / 0` |
| Staged autofocus | `1.0` | `2.083 ms` | `0.011 ms` | `0 / 0` |
| Fixed large shell | `1.0` | `1.803 ms` | `1.039 ms` | `0 / 0` |

All runs remained inside the 16 millisecond p90 gate. The focus-progress
change is the timing evidence: automatic focus moved from the start of the
route to its completed state without adding a second keyboard-inset animation.
The fixed-large-shell run additionally held the settled sheet at logical
coordinates `top = 47` and `bottom = 844` for every sampled keyboard frame.
