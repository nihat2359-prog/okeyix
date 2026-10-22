import 'package:flutter/material.dart';
import '../../services/quick_play_service.dart';
import 'lobby_metal_surface.dart';

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
      final short = compact || limits.maxHeight < 160;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 490),
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
                                  'Masa yoksa kendi liginde botla hemen başla.',
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

class _QuickPlayWaitDialogState extends State<QuickPlayWaitDialog> {
  bool _closed = false;
  QuickPlayController get flow => widget.controller;
  @override
  void initState() {
    super.initState();
    flow.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) flow.start();
    });
  }

  void _changed() {
    if (!mounted || _closed) return;
    if (flow.terminal) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          Navigator.of(
            context,
          ).pop(flow.phase == QuickPlayPhase.ready ? flow.result : null);
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    flow.removeListener(_changed);
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
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: LobbyMetalSurface(
              flatBorder: true,
              surfaceOpacity: 2.3,
              radius: 22,
              padding: const EdgeInsets.all(20),
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
                        : 'Uygun masa aranıyor',
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
                            : 'Oynayabileceğin tüm ligler taranıyor. Uygun masa yoksa kendi liginde en düşük girişle bot rakiple başlayacaksın.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFBAC7C3),
                      fontSize: 12,
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
                    child: const Text('İptal'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
