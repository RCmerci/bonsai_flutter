import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';

import '../test/counter_ffi_test.dart' as counter;
import '../test/gallery_ffi_test.dart' as gallery;
import '../test/host_navigation_ffi_test.dart' as host_navigation;
import '../test/mail_ffi_test.dart' as mail;
import '../test/text_input_ffi_test.dart' as text_input;
import '../test/todo_ffi_test.dart' as todo;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  counter.main();
  gallery.main();
  text_input.main();
  todo.main();
  mail.main();
  host_navigation.registerHostNavigationFfiTests(
    implementation: const FlutterHostEffectImplementation(),
    beforeClipboardRead: () => Clipboard.setData(
      const ClipboardData(text: 'Clipboard from physical iOS'),
    ),
    expectedClipboardText: 'Clipboard from physical iOS',
  );
}
