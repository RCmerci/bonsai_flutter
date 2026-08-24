import 'package:flutter/widgets.dart';

/// Marks a message composer whose surrounding widget owns the visual surface.
final class MessageComposerSurfaceScope extends InheritedWidget {
  const MessageComposerSurfaceScope.embedded({required super.child, super.key});

  static bool isEmbedded(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MessageComposerSurfaceScope>() !=
      null;

  @override
  bool updateShouldNotify(MessageComposerSurfaceScope oldWidget) => false;
}
