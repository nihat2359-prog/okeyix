import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../ui/game_world.dart';
import '../ui/pisti_invite_window.dart';
import '../ui/pisti_career_board.dart';
import '../services/pisti_service.dart';
import 'pisti_table_screen.dart';

class PistiLobbyScreen extends StatefulWidget {
  const PistiLobbyScreen({
    super.key,
    this.service,
    this.initialInviteId,
    this.initialRoomId,
  });
  final PistiService? service;
  final String? initialInviteId, initialRoomId;
  @override
  State<PistiLobbyScreen> createState() => _PistiLobbyScreenState();
}

class _PistiLobbyScreenState extends State<PistiLobbyScreen>
    with WidgetsBindingObserver {
  late final PistiService service;
  Timer? _timer;
  bool busy = false,
      loading = true,
      _reading = false,
      _initialInviteOffered = false;
  bool _foreground = true;
  String? error, _request, _pendingAction, _activeRoom;
  Map<String, dynamic>? _pendingArgs;
  bool _pendingInvite = false;
  List<Map<String, dynamic>> invites = [];
  bool enabled = false;
  @override
  void initState() {
    super.initState();
    service = widget.service ?? PistiService();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_foreground && (ModalRoute.of(context)?.isCurrent ?? false))
        unawaited(_refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final data = await service.lobby();
      if (!mounted) return;
      setState(() {
        enabled = data['settings']['enabled'] == true;
        invites = List<Map<String, dynamic>>.from(data['invites'] as List);
        _activeRoom = data['active_room_id'] as String?;
        loading = false;
        if (_pendingAction == null) error = null;
      });
      if (!_initialInviteOffered &&
          (widget.initialInviteId != null || widget.initialRoomId != null)) {
        _initialInviteOffered = true;
        if (_activeRoom != null && _activeRoom == widget.initialRoomId) {
          _open(_activeRoom!);
          return;
        }
        final matching = invites.where(
          (i) => widget.initialInviteId != null
              ? i['id'] == widget.initialInviteId
              : i['table_id'] == widget.initialRoomId,
        );
        if (matching.isNotEmpty) {
          await _offerInvite(matching.first);
        } else {
          setState(
            () => error =
                'Davetin süresi doldu veya daha önce yanıtlandı. Arkadaşından yeni bir davet iste.',
          );
        }
      }
    } catch (e) {
      if (mounted)
        setState(() {
          error = pistiError(e);
          loading = false;
        });
    } finally {
      _reading = false;
    }
  }

  Future<void> _run(
    String action,
    Map<String, dynamic> args, {
    bool invite = false,
  }) async {
    if (busy) return;
    if (_pendingAction == null) {
      _pendingAction = action;
      _pendingArgs = args;
      _pendingInvite = invite;
    }
    _request ??= const Uuid().v4();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final executing = _pendingAction!;
      final openInvite = _pendingInvite;
      final data = await service.command(
        executing,
        _pendingArgs!,
        request: _request,
      );
      _pendingAction = null;
      _pendingArgs = null;
      _request = null;
      if (mounted && data['room_id'] != null && executing != 'reject') {
        _open(data['room_id'] as String, invite: openInvite);
      } else {
        await _refresh();
      }
    } on FunctionException catch (e) {
      if (e.status < 500 && e.details is Map) {
        _pendingAction = null;
        _pendingArgs = null;
        _request = null;
      }
      if (mounted) setState(() => error = pistiError(e.details ?? e));
    } catch (e) {
      if (mounted) setState(() => error = pistiError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _open(String room, {bool invite = false}) {
    _timer?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PistiTableScreen(
          roomId: room,
          inviteOnOpen: invite,
          controller: PistiController(room, service),
        ),
      ),
    );
  }

  Future<void> _offerInvite(Map<String, dynamic> invite) async {
    final accepted = await showPistiInviteWindow(context);
    if (!mounted || accepted == null) return;
    await _run(accepted ? 'accept' : 'reject', {
      'invite_id': invite['id'],
      if (!accepted) 'room_id': invite['table_id'],
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PistiShell(
    title: 'PİŞTİ MOLASI',
    child: LayoutBuilder(
      builder: (context, c) {
        Widget choice(
          String title,
          String description,
          IconData icon,
          String mode,
        ) => Expanded(
          child: GameTray(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: worldGold, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: Color(0xFFB9C5BC),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                FilledButton(
                  onPressed:
                      busy ||
                          loading ||
                          !enabled ||
                          _pendingAction != null ||
                          _activeRoom != null
                      ? null
                      : () => _run('create', {
                          'mode': mode,
                        }, invite: mode == 'break_friend'),
                  child: Text(title),
                ),
              ],
            ),
          ),
        );
        return Column(
          children: [
            Expanded(
              child: _activeRoom != null
                  ? Center(
                      child: FilledButton.icon(
                        onPressed: () => _open(_activeRoom!),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Devam eden molana dön'),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (c.maxWidth > 700)
                          const Expanded(
                            flex: 1,
                            child: GameArtwork(kind: GameArtKind.pisti),
                          ),
                        Expanded(
                          flex: 4,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              choice(
                                'Botla Oyna',
                                'Kısa bir mola, hazır bir rakip. Rakibin bir bot; ayar seçmeden ücretsiz oyna.',
                                Icons.smart_toy_outlined,
                                'break_bot',
                              ),
                              const SizedBox(width: 12),
                              choice(
                                'Arkadaşımla Oyna',
                                'Özel masanı aç, mevcut arkadaşlarından birini davet et. Birlikte ücretsiz oyna.',
                                Icons.people_outline,
                                'break_friend',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            if (error != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF0B4A4),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _pendingAction == null
                              ? _refresh()
                              : _run(_pendingAction!, _pendingArgs!),
                    child: const Text('Yeniden dene'),
                  ),
                ],
              ),
            if (invites.isNotEmpty)
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final i in invites)
                      TextButton.icon(
                        onPressed: busy ? null : () => _offerInvite(i),
                        icon: const Icon(Icons.mail_outline, size: 18),
                        label: const Text('Arkadaşının Pişti daveti'),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    loading
                        ? 'Molan hazırlanıyor…'
                        : error != null && !enabled
                        ? 'Mola durumu doğrulanamadı.'
                        : !enabled
                        ? 'Pişti Molası şu anda kapalı.'
                        : 'Ücretsiz · Coin ve rating değişmez',
                    style: const TextStyle(color: worldGold, fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: () => showPistiRules(context),
                  child: const Text(
                    'Nasıl oynanır?',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class PistiShell extends StatelessWidget {
  const PistiShell({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.onBack,
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Theme(
    data: gameWorldTheme(context),
    child: Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF08140E),
      body: GameWorldBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Geri',
                        onPressed: onBack ?? () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: worldPaper,
                            fontSize: 15,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

const pistiRules =
    '52 kart, iki oyuncu. Ortaya dört kart, oyunculara dörder kart dağıtılır. '
    'Başlangıç valeleri alta çevrilir; dört vale gelirse yeniden dağıtılır. Dağıtmayan başlar; dağıtan her elde değişir. '
    'Aynı değer veya vale ortayı toplar. Tek kartı aynı değerle almak 10, tek valeyi valeyle almak 20 Pişti puanıdır. '
    'İlk ve son oynanan kart Pişti sayılmaz. Vale ile farklı tek kartı almak Pişti değildir. '
    'As ve vale 1; sinek 2, 2; karo 10, 3 puan. Kart çoğunluğu 3; 26–26 eşitlikte bonus yok. '
    'Kalan orta son toplayana, hiç toplama olmadıysa dağıtana gider. '
    'Hedefe el sonunda bakılır; eşitlik varsa yeni el oynanır. Pişti Molası ücretsizdir; coin ödülü ve rating değişimi yoktur. '
    'Üç süre aşımı veya 90 saniye bağlantı yokluğu hükmen yenilgidir (masa ayarı farklı olabilir). '
    'Ayrılma hükmen yenilgidir. Rövanş iki tarafın onayıyla başlar.';
Future<void> showPistiRules(
  BuildContext context, {
  Map<String, dynamic>? game,
  Map<String, dynamic>? settings,
}) => showDialog<void>(
  context: context,
  builder: (context) => GameWindow(
    title: const Text('Pişti kuralları'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(pistiRules, style: TextStyle(fontSize: 13, height: 1.6)),
        if (settings != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Bu masa: hedef ${settings['target']} · hamle ${settings['turn_seconds']} sn · bağlantı ${settings['disconnect_seconds']} sn · ${settings['timeout_limit']} süre aşımı',
              style: const TextStyle(color: worldGold, fontSize: 12),
            ),
          ),
        if (game != null) ...[
          const Divider(color: Color(0x447C7057)),
          Text(
            'TOPLAM ${(game['total'] as List).join(' – ')} · HEDEF ${game['target']}',
            style: const TextStyle(
              color: worldGold,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text('EL PUANLARI'),
          for (final round in game['rounds'] as List)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'El ${round['round']}: ${(round['score'] as List).join(' – ')} · Kartlar ${(round['cards'] as List).join(' – ')} · Pişti ${(round['pistis'] as List).join(' – ')}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if ((game['rounds'] as List).isEmpty)
            const Text('İlk el henüz tamamlanmadı.'),
        ],
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Masaya dön'),
      ),
    ],
  ),
);

class PistiCareerScreen extends StatefulWidget {
  const PistiCareerScreen({super.key, this.userId});
  final String? userId;
  @override
  State<PistiCareerScreen> createState() => _PistiCareerScreenState();
}

class _PistiCareerScreenState extends State<PistiCareerScreen> {
  late final Future<List<dynamic>> data;
  @override
  void initState() {
    super.initState();
    final db = Supabase.instance.client;
    data = Future.wait([
      db
          .from('okeyix_pisti_careers')
          .select('*,users(username)')
          .order('rating', ascending: false)
          .limit(50),
      db
          .from('okeyix_pisti_results')
          .select()
          .contains('players', [
            {'id': widget.userId ?? db.auth.currentUser!.id},
          ])
          .order('created_at', ascending: false)
          .limit(50),
      db
          .from('okeyix_pisti_careers')
          .select()
          .eq('user_id', widget.userId ?? db.auth.currentUser!.id)
          .maybeSingle(),
    ]);
  }

  @override
  Widget build(BuildContext context) => PistiShell(
    title: 'PİŞTİ · KARİYER VE MAÇ GEÇMİŞİ',
    child: FutureBuilder<List<dynamic>>(
      future: data,
      builder: (context, s) {
        if (s.hasError) {
          return GameEmptyState(
            title: 'Kariyer yüklenemedi',
            message: pistiError(s.error!),
            icon: Icons.wifi_off_rounded,
          );
        }
        if (!s.hasData) {
          return const GameEmptyState(
            title: 'Kariyerin hazırlanıyor',
            message: 'Maç geçmişin ve sıralama getiriliyor.',
            icon: Icons.hourglass_top_rounded,
          );
        }
        return PistiCareerBoard(
          leaders: s.data![0] as List,
          matches: s.data![1] as List,
          career: s.data![2] as Map?,
          otherPlayer: widget.userId != null,
        );
      },
    ),
  );
}
