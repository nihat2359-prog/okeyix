import 'package:flutter/widgets.dart';

/// Keeps the app content current while preserving foreground effect entries.
class AppOverlay extends StatefulWidget {
  final GlobalKey<OverlayState> overlayKey;
  final Widget child;

  const AppOverlay({super.key, required this.overlayKey, required this.child});

  @override
  State<AppOverlay> createState() => _AppOverlayState();
}

class _AppOverlayState extends State<AppOverlay> {
  late final OverlayEntry _content;

  @override
  void initState() {
    super.initState();
    _content = OverlayEntry(builder: (_) => widget.child);
  }

  @override
  void didUpdateWidget(covariant AppOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _content.markNeedsBuild();
  }

  @override
  void dispose() {
    _content.remove();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Overlay(key: widget.overlayKey, initialEntries: [_content]);
}
