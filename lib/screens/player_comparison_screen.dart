import 'package:flutter/material.dart';
import 'package:okeyix/models/player_comparison.dart';
import 'package:okeyix/ui/comparison_arena.dart';
import 'package:okeyix/ui/comparison_share_dialog.dart';

class PlayerComparisonScreen extends StatefulWidget {
  const PlayerComparisonScreen({
    super.key,
    required this.viewerId,
    required this.opponentId,
    required this.load,
    this.share,
  });
  final String viewerId;
  final String opponentId;
  final Future<PlayerComparison> Function(String, String) load;
  final Future<void> Function(BuildContext, PlayerComparison)? share;
  @override
  State<PlayerComparisonScreen> createState() => _PlayerComparisonScreenState();
}

class _PlayerComparisonScreenState extends State<PlayerComparisonScreen> {
  late Future<PlayerComparison> _future;
  void _load() {
    _future = Future.sync(
      () => widget.load(widget.viewerId, widget.opponentId),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PlayerComparisonScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerId != widget.viewerId ||
        oldWidget.opponentId != widget.opponentId) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0B1718),
    body: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/images/lobby/lobby.png', fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xE5102220), Color(0xD907111A)],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: FutureBuilder<PlayerComparison>(
              key: ValueKey('${widget.viewerId}:${widget.opponentId}'),
              future: _future,
              builder: (context, snapshot) {
                final data =
                    snapshot.connectionState == ConnectionState.done &&
                        !snapshot.hasError
                    ? snapshot.data
                    : null;
                return Column(
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/logo/okeyix_logo.png',
                          width: 95,
                          height: 32,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'İKİLİ REKABET',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: comparisonGold,
                              fontSize: 10,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: data == null
                              ? null
                              : () async {
                                  await (widget.share ??
                                      showComparisonShareDialog)(context, data);
                                },
                          icon: const Icon(Icons.ios_share_rounded, size: 17),
                          label: const Text('Paylaş'),
                          style: TextButton.styleFrom(
                            foregroundColor: comparisonGold,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kapat',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: data == null
                          ? Center(
                              child: snapshot.hasError
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Karşılaştırma yüklenemedi',
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => setState(_load),
                                          child: const Text('Tekrar dene'),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Rekabet kayıtları yükleniyor…',
                                      style: TextStyle(color: comparisonGold),
                                    ),
                            )
                          : LayoutBuilder(
                              builder: (context, bounds) => FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: SizedBox(
                                  width: bounds.maxWidth.clamp(0.0, 1100.0),
                                  height: bounds.maxHeight.clamp(340.0, 620.0),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        flex: 6,
                                        child: ComparisonArena(data: data),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          'BİRBİRİNİZE KARŞI · EL DETAYLARI',
                                          style: TextStyle(
                                            color: comparisonGold.withValues(
                                              alpha: .8,
                                            ),
                                            fontSize: 9,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 5,
                                        child: ComparisonTotals(data: data),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Yalnız aranızdaki tamamlanmış eller. Okeyli çift, her iki bitişe dahildir.',
                                        maxLines: 3,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}
