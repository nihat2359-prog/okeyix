import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Presentation only. Does not pause the game or own network/audio resources.
class TableChatQuickMessages extends StatelessWidget {
  const TableChatQuickMessages({super.key, required this.onSelected});
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 30,
        crossAxisSpacing: 6,
        mainAxisSpacing: 4,
      ),
      itemCount: TableChatPanel.quickMessages.length,
      itemBuilder: (context, index) => TextButton(
        onPressed: () => onSelected(TableChatPanel.quickMessages[index]),
        style: TextButton.styleFrom(
          foregroundColor: TableChatPanel.gold,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          side: const BorderSide(color: Color(0x33DABF82), width: .6),
        ),
        child: Text(TableChatPanel.quickMessages[index],
          style: const TextStyle(fontSize: 10)),
      ),
    ),
  );
}

class TableChatPanel extends StatelessWidget {
  const TableChatPanel({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.messageCount,
    required this.messageBuilder,
    required this.onClose,
    required this.onSend,
    required this.onQuickMessage,
    required this.onEmoji,
    required this.microphone,
    this.accessory,
  });

  final TextEditingController controller;
  final ScrollController scrollController;
  final int messageCount;
  final IndexedWidgetBuilder messageBuilder;
  final VoidCallback onClose, onSend, onEmoji;
  final ValueChanged<String> onQuickMessage;
  final Widget microphone;
  final Widget? accessory;
  static const quickMessages = [
    'Hızlı oyna',
    'Tebrikler',
    'Teşekkürler',
    'Bol şans',
  ];
  static const gold = Color(0xFFE3C78C);

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    onClose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: LayoutBuilder(
      builder: (context, bounds) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final height = math.min(
          350.0,
          math.max(0.0, bounds.maxHeight - keyboard - 12),
        );
        final compact = height < 170;
        final tiny = height < 90;
        final width = math.min(
          keyboard > 0 ? 420.0 : 350.0,
          bounds.maxWidth * (keyboard > 0 ? .62 : .48),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('table-chat-outside'),
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              width: width,
              height: height,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  key: const ValueKey('table-chat-panel'),
                  padding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: tiny ? 1 : 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xEC1C252B), Color(0xE60D141C)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0x55C9AD72),
                      width: .7,
                    ),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: tiny
                            ? 24
                            : compact
                            ? 30
                            : 36,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.forum_outlined,
                              size: 16,
                              color: gold,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Masa Sohbeti',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xFFEDE5D4),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('table-chat-close'),
                              tooltip: 'Sohbeti kapat',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36),
                              onPressed: _close,
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: Color(0xFFBDC5CE),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          key: const ValueKey('table-chat-messages'),
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: messageCount + 1,
                          itemBuilder: (context, index) {
                            if (index < messageCount) {
                              return messageBuilder(context, index);
                            }
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (messageCount == 0 && !compact)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text(
                                      'Masaya bir selam bırak.',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ?accessory,
                              ],
                            );
                          },
                        ),
                      ),
                      if (!compact)
                        TableChatQuickMessages(onSelected: (message) {
                          _close();
                          onQuickMessage(message);
                        }),
                      SizedBox(
                        // Keyboard insets remove the quick-message SizedBox
                        // above. Keep this subtree's identity so its TextField
                        // is not replaced (which would dismiss the iOS IME).
                        key: const ValueKey('table-chat-composer'),
                        height: tiny ? 30 : 40,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              height: 36,
                              child: FittedBox(child: microphone),
                            ),
                            IconButton(
                              tooltip: 'Emoji',
                              onPressed: onEmoji,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 36,
                              ),
                              icon: const Icon(
                                Icons.emoji_emotions_outlined,
                                color: gold,
                                size: 20,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                key: const ValueKey('table-chat-input'),
                                controller: controller,
                                style: const TextStyle(
                                  color: Color(0xFFF0F2ED),
                                  fontSize: 13,
                                ),
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => onSend(),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: 'Mesaj yaz...',
                                  hintStyle: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 8,
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('table-chat-send'),
                              tooltip: 'Gönder',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 36,
                                height: 36,
                              ),
                              onPressed: onSend,
                              icon: const Icon(
                                Icons.send_rounded,
                                color: gold,
                                size: 21,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
