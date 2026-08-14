import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MessageComposerDemoApp());

final class MessageComposerDemoApp extends StatefulWidget {
  const MessageComposerDemoApp({super.key});

  @override
  State<MessageComposerDemoApp> createState() => _MessageComposerDemoAppState();
}

final class _MessageComposerDemoAppState extends State<MessageComposerDemoApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'MessageComposer adaptive demo',
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: _themeMode,
    home: _DemoScreen(
      themeMode: _themeMode,
      onThemeChanged: (mode) => setState(() => _themeMode = mode),
    ),
  );
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff7c8cff),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xff0c1020)
        : const Color(0xfff5f6fb),
  );
}

final class _DemoScreen extends StatefulWidget {
  const _DemoScreen({required this.themeMode, required this.onThemeChanged});

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<_DemoScreen> createState() => _DemoScreenState();
}

final class _DemoScreenState extends State<_DemoScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _lastAction;
  final _messages = <_DemoMessage>[
    const _DemoMessage(
      text: 'Type a draft, then swipe down to collapse it.',
      fromUser: false,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send(String message) {
    setState(() {
      _messages.add(_DemoMessage(text: message, fromUser: true));
      _messages.add(
        const _DemoMessage(
          text: 'Message received by the temporary demo.',
          fromUser: false,
        ),
      );
      _controller.clear();
    });
  }

  void _showAction(String label) {
    setState(() => _lastAction = label);
  }

  void _handleComposerButton(int buttonId, String text) {
    switch (buttonId) {
      case 1:
        _showAction('Attachment action');
      case 2:
        _showAction('Input tools action');
      case 3:
        _showAction('Dictation action');
      case 4:
        _showAction('Voice action');
      case 5:
        final message = text.trim();
        if (message.isNotEmpty) _send(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final usingDarkTheme = widget.themeMode == ThemeMode.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MessageComposer'),
            Text(
              'Adaptive demo',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: usingDarkTheme ? 'Use light theme' : 'Use dark theme',
            onPressed: () => widget.onThemeChanged(
              usingDarkTheme ? ThemeMode.light : ThemeMode.dark,
            ),
            icon: Icon(
              usingDarkTheme
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                itemCount: _messages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final message = _messages[_messages.length - index - 1];
                  return _MessageBubble(message: message);
                },
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _lastAction == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey(_lastAction),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Chip(
                        avatar: const Icon(Icons.check_rounded, size: 16),
                        label: Text(_lastAction!),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: MessageComposer(
                controller: _controller,
                focusNode: _focusNode,
                hintText: 'Ask anything',
                buttons: _composerButtons,
                onButtonPressed: _handleComposerButton,
              ),
            ),
            Container(
              height: 3,
              width: 44,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _composerButtons = [
  MessageComposerButton(
    id: 1,
    tooltip: 'Add attachment',
    position: MessageComposerButtonPosition.leading,
    child: Icon(Icons.add_rounded),
  ),
  MessageComposerButton(
    id: 2,
    tooltip: 'Open input tools',
    child: Icon(Icons.speed_rounded),
  ),
  MessageComposerButton(
    id: 3,
    tooltip: 'Start dictation',
    child: Icon(Icons.mic_none_rounded),
  ),
  MessageComposerButton(
    id: 4,
    tooltip: 'Start voice input',
    visibility: MessageComposerButtonVisibility.whenEmpty,
    style: MessageComposerButtonStyle.filled,
    child: Icon(Icons.graphic_eq_rounded),
  ),
  MessageComposerButton(
    id: 5,
    tooltip: 'Send message',
    visibility: MessageComposerButtonVisibility.whenNonEmpty,
    style: MessageComposerButtonStyle.filled,
    child: Icon(Icons.arrow_upward_rounded),
  ),
];

final class _DemoMessage {
  const _DemoMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

final class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _DemoMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: message.fromUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: message.fromUser
              ? colors.primary
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: message.fromUser
              ? null
              : Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            message.text,
            style: TextStyle(
              color: message.fromUser ? colors.onPrimary : colors.onSurface,
              fontSize: 15,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}
