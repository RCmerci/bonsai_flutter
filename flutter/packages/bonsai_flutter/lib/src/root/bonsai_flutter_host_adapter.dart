import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Application-owned behavior used by a generated Bonsai Flutter host.
///
/// Implementations create the opaque application payload asynchronously. They
/// may also wrap the generated host with application-owned platform or
/// lifecycle services. The host owns the runtime envelope and root widget.
abstract interface class BonsaiFlutterHostAdapter {
  Future<Uint8List> createApplicationPayload();

  Widget buildHost({required BuildContext context, required Widget child});
}
