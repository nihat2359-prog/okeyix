import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:okeyix/services/reward_audio.dart';
import 'package:okeyix/core/format.dart';

const _gold = Color(0xFFFFDA83);

class WelcomeRewardDialog extends StatelessWidget {
  final int amount;
  final ValueChanged<RewardSound>? onSound;
  const WelcomeRewardDialog({super.key, required this.amount, this.onSound});
  @override
  Widget build(BuildContext context) => _RewardCard(
    amount: amount,
    title: 'Okeyix’e hoş geldin!',
    message: 'İlk masanın heyecanı seni bekliyor. Oyun başlasın!',
    badge: 'HOŞ GELDİN HEDİYESİ',
    button: 'Harika, başlayalım',
    onSound: onSound,
    onPressed: () => Navigator.of(context).pop(),
  );
}

enum _ClaimState { ready, loading, success, alreadyClaimed, error }

class DailyBonusDialog extends StatefulWidget {
  final int amount;
  final int? rewardDay;
  final List<int>? weeklyRewards;
  final int Function()? creditedAmount;
  final bool alreadyClaimed;
  // A win is shown only after a confirmed server credit.
  final Future<bool> Function() onClaim;
  final ValueChanged<RewardSound>? onSound;
  const DailyBonusDialog({
    super.key,
    required this.amount,
    required this.onClaim,
    this.rewardDay,
    this.weeklyRewards,
    this.creditedAmount,
    this.alreadyClaimed = false,
    this.onSound,
  });
  @override
  State<DailyBonusDialog> createState() => _DailyBonusDialogState();
}

class _DailyBonusDialogState extends State<DailyBonusDialog> {
  _ClaimState _state = _ClaimState.ready;
  @override
  void initState() {
    super.initState();
    if (widget.alreadyClaimed) _state = _ClaimState.alreadyClaimed;
  }

  Future<void> _claim() async {
    if (_state == _ClaimState.loading) return;
    if (_state == _ClaimState.success || _state == _ClaimState.alreadyClaimed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _state = _ClaimState.loading);
    try {
      final credited = await widget.onClaim();
      if (!mounted) return;
      setState(
        () => _state = credited
            ? _ClaimState.success
            : _ClaimState.alreadyClaimed,
      );
    } catch (_) {
      if (mounted) setState(() => _state = _ClaimState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final success = _state == _ClaimState.success;
    final already = _state == _ClaimState.alreadyClaimed;
    return _RewardCard(
      amount: success
          ? (widget.creditedAmount?.call() ?? widget.amount)
          : widget.amount,
      treasureAsset: widget.rewardDay == null || widget.rewardDay == 7
          ? 'assets/images/coins/coins_huge.png'
          : widget.rewardDay! <= 2 ? 'assets/images/coins/coins_small.png'
          : widget.rewardDay! <= 4 ? 'assets/images/coins/coins_medium.png'
          : 'assets/images/coins/coins_large.png',
      badge: success
          ? 'ÖDÜL SENİN'
          : already
          ? 'BUGÜN TAMAMLANDI'
          : widget.rewardDay == null
          ? 'HER GÜN YENİ BİR HEDİYE'
          : '7 GÜNLÜK HEDİYE YOLCULUĞU',
      title: success
          ? 'Harika! Kazandın.'
          : already
          ? 'Bugünkü ödülün alındı'
          : widget.rewardDay == null
          ? 'Günlük bonusun hazır!'
          : widget.rewardDay == 7
          ? 'Büyük sandığın hazır!'
          : '${widget.rewardDay}. gün hediyen hazır!',
      message: success
          ? widget.rewardDay == null
                ? 'Coinlerin hesabına eklendi. Şimdi masada parlama zamanı!'
                : widget.rewardDay == 7
                ? 'Büyük sandığın Coinleri hesabına eklendi. Yarın yeni bir 7 günlük yolculuk başlıyor!'
                : 'Coinlerin hesabına eklendi. Yarın ${widget.rewardDay! + 1}. gün hediyen için yeniden gel!'
          : already
          ? 'Yarın yeni bir bonus için tekrar gel. Masalar seni bekliyor.'
          : widget.rewardDay == null
          ? 'Yeni bir gün, yeni bir şans. Hediyeni al, masaya güçlü başla.'
          : 'Her gün bir hediye, 7. gün büyük sandık! Bir gün ara versen de ilerlemen kaybolmaz.',
      footer: widget.rewardDay != null && widget.weeklyRewards != null
          ? _SevenDayTrail(
              day: widget.rewardDay!,
              rewards: widget.weeklyRewards!,
              claimed: success || already,
            )
          : null,
      button: success || already
          ? 'Devam et'
          : _state == _ClaimState.error
          ? 'Tekrar dene'
          : 'Al',
      loading: _state == _ClaimState.loading,
      success: success,
      alreadyClaimed: already,
      error: _state == _ClaimState.error
          ? 'Bonus alınamadı. Lütfen tekrar deneyin.'
          : null,
      onPressed: _claim,
      onSound: widget.onSound,
    );
  }
}

class _SevenDayTrail extends StatelessWidget {
  final int day;
  final List<int> rewards;
  final bool claimed;
  const _SevenDayTrail({
    required this.day,
    required this.rewards,
    required this.claimed,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 62,
    child: Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 6 ? 0 : 4),
              child: Semantics(
                label:
                    '${i + 1}. gün, ${rewards[i]} Coin, '
                    '${i + 1 < day || (i + 1 == day && claimed)
                        ? "alındı"
                        : i + 1 == day
                        ? "bugün"
                        : "sıradaki"}',
                child: Container(
                  key: ValueKey('reward-day-${i + 1}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: i + 1 == day
                          ? [const Color(0xCC77532B), const Color(0xDD30251B)]
                          : [const Color(0xDD293039), const Color(0xDD111820)],
                    ),
                    border: Border.all(
                      color: i + 1 == day ? _gold : const Color(0x556F747C),
                    ),
                    boxShadow: i + 1 == day
                        ? [
                            const BoxShadow(
                              color: Color(0x337F5823),
                              blurRadius: 8,
                            ),
                          ]
                        : [],
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      children: [
                        Text(
                          '${i + 1}. GÜN',
                          style: const TextStyle(
                            color: Color(0xFFCFC5AD),
                            fontSize: 9,
                          ),
                        ),
                        Icon(
                          i + 1 < day || (i + 1 == day && claimed)
                              ? Icons.check_circle_rounded
                              : i == 6
                              ? Icons.inventory_2_rounded
                              : Icons.monetization_on_rounded,
                          color: i + 1 <= day || i == 6
                              ? _gold
                              : const Color(0xFF8E929A),
                          size: 18,
                        ),
                        Text(
                          Format.coin(rewards[i]),
                          style: const TextStyle(
                            color: _gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _RewardCard extends StatefulWidget {
  final int amount;
  final String treasureAsset;
  final String title, message, badge, button;
  final String? error;
  final bool loading, success, alreadyClaimed;
  final VoidCallback onPressed;
  final ValueChanged<RewardSound>? onSound;
  final Widget? footer;
  const _RewardCard({
    required this.amount,
    this.treasureAsset = 'assets/images/coins/coins_huge.png',
    required this.title,
    required this.message,
    required this.badge,
    required this.button,
    required this.onPressed,
    this.onSound,
    this.footer,
    this.error,
    this.loading = false,
    this.success = false,
    this.alreadyClaimed = false,
  });
  @override
  State<_RewardCard> createState() => _RewardCardState();
}

class _RewardCardState extends State<_RewardCard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  RewardAudio? _audio;
  void _sound(RewardSound sound) {
    if (widget.onSound != null) {
      widget.onSound!(sound);
    } else {
      unawaited((_audio ??= RewardAudio()).play(sound));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sound(RewardSound.opening);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _audio?.stop();
  }

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final AnimationController _win = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    }
  }

  @override
  void didUpdateWidget(covariant _RewardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.success && !oldWidget.success) _sound(RewardSound.won);
    if (widget.success &&
        !oldWidget.success &&
        !MediaQuery.disableAnimationsOf(context)) {
      _win.forward(from: 0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audio?.dispose();
    _entrance.dispose();
    _win.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _entrance.drive(CurveTween(curve: Curves.easeOutCubic));
    return PopScope(
      canPop: false,
      child: SafeArea(
        child: Dialog(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, bounds) => FadeTransition(
              opacity: curve,
              child: ScaleTransition(
                scale: Tween<double>(begin: .94, end: 1).animate(curve),
                child: SizedBox(
                  width: math.min(bounds.maxWidth, 980),
                  height: math.min(bounds.maxHeight, 520),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/images/table.png',
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0x55030D0C),
                                  Color(0xD9071315),
                                  Color(0xF2071015),
                                ],
                                stops: [0, .55, 1],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'O K E Y I X',
                                          style: TextStyle(
                                            color: _gold,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey('reward-close'),
                                      tooltip: 'Kapat',
                                      onPressed: widget.loading
                                          ? null
                                          : () => Navigator.of(context).pop(),
                                      icon: const Icon(Icons.close_rounded),
                                      color: const Color(0xFFE5D4AF),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(flex: 5, child: _treasure()),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        flex: 5,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(
                                                child: SingleChildScrollView(
                                                  key: const ValueKey(
                                                    'reward-details',
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const SizedBox(height: 6),
                                                      CustomPaint(
                                                        painter:
                                                            const _Insignia(),
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets.fromLTRB(
                                                                20,
                                                                6,
                                                                8,
                                                                6,
                                                              ),
                                                          child: Text(
                                                            widget.badge,
                                                            style:
                                                                const TextStyle(
                                                                  color: _gold,
                                                                  fontSize: 10,
                                                                  letterSpacing:
                                                                      1.4,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Text(
                                                        widget.title,
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFFFFF1D4,
                                                          ),
                                                          fontSize: 30,
                                                          height: 1.06,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          shadows: [
                                                            Shadow(
                                                              color:
                                                                  Colors.black,
                                                              offset: Offset(
                                                                0,
                                                                3,
                                                              ),
                                                              blurRadius: 8,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Semantics(
                                                        liveRegion: true,
                                                        child: Text(
                                                          widget.message,
                                                          style:
                                                              const TextStyle(
                                                                color: Color(
                                                                  0xFFC2CEC8,
                                                                ),
                                                                fontSize: 13,
                                                                height: 1.5,
                                                              ),
                                                        ),
                                                      ),
                                                      if (widget.error != null)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 8,
                                                              ),
                                                          child: Semantics(
                                                            liveRegion: true,
                                                            child: Text(
                                                              widget.error!,
                                                              style:
                                                                  const TextStyle(
                                                                    color: Color(
                                                                      0xFFFFC6B4,
                                                                    ),
                                                                    height: 1.3,
                                                                  ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              _action(),
                                              const SizedBox(height: 4),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.footer != null) ...[
                                  const SizedBox(height: 8),
                                  widget.footer!,
                                ],
                              ],
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
    );
  }

  Widget _treasure() => LayoutBuilder(
    builder: (context, bounds) => Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: bounds.maxHeight * .25,
          child: AnimatedBuilder(
            animation: _win,
            builder: (context, child) => Transform.scale(
              scale: 1 + math.sin(_win.value * math.pi) * .12,
              child: child,
            ),
            child: LayoutBuilder(builder: (context, space) {
              final side = math.min(space.maxWidth, space.maxHeight);
              return Center(child: SizedBox.square(dimension: side,
                child: CustomPaint(
                  painter: _RewardDais(base: widget.treasureAsset.endsWith('coins_small.png') ? .68 : .76),
                  child: Image.asset(widget.treasureAsset, fit: BoxFit.contain,
                    excludeFromSemantics: true),
                ),
              ));
            }),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 4,
          height: bounds.maxHeight * .30,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: '${widget.amount} coin',
                  excludeSemantics: true,
                  child: Text(
                    '+ ${NumberFormat.decimalPattern('tr').format(widget.amount)}',
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 54,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(color: Color(0xFF382205), offset: Offset(0, 3)),
                        Shadow(color: Color(0xAA000000), blurRadius: 12),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.alreadyClaimed
                      ? 'BUGÜNKÜ BONUS ALINDI'
                      : widget.success
                      ? 'HESABINA EKLENDİ'
                      : 'COIN HEDİYESİ',
                  style: const TextStyle(
                    color: Color(0xFFE1CF9D),
                    fontSize: 10,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _WinParticles(_win)),
          ),
        ),
      ],
    ),
  );

  Widget _action() => CustomPaint(
    painter: _MetalButton(widget.loading),
    child: ElevatedButton.icon(
      key: const ValueKey('reward-action'),
      onPressed: widget.loading ? null : widget.onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        foregroundColor: const Color(0xFF30220E),
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        shape: const BeveledRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      icon: widget.loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              widget.success || widget.alreadyClaimed
                  ? Icons.arrow_forward_rounded
                  : Icons.redeem_rounded,
            ),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          widget.loading ? 'Alınıyor...' : widget.button,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: .4,
          ),
        ),
      ),
    ),
  );
}

class _MetalButton extends CustomPainter {
  final bool disabled;
  _MetalButton(this.disabled);
  @override
  void paint(Canvas canvas, Size size) {
    Path shape(Rect r) => Path()
      ..moveTo(r.left + 12, r.top)
      ..lineTo(r.right - 12, r.top)
      ..lineTo(r.right, r.center.dy)
      ..lineTo(r.right - 12, r.bottom)
      ..lineTo(r.left + 12, r.bottom)
      ..lineTo(r.left, r.center.dy)
      ..close();
    final rect = Offset.zero & size;
    canvas.drawPath(
      shape(rect.shift(const Offset(0, 4))),
      Paint()..color = const Color(0xFF60401B),
    );
    canvas.drawPath(
      shape(rect),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: disabled
              ? const [Color(0xFF8F8872), Color(0xFF5D584D)]
              : const [Color(0xFFFFE9AF), Color(0xFFD5A746), Color(0xFFB57D29)],
          stops: disabled ? null : const [0, .55, 1],
        ).createShader(rect),
    );
    canvas.drawPath(
      shape(rect.deflate(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x99FFF0BD),
    );
  }

  @override
  bool shouldRepaint(covariant _MetalButton oldDelegate) =>
      oldDelegate.disabled != disabled;
}

class _Insignia extends CustomPainter {
  const _Insignia();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFCBAD69)
      ..strokeWidth = 1;
    final y = size.height / 2;
    canvas.drawPath(
      Path()
        ..moveTo(5, y - 5)
        ..lineTo(10, y)
        ..lineTo(5, y + 5)
        ..lineTo(0, y)
        ..close(),
      p,
    );
    canvas.drawLine(
      Offset(20, size.height),
      Offset(size.width, size.height),
      p..color = const Color(0x667B704F),
    );
  }

  @override
  bool shouldRepaint(covariant _Insignia oldDelegate) => false;
}

class _RewardDais extends CustomPainter {
  final double base;
  const _RewardDais({required this.base});
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * base);
    final oval = Rect.fromCenter(
      center: center,
      width: size.width * .72,
      height: size.height * .10,
    );
    canvas.drawOval(
      oval.shift(const Offset(0, 5)),
      Paint()..color = const Color(0xBB020908),
    );
    canvas.drawOval(
      oval,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF335748), Color(0xFF102821)],
        ).createShader(oval),
    );
    canvas.drawOval(
      oval.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFB89856),
    );
    final paint = Paint()
      ..color = const Color(0x668D7B49)
      ..strokeWidth = 1;
    for (var i = 0; i < 9; i++) {
      final angle = math.pi + i * math.pi / 8;
      final origin = Offset(size.width / 2, size.height * .38);
      canvas.drawLine(
        origin +
            Offset(
              math.cos(angle) * size.width * .28,
              math.sin(angle) * size.height * .23,
            ),
        origin +
            Offset(
              math.cos(angle) * size.width * .42,
              math.sin(angle) * size.height * .36,
            ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RewardDais oldDelegate) => oldDelegate.base != base;
}

class _WinParticles extends CustomPainter {
  final Animation<double> progress;
  _WinParticles(this.progress) : super(repaint: progress);
  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final paint = Paint()..color = _gold.withValues(alpha: 1 - t);
    final center = size.center(Offset.zero);
    for (var i = 0; i < 20; i++) {
      final angle = i * math.pi * 2 / 20;
      final radius = 18 + 95 * Curves.easeOut.transform(t);
      final point =
          center +
          Offset(
            math.cos(angle) * radius,
            math.sin(angle) * radius * .6 + 18 * t * t,
          );
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(angle + t * 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: i.isEven ? 5 : 3,
            height: 8,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WinParticles oldDelegate) =>
      oldDelegate.progress != progress;
}
