# bonsai_flutter

This package is the typed Flutter-side renderer for the `bonsai_flutter`
project. OCaml and Bonsai own application state, declarative UI,
reconciliation, and event handlers. Dart validates binary frames, commits them
atomically to a `NodeStore`, and will host the corresponding native Flutter
widgets.

The current development release contains:

- typed core, text-input, navigation, host-effect, and native-extension frame
  models;
- bounded little-endian frame encoding and decoding;
- strict protocol, UTF-8, epoch, revision, and graph validation;
- copy-on-write frame application with per-node dirty notifications;
- OCaml-produced frame fixtures decoded by Dart and Dart-produced event
  fixtures decoded by OCaml, with byte-for-byte clean checks;
- keyed per-node widget hosts and a typed application extension registry;
- subtree-local rebuilds and typed press event dispatch;
- bounded event batching, ordered-event backpressure, and state coalescing;
- a foreground-vsync pump with background suspension, resume catch-up, and
  exact presentation-token backpressure;
- a dedicated ordered runtime isolate and ABI 2.0 native owned-buffer
  transport boundary for renderer protocol 2.26;
- node-scoped text-input, focus, scroll, animation, and native resource
  disposal;
- Flutter-local semantic opacity interpolation with typed completion events
  and reduced-motion handling;
- a 50,000-item windowed VirtualList prototype.

Visible idle roots continue one backpressured logical pump per eligible
Flutter frame so Bonsai clocks and lifecycle work advance without external
input. Hidden, paused, and detached roots do not pump. A mounted foreground
root therefore does not settle; widget tests should use bounded frames or a
predicate helper instead of `pumpAndSettle`.

The default native package build reports an unavailable-backend fatal status
unless an application supplies the opt-in linked OCaml complete object. The
macOS arm64 integration workspace exercises that real backend. This package is
not production ready.

## Managed host adapters

`BonsaiFlutterHostAdapter` is the application-owned extension point used by a
tool-generated managed host. Its payload method may resolve platform paths,
capture application state, or call an application-owned codec asynchronously.
Its widget method may install application-owned platform and lifecycle
services around the generated host.

For a configuration that names
`lib/application_host_adapter.dart`, that file must export the fixed factory
and contract below:

```dart
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/widgets.dart';

BonsaiFlutterHostAdapter createBonsaiFlutterHostAdapter() =>
    ApplicationHostAdapter();

final class ApplicationHostAdapter implements BonsaiFlutterHostAdapter {
  @override
  Future<Uint8List> createApplicationPayload() async {
    // Resolve platform data and encode the application-specific payload here.
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  BonsaiFlutterApplicationPlatform? createApplicationPlatform() => null;

  @override
  Widget buildHost({
    required BuildContext context,
    required Widget child,
  }) {
    // Return an application-owned lifecycle or platform-service wrapper here.
    return child;
  }
}
```

The payload is opaque to `bonsai_flutter`; application codecs and validation
remain in the application repository. `RuntimeBootstrapConfig` defensively
copies the bytes and rejects payloads larger than 1 MiB. The generated host
owns the `BFR1` outer envelope, configured entrypoint and launch policy, and
`BonsaiFlutterRoot`. Adapter implementations must not encode a second `BFR1`
envelope.

Applications that need live application-owned requests or events return a
`BonsaiFlutterApplicationPlatform` instead of `null`. The bridge transports
copied opaque byte payloads up to 1 MiB; application-specific tags, codecs, and
platform signal collection remain outside this package. See
[`docs/application-platform.md`](../../../docs/application-platform.md).

Run the package checks with:

```sh
dart analyze
NO_PROXY=127.0.0.1,localhost flutter test
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/generate_input_fixtures.dart --check
```
