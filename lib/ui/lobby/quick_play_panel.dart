import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/quick_play_service.dart';
import 'lobby_metal_surface.dart';
import 'lobby_micro_motion.dart';

/// Compact gold table action; account linking remains a separate tap target.
class LobbyQuickPlayBar extends StatefulWidget {
  final VoidCallback? onPlay;
  final Widget? guestControl;
  const LobbyQuickPlayBar({super.key, required this.onPlay, this.guestControl});

  @override
  State<LobbyQuickPlayBar> createState() => _LobbyQuickPlayBarState();
}

class _LobbyQuickPlayBarState extends State<LobbyQuickPlayBar> {
  bool _pressed = false;
  VoidCallback? get onPlay => widget.onPlay;
  Widget? get guestControl => widget.guestControl;

  void _press(bool pressed) {
    if (_pressed == pressed || (pressed && onPlay == null)) return;
    setState(() => _pressed = pressed);
  }

  @override
  void didUpdateWidget(covariant LobbyQuickPlayBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (onPlay == null) _pressed = false;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 14,
            child: LobbyQuickPlayMotion(
              enabled: onPlay != null,
              borderRadius: BorderRadius.circular(13),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: AnimatedContainer(
                  key: const ValueKey('quick-play-key-depth'),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 90),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x66000000),
                        offset: Offset(0, _pressed ? 3 : 6),
                        blurRadius: 4,
                      ),
                      BoxShadow(
                        color: onPlay != null
                            ? const Color(0xFF8C5808)
                            : const Color(0xFF4C5945),
                        offset: Offset(0, _pressed ? 1 : 4),
                        blurRadius: 0,
                      ),
                      if (onPlay != null)
                        const BoxShadow(
                          color: Color(0x38E9AD40),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                      side: BorderSide(
                        color: onPlay != null
                            ? const Color(0xFFFFDF8B)
                            : const Color(0xFF77867A),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: onPlay != null
                              ? const [
                                  Color(0xFFFFE07D),
                                  Color(0xFFF5B027),
                                  Color(0xFFC9820B),
                                ]
                              : const [
                                  Color(0xFFB5B7A0),
                                  Color(0xFF929C87),
                                  Color(0xFF71836E),
                                ],
                          stops: const [0, .48, 1],
                        ),
                      ),
                      child: InkWell(
                        key: const ValueKey('quick-play'),
                        onTap: onPlay,
                        onTapDown: onPlay == null ? null : (_) => _press(true),
                        onTapUp: (_) => _press(false),
                        onTapCancel: () => _press(false),
                        splashColor: const Color(0x44FFFFFF),
                        highlightColor: const Color(0x22FFFFFF),
                        child: LayoutBuilder(
                          builder: (context, bounds) => Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned(
                                top: 1,
                                left: 12,
                                right: 12,
                                child: IgnorePointer(
                                  child: Container(
                                    height: 1,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0x00FFFFFF),
                                          Color(0xCCFFFFFF),
                                          Color(0x00FFFFFF),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: bounds.maxWidth > 240 ? 25 : 8,
                                  vertical: 4,
                                ),
                                child: Align(
                                  alignment: Alignment.center,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 29,
                                          height: 29,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFF244D3B),
                                                Color(0xFF10271E),
                                              ],
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFFFE6A5),
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Color(0x4480521D),
                                                offset: Offset(0, 1),
                                                blurRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: onPlay != null
                                                ? const Icon(
                                                    Icons.bolt_rounded,
                                                    color: Color(0xFFFFDA80),
                                                    size: 23,
                                                  )
                                                : const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 1.7,
                                                          color: Color(
                                                            0xFFFFDA80,
                                                          ),
                                                        ),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        Text(
                                          onPlay != null
                                              ? 'HIZLI OYNA'
                                              : 'MASA ARANIYOR',
                                          style: const TextStyle(
                                            color: Color(0xFF2C2412),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1,
                                            shadows: [
                                              Shadow(
                                                color: Color(0x77FFF3CC),
                                                offset: Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (bounds.maxWidth > 240 && onPlay != null)
                                const Positioned(
                                  right: 8,
                                  top: 0,
                                  bottom: 0,
                                  child: IgnorePointer(
                                    child: Icon(
                                      Icons.chevron_right_rounded,
                                      size: 22,
                                      color: Color(0xFF76501F),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (guestControl != null) ...[
            const SizedBox(width: 10),
            Flexible(
              flex: 10,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: guestControl!),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class QuickPlayPanel extends StatelessWidget {
  final VoidCallback? onPlay;
  final String leagueName;
  final bool compact;
  const QuickPlayPanel({
    super.key,
    required this.onPlay,
    required this.leagueName,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, limits) {
      final short = compact || limits.maxHeight < 160 || limits.maxWidth < 280;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 490),
          child: LobbyQuickPlayMotion(
            enabled: onPlay != null,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('quick-play'),
                onTap: onPlay,
                borderRadius: BorderRadius.circular(20),
                child: LobbyMetalSurface(
                  flatBorder: true,
                  surfaceOpacity: 1.7,
                  radius: 20,
                  padding: EdgeInsets.symmetric(
                    horizontal: short ? 14 : 22,
                    vertical: short ? 9 : 20,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: short ? 30 : 48,
                        height: short ? 30 : 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF1D99E), Color(0xFFB78A3E)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFE5BD6F,
                              ).withValues(alpha: .12),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          size: short ? 24 : 37,
                          color: const Color(0xFF28220F),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'HIZLI OYNA',
                              style: TextStyle(
                                color: const Color(0xFFF2DBA5),
                                fontSize: short ? 13 : 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .8,
                              ),
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 5),
                              Text(
                                'Tüm liglerde uygun masa ara',
                                maxLines: 2,
                                style: const TextStyle(
                                  color: Color(0xFFBDC8C5),
                                  fontSize: 11,
                                ),
                              ),
                              if (!short)
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Gerçek rakip için en fazla 5 saniye ara.',
                                    style: TextStyle(
                                      color: Color(0xFF8F9F9B),
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFE6C78A),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class QuickPlayWaitDialog extends StatefulWidget {
  final QuickPlayController controller;
  final String leagueName;
  const QuickPlayWaitDialog({
    super.key,
    required this.controller,
    required this.leagueName,
  });
  @override
  State<QuickPlayWaitDialog> createState() => _QuickPlayWaitDialogState();
}

class _QuickPlayWaitDialogState extends State<QuickPlayWaitDialog>
    with WidgetsBindingObserver {
  bool _closed = false;
  bool _foreground = true;
  QuickPlayController get flow => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    flow.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _foreground) flow.start();
      if (mounted && !_foreground) flow.cancel();
    });
  }

  void _changed() {
    if (!mounted || _closed) return;
    if (flow.terminal && _foreground) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_foreground) {
          _closed = false;
          return;
        }
        if (mounted) {
          Navigator.of(
            context,
          ).pop(flow.phase == QuickPlayPhase.ready ? flow.result : null);
        }
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _changed();
    } else if (!flow.terminal) {
      unawaited(flow.cancel());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    flow.removeListener(_changed);
    if (!flow.terminal) unawaited(flow.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cancelling = flow.phase == QuickPlayPhase.cancelling;
    final failed = flow.phase == QuickPlayPhase.error;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) flow.cancel();
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 270),
          child: LobbyMetalSurface(
            flatBorder: true,
            surfaceOpacity: 2.3,
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'HIZLI OYNA · TÜM LİGLER',
                          style: TextStyle(
                            color: Color(0xFFAF9D78),
                            fontSize: 10,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          cancelling
                              ? 'İşlem iptal ediliyor'
                              : failed
                              ? 'Oyun başlatılamadı'
                              : 'Gerçek rakip aranıyor…',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFF2DDAA),
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!failed)
                          const LinearProgressIndicator(
                            color: Color(0xFFE3C17D),
                            backgroundColor: Colors.white10,
                          ),
                        const SizedBox(height: 12),
                        Text(
                          flow.message ??
                              (cancelling
                                  ? 'İşlem sunucuda doğrulanıyor.'
                                  : 'En fazla 5 saniye gerçek rakip aranır. Bulunamazsa bot kullanımına izin verilen liglerde botla başlanır.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFBAC7C3),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (failed)
                  TextButton(
                    onPressed: flow.busy ? null : flow.retry,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFE3C17D),
                    ),
                    child: const Text('Yeniden dene'),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: cancelling ? null : flow.cancel,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFC6CFCC),
                  ),
                  child: const Text('Vazgeç'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
