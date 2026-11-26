import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/game/table_gift_flight.dart';
import 'package:okeyix/models/table_gift.dart';
import 'package:okeyix/services/table_gift_service.dart';
import 'table_gift_art.dart';

const _gold = Color(0xFFE8CA8C);

class TableGiftAnchor {
  const TableGiftAnchor(this.userId, this.name, this.key, {this.originKey});
  final String userId, name;
  final GlobalKey key;
  final GlobalKey? originKey;
}

/// Positioned over the existing avatars. Only gift buttons receive touches;
/// The same image flies and stays at its destination, without a renderer swap.
class TableGiftLayer extends StatefulWidget {
  const TableGiftLayer({
    super.key,
    required this.tableId,
    required this.anchors,
    this.spectator = false,
    this.onBalance,
    this.service,
  });
  final String tableId;
  final List<TableGiftAnchor> anchors;
  final bool spectator;
  final ValueChanged<int>? onBalance;
  final TableGiftService? service;
  @override
  State<TableGiftLayer> createState() => _TableGiftLayerState();
}

class _TableGiftLayerState extends State<TableGiftLayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TableGiftController _gifts;
  late final AnimationController _flight;
  Offset _flightFrom = Offset.zero;
  final _root = GlobalKey();
  final Map<String, Rect> _rects = {};
  final Map<String, Offset> _origins = {};
  final Queue<TableGiftEvent> _queue = Queue();
  final Set<int> _seenSequences = {};
  TableGiftEvent? _flying;
  bool _panel = false;
  int? _lastBalance;
  int _restoration = 0;
  Route<void>? _panelRoute;
  NavigatorState? _panelNavigator;
  bool _measurePending = false;
  Size? _measuredSize;
  @override
  void initState() {
    super.initState();
    _flight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    WidgetsBinding.instance.addObserver(this);
    _gifts = TableGiftController(
      tableId: widget.tableId,
      service: widget.service ?? TableGiftService(),
      spectator: widget.spectator,
    );
    _gifts.addListener(_changed);
    _gifts.onEvents = (events) {
      _queue.addAll(events.where((e) => _seenSequences.add(e.seq)));
      _drain();
    };
    _gifts.start();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant TableGiftLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (_measurePending) return;
    _measurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurePending = false;
      if (mounted) _measure();
    });
  }

  @override
  void dispose() {
    final route = _panelRoute;
    final navigator = _panelNavigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
    WidgetsBinding.instance.removeObserver(this);
    _gifts.removeListener(_changed);
    _gifts.dispose();
    _flight.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queue.clear();
      unawaited(_gifts.restore());
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_restoration != _gifts.restoration) {
      _restoration = _gifts.restoration;
      _queue.clear();
    }
    final balance = _gifts.balance;
    if (balance != null && balance != _lastBalance) {
      _lastBalance = balance;
      widget.onBalance?.call(balance);
    }
    setState(() {});
  }

  void _measure({bool drain = true}) {
    final root = _root.currentContext?.findRenderObject();
    if (root is! RenderBox || !root.hasSize || !root.attached) return;
    final next = <String, Rect>{};
    final origins = <String, Offset>{};
    for (final a in widget.anchors) {
      final origin = a.originKey?.currentContext?.findRenderObject();
      if (origin is RenderBox && origin.hasSize && origin.attached) {
        origins[a.userId] = root.globalToLocal(
          origin.localToGlobal(origin.size.center(Offset.zero)),
        );
      }
      final box = a.key.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        next[a.userId] =
            root.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
      }
    }
    _origins
      ..clear()
      ..addAll(origins);
    if (next.length != _rects.length ||
        next.entries.any((e) => _rects[e.key] != e.value)) {
      if (mounted) {
        setState(() {
          _rects
            ..clear()
            ..addAll(next);
        });
      }
    }
    if (drain) _drain();
  }

  Offset _slot(Rect rect, Size size) => Offset(
    (rect.right - 22).clamp(24.0, size.width - 24),
    (rect.top + 20).clamp(24.0, size.height - 24),
  );
  Future<void> _drain() async {
    if (!mounted ||
        widget.spectator ||
        _panel ||
        _flying != null ||
        _queue.isEmpty) {
      return;
    }
    _measure(drain: false);
    final e = _queue.first;
    final from = _rects[e.senderId], to = _rects[e.recipientId];
    if (from == null || to == null) {
      final members = widget.anchors.map((a) => a.userId).toSet();
      if (!members.contains(e.senderId) || !members.contains(e.recipientId)) {
        _queue.removeFirst();
        if (_queue.isNotEmpty) unawaited(_drain());
      }
      return;
    }
    final root = _root.currentContext?.findRenderObject();
    if (root is! RenderBox || !root.hasSize || !root.attached) return;
    _queue.removeFirst();
    _flightFrom = _origins[e.senderId] ?? from.center;
    _flight.duration = Duration(
      milliseconds: e.senderId == e.recipientId ? 550 : 1050,
    );
    _flight.value = 0;
    setState(() => _flying = e);
    try {
      await _flight.forward().orCancel;
    } catch (_) {
      /* The confirmed persistent state remains visible if art fails. */
    } finally {
      if (mounted) {
        setState(() => _flying = null);
        unawaited(_drain());
      }
    }
  }

  Widget? _giftVisual(TableGiftAnchor anchor, Size size) {
    final moving = _flying?.recipientId == anchor.userId ? _flying : null;
    final gift = moving != null
        ? TableLastGift(moving.seq, moving.giftId)
        : _gifts.latest[anchor.userId];
    if (gift == null ||
        (moving == null && _queue.any((e) => e.seq == gift.seq))) {
      return null;
    }
    final destination = _slot(_rects[anchor.userId]!, size);
    final progress = moving == null ? 1.0 : _flight.value;
    final center = moving == null
        ? destination
        : tableGiftFlightPoint(
            _flightFrom,
            destination,
            progress,
            self: moving.senderId == moving.recipientId,
          );
    final extent = 84 - 36 * Curves.easeOutCubic.transform(progress);
    return Positioned(
      key: ValueKey('gift-visual:${anchor.userId}'),
      left: center.dx - extent / 2,
      top: center.dy - extent / 2,
      child: IgnorePointer(
        ignoring: widget.spectator || moving != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.spectator ? null : () => _open(anchor),
          child: Tooltip(
            message: '${_t('Hediye', 'Gift')} · ${anchor.name}',
            child: TableGiftArt(
              key: ValueKey('last-gift:${anchor.userId}:${gift.seq}'),
              giftId: gift.giftId,
              width: extent,
              height: extent,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(TableGiftAnchor recipient) async {
    if (_panel || widget.spectator) return;
    setState(() => _panel = true);
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: _t('Kapat', 'Close'),
        barrierColor: const Color(0x33000000),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondary) {
          _panelRoute = ModalRoute.of<void>(context);
          _panelNavigator = Navigator.of(context);
          return Align(
            alignment: Alignment.centerRight,
            child: SafeArea(
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width.clamp(0, 340) * .88,
                height: double.infinity,
                child: _GiftPanel(
                  controller: _gifts,
                  onBuy: (gift) async {
                    await _gifts.buy(recipient.userId, gift);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, a, secondary, child) => SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );
    } finally {
      _panelRoute = null;
      _panelNavigator = null;
      // Wait for the closing slide before starting a queued table flight.
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (mounted) {
        setState(() => _panel = false);
        unawaited(_drain());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flight,
      builder: (context, _) => LayoutBuilder(
        builder: (context, bounds) {
          if (_measuredSize != bounds.biggest) {
            _measuredSize = bounds.biggest;
            _scheduleMeasure();
          }
          return SizedBox.expand(
            key: _root,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final a in widget.anchors)
                  if (_rects[a.userId] != null) ...[
                    if (_giftVisual(a, bounds.biggest) case final Widget visual)
                      visual,
                    if (!widget.spectator &&
                        !_gifts.latest.containsKey(a.userId))
                      Positioned(
                        left: _slot(_rects[a.userId]!, bounds.biggest).dx - 12,
                        top: _slot(_rects[a.userId]!, bounds.biggest).dy - 12,
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _open(a),
                            child: Tooltip(
                              message: '${_t('Hediye', 'Gift')} · ${a.name}',
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: const Icon(
                                  Icons.card_giftcard_rounded,
                                  size: 14,
                                  color: _gold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

String _t(String tr, String en) =>
    WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'tr'
    ? tr
    : en;

class _GiftPanel extends StatefulWidget {
  const _GiftPanel({required this.controller, required this.onBuy});
  final TableGiftController controller;
  final Future<void> Function(String) onBuy;
  @override
  State<_GiftPanel> createState() => _GiftPanelState();
}

class _GiftPanelState extends State<_GiftPanel> {
  String? error;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Material(
        color: const Color(0xC91D252E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(left: Radius.circular(22)),
          side: BorderSide(color: Color(0x887D754F)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _t('Hediyeler', 'Gifts'),
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _t('Kapat', 'Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _gold,
                      size: 21,
                    ),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    error!,
                    style: const TextStyle(
                      color: Color(0xFFFFB6A1),
                      fontSize: 11,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Expanded(
                child: c.catalog.isEmpty
                    ? Center(
                        child: c.failed
                            ? TextButton(
                                onPressed: c.restore,
                                child: Text(
                                  _t(
                                    'Yüklenemedi · Tekrar dene',
                                    'Could not load · Retry',
                                  ),
                                  style: const TextStyle(color: _gold),
                                ),
                              )
                            : const CircularProgressIndicator(color: _gold),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 5,
                              mainAxisSpacing: 5,
                              childAspectRatio: .95,
                            ),
                        itemCount: c.catalog.length,
                        itemBuilder: (context, index) {
                          final g = c.catalog[index];
                          return Material(
                            color: const Color(0x553C454F),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: c.buying
                                  ? null
                                  : () async {
                                      setState(() => error = null);
                                      try {
                                        await widget.onBuy(g.id);
                                      } catch (e) {
                                        if (mounted) {
                                          setState(
                                            () => error =
                                                e.toString().contains(
                                                  'GIFT_INSUFFICIENT_COINS',
                                                )
                                                ? _t(
                                                    'Yetersiz coin',
                                                    'Not enough coins',
                                                  )
                                                : e.toString().contains(
                                                    'GIFT_PENDING_REQUEST',
                                                  )
                                                ? _t(
                                                    'Önceki hediyeye tekrar dokunarak işlemi doğrula.',
                                                    'Tap the previous gift again to confirm the pending purchase.',
                                                  )
                                                : _t(
                                                    'İşlem doğrulanamadı. Aynı hediyeye dokunarak tekrar dene.',
                                                    'Could not confirm. Tap the same gift to retry.',
                                                  ),
                                          );
                                        }
                                      }
                                    },
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Column(
                                  children: [
                                    Expanded(child: TableGiftArt(giftId: g.id)),
                                    Text(
                                      _t(g.nameTr, g.nameEn),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      Format.coin(g.price),
                                      style: const TextStyle(
                                        color: _gold,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (c.buying)
                const LinearProgressIndicator(color: _gold, minHeight: 2),
            ],
          ),
        ),
      );
    },
  );
}
