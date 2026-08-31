import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsai_flutter/src/protocol/event_batch.dart';
import 'package:bonsai_flutter/src/protocol/generated_protocol.dart';

void main(List<String> arguments) {
  final check = arguments.contains('--check');
  final repositoryRoot = findRepositoryRoot();
  final fixtureDirectory = Directory(
    '${repositoryRoot.path}/protocol/generated/fixtures',
  );
  final fixtures = <String, EventBatch>{
    'dart_counter_press.hex': counterPress,
    'dart_host_response.hex': hostResponse,
    'dart_text_edit_unicode.hex': textEditUnicode,
    'dart_text_limit_reached.hex': textLimitReached,
    'dart_environment_changed.hex': environmentChanged,
    'dart_application_response.hex': applicationResponse,
    'dart_application_event.hex': applicationEvent,
  };
  final stale = <String>[];

  for (final MapEntry(key: name, value: batch) in fixtures.entries) {
    final file = File('${fixtureDirectory.path}/$name');
    final expected = hex(EventBatchCodec.encode(batch));
    if (check) {
      if (!file.existsSync() || file.readAsStringSync() != expected) {
        stale.add(file.path);
      }
    } else {
      fixtureDirectory.createSync(recursive: true);
      file.writeAsStringSync(expected);
    }
  }

  if (stale.isNotEmpty) {
    for (final path in stale) {
      stderr.writeln('Generated fixture is stale: $path');
    }
    exitCode = 1;
  }
}

Directory findRepositoryRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/protocol/schema.sexp').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate the bonsai_flutter repository root');
    }
    directory = parent;
  }
}

String hex(Uint8List bytes) {
  final output = StringBuffer();
  for (var index = 0; index < bytes.length; index += 1) {
    if (index > 0) {
      output.write(index % 12 == 0 ? '\n' : ' ');
    }
    output.write(bytes[index].toRadixString(16).padLeft(2, '0'));
  }
  output.writeln();
  return output.toString();
}

final counterPress = EventBatch(
  runtimeEpoch: 21,
  events: const [
    UiEvent(
      sequence: 1,
      displayedRevision: 1,
      nodeId: 3,
      handlerId: 9001,
      eventTag: EventTagId.press,
      payload: UnitEventPayload(),
    ),
  ],
);

final hostResponse = EventBatch(
  runtimeEpoch: 31,
  events: [
    UiEvent(
      sequence: 2,
      displayedRevision: 3,
      nodeId: 0,
      handlerId: 0,
      eventTag: EventTagId.hostResponse,
      payload: HostResponseEventPayload(
        requestId: 44,
        status: HostResponseStatus.error,
        value: utf8.encode('denied: 剪贴板😀'),
      ),
    ),
  ],
);

final textEditUnicode = EventBatch(
  runtimeEpoch: 22,
  events: const [
    UiEvent(
      sequence: 3,
      displayedRevision: 2,
      nodeId: 4,
      handlerId: 44,
      eventTag: EventTagId.textEdit,
      payload: TextEditEventPayload(
        sessionId: 7,
        localRevision: 3,
        baseDocumentRevision: 2,
        text: '拼😀音',
        selectionStartUtf16: 4,
        selectionEndUtf16: 4,
        composingStartUtf16: 0,
        composingEndUtf16: 4,
      ),
    ),
  ],
);

final environmentChanged = EventBatch(
  runtimeEpoch: 31,
  events: const [
    UiEvent(
      sequence: 4,
      displayedRevision: 3,
      nodeId: 0,
      handlerId: 0,
      eventTag: EventTagId.environmentChanged,
      payload: EnvironmentEventPayload(
        EnvironmentSnapshot(
          viewportWidth: 1440,
          viewportHeight: 900,
          devicePixelRatio: 2,
          textScale: 1.25,
          brightness: EnvironmentBrightness.dark,
          platform: 'macos',
          locale: 'zh-CN',
          safeArea: EnvironmentInsets(left: 0, top: 24, right: 0, bottom: 0),
          keyboardInsets: EnvironmentInsets(
            left: 0,
            top: 0,
            right: 0,
            bottom: 280,
          ),
          accessibleNavigation: false,
          boldText: true,
          invertColors: false,
          disableAnimations: false,
          reducedMotion: true,
          highContrast: true,
          orientation: EnvironmentOrientation.landscape,
          pointerKinds: 10,
        ),
      ),
    ),
  ],
);

final textLimitReached = EventBatch(
  runtimeEpoch: 22,
  events: const [
    UiEvent(
      sequence: 4,
      displayedRevision: 2,
      nodeId: 4,
      handlerId: 45,
      eventTag: EventTagId.textLimitReached,
      payload: UnitEventPayload(),
    ),
  ],
);

final applicationResponse = EventBatch(
  runtimeEpoch: 41,
  events: [
    UiEvent(
      sequence: 8,
      displayedRevision: 9,
      nodeId: 0,
      handlerId: 0,
      eventTag: EventTagId.applicationResponse,
      payload: ApplicationResponseEventPayload(
        requestId: 501,
        payload: Uint8List.fromList([0, 111, 112, 97, 113, 117, 101, 255]),
      ),
    ),
  ],
);

final applicationEvent = EventBatch(
  runtimeEpoch: 41,
  events: [
    UiEvent(
      sequence: 9,
      displayedRevision: 9,
      nodeId: 0,
      handlerId: 0,
      eventTag: EventTagId.applicationEvent,
      payload: ApplicationEventPayload(
        payload: Uint8List.fromList([128, 0, 101, 118, 101, 110, 116]),
      ),
    ),
  ],
);
