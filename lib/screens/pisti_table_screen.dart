import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../dev/pisti/pisti_screen.dart';
import '../dev/pisti/pisti_chrome.dart';
import '../dev/pisti/pisti_model.dart';
import '../services/pisti_service.dart';
import '../ui/game_world.dart';
import '../ui/game_invite_dialog.dart';
import '../ui/lobby/lobby_avatar.dart';
import '../services/analytics_service.dart';
import '../services/table_chat_sync.dart';
import 'pisti_lobby_screen.dart';

class PistiTableScreen extends StatefulWidget {
  const PistiTableScreen({
    super.key,
    required this.roomId,
    this.controller,
    this.inviteOnOpen = false,
  });
  final bool inviteOnOpen;
  final String roomId;
  final PistiController? controller;
  @override
  State<PistiTableScreen> createState() => _PistiTableScreenState();
}

class _PistiTableScreenState extends State<PistiTableScreen>
    with WidgetsBindingObserver {
  late final PistiController controller;
  bool _foreground = true;
  bool _showResult = false;
  String? _lastMatch;
  Timer? _resultTimer;
  Timer? _clock;
  Duration _offset = Duration.zero;
  String? _lastServerNow;
  late final TableChatSync _chatSync;
  RealtimeChannel? _socialChannel;
  Timer? _noticeTimer;
  Map<String, dynamic>? _notice;
  bool _chatReady = false;
  bool _leaving = false;
  int? _preparingVersion;
  bool _inviteOpened = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller =
        (widget.controller ?? PistiController(widget.roomId, PistiService()))
          ..addListener(_changed)
          ..start();
    _lastServerNow = controller.snapshot?['now']?.toString();
    final initialNow = DateTime.tryParse(_lastServerNow ?? '');
    if (initialNow != null) _offset = initialNow.difference(DateTime.now());
    _lastMatch = controller.snapshot?['room']['match_id'] as String?;
    _showResult = controller.snapshot?['room']['status'] == 'finished';
    _chatSync = TableChatSync(
      loadRecent: () => controller.service.recentMessages(widget.roomId),
      onMessage: _receiveMessage,
    );
    _socialChannel = controller.service.watchMessages(widget.roomId, (message) {
      if (_chatReady) {
        _chatSync.receive(message);
      } else {
        _chatSync.seed([message]);
      }
    }, () => unawaited(_restoreSocial()));
    unawaited(_restoreSocial());
    unawaited(
      AnalyticsService.instance.logEvent(
        name: 'pisti_table_open',
        parameters: {'game_type': 'pisti'},
      ),
    );
    _startClock();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareSeat());
  }

  void _changed() {
    if (!mounted) return;
    final room = controller.snapshot?['room'];
    final finished = room?['status'] == 'finished';
    if (room?['match_id'] != _lastMatch) {
      _lastMatch = room?['match_id'] as String?;
      _showResult = finished;
    } else if (finished && !_showResult && _resultTimer == null) {
      _resultTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _showResult = true);
        _resultTimer = null;
      });
    }
    if (!finished) {
      _resultTimer?.cancel();
      _resultTimer = null;
      _showResult = false;
    }
    final now = DateTime.tryParse(
      controller.snapshot?['now']?.toString() ?? '',
    );
    final serverNow = controller.snapshot?['now']?.toString();
    if (now != null && serverNow != _lastServerNow) {
      _offset = now.difference(DateTime.now());
      _lastServerNow = serverNow;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareSeat());
  }

  Future<void> _restoreSocial() async {
    try {
      if (!_chatReady) {
        final rows = await controller.service.recentMessages(widget.roomId);
        _chatSync.seed(rows);
        _chatReady = true;
      }
      await _chatSync.refresh();
    } catch (_) {
      /* Reconnect and foreground restore retry the persisted feed. */
    }
  }

  void _receiveMessage(Map<String, dynamic> message) {
    if (!mounted ||
        !_foreground ||
        (ModalRoute.of(context)?.isCurrent != true)) {
      return;
    }
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _notice = null);
      }
    });
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          _foreground &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    controller.setActive(_foreground);
    if (_foreground) {
      _startClock();
      unawaited(_restoreSocial());
    } else {
      _clock?.cancel();
    }
  }

  @override
  void dispose() {
    _resultTimer?.cancel();
    _chatSync.dispose();
    _noticeTimer?.cancel();
    if (_socialChannel != null) {
      unawaited(controller.service.client.removeChannel(_socialChannel!));
    }
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  Future<bool> _exit() async {
    if (controller.membershipEnded) return true;
    if (controller.busy) return false;
    final data = controller.snapshot;
    if (data == null ||
        (data['viewer'] as int) < 0 ||
        data['room']['status'] == 'closed') {
      return true;
    }
    final playing = data['room']['status'] == 'playing';
    if (playing) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => GameWindow(
          title: const Text('Masadan ayrıl?'),
          content: Text(
            data['room']['casual'] == true
                ? 'Maç hükmen biter. Coin veya rating etkilenmez.'
                : 'Devam eden maç hükmen yenilgiyle biter. Giriş bedeli iade edilmez.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Oyuna dön'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ayrıl'),
            ),
          ],
        ),
      );
      if (yes != true) return false;
      await controller.send('forfeit', {
        'version': data['room']['version'],
        'match_id': data['room']['match_id'],
      });
      if (controller.membershipEnded) return true;
      if (controller.error != null) return false;
    }
    await controller.send('leave');
    return controller.membershipEnded || controller.error == null;
  }

  void _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      if (await _exit() && mounted) Navigator.pop(context);
    } finally {
      _leaving = false;
    }
  }

  Future<void> _prepareSeat() async {
    if (!mounted || controller.busy || controller.membershipEnded) return;
    final data = controller.snapshot;
    if (data == null || data['room']['status'] != 'waiting') return;
    if (widget.inviteOnOpen &&
        !_inviteOpened &&
        data['viewer'] >= 0 &&
        data['room']['seats'].length == 1) {
      _inviteOpened = true;
      unawaited(_invite());
    }
    final viewer = data['viewer'] as int;
    final version = data['room']['version'] as int;
    if (viewer < 0 ||
        data['room']['seats'][viewer]['ready'] == true ||
        _preparingVersion == version) {
      return;
    }
    _preparingVersion = version;
    await controller.send('ready', {'ready': true});
  }

  Future<void> _retryPreparation() async {
    _preparingVersion = null;
    await controller.retry();
    await _prepareSeat();
  }

  @override
  Widget build(BuildContext context) {
    final data = controller.snapshot;
    if (controller.membershipEnded) {
      return PistiShell(
        title: 'PİŞTİ',
        onBack: _leave,
        child: GameEmptyState(
          title: 'Bu masadaki oturumun sona erdi',
          message:
              'Lobiye dönüp yeni bir masa açabilir veya açık bir masaya katılabilirsin.',
          icon: Icons.meeting_room_outlined,
          action: FilledButton(
            onPressed: _leave,
            child: const Text('Lobiye dön'),
          ),
        ),
      );
    }
    if (data == null) {
      return PistiShell(
        title: 'PİŞTİ',
        child: Center(
          child: controller.error == null
              ? const GameEmptyState(
                  title: 'Masana bağlanıyorsun',
                  message: 'Kartlar ve masa bilgileri getiriliyor.',
                  icon: Icons.wifi_rounded,
                )
              : GameEmptyState(
                  title: 'Masaya bağlanılamadı',
                  message: controller.error!,
                  icon: Icons.wifi_off_rounded,
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller.error!.contains('Genel Seyirci Geçişi'))
                        FilledButton(
                          onPressed: controller.busy
                              ? null
                              : () => controller.send('buy_pass'),
                          child: const Text('24 saat geçiş · 10000 Coin'),
                        ),
                      TextButton(
                        onPressed: controller.retry,
                        child: const Text('Yeniden dene'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    final room = data['room'] as Map;
    final viewer = data['viewer'] as int;
    final status = room['status'];
    final game = data['game'];
    final deadline = DateTime.tryParse(room['deadline']?.toString() ?? '');
    final remaining = deadline == null
        ? 0
        : (deadline.difference(DateTime.now().add(_offset)).inMilliseconds /
                  1000)
              .ceil()
              .clamp(0, 300);
    final seats = room['seats'] as List;
    return Theme(
      data: gameWorldTheme(context),
      child: Material(
        type: MaterialType.transparency,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _leave();
          },
          child: Stack(
            children: [
              if (game != null)
                PistiDemoScreen(
                  key: ValueKey(room['match_id']),
                  online: controller,
                  turnSeconds: remaining,
                )
              else
                PistiShell(
                  title: 'PİŞTİ · MASA HAZIRLIĞI',
                  onBack: _leave,
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: GameArtwork(kind: GameArtKind.pisti),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: GameTray(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ListView(
                                  children: [
                                    if (controller.error != null)
                                      GameTray(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              controller.error!,
                                              style: const TextStyle(
                                                color: Color(0xFFF0B4A4),
                                                fontSize: 12,
                                                height: 1.4,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: controller.busy
                                                  ? null
                                                  : _retryPreparation,
                                              child: const Text('Yeniden dene'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Text(
                                      room['casual'] == true
                                          ? 'Ücretsiz · Hedef ${data['settings']['target']}'
                                          : '${room['entry_coin']} Coin · Hedef ${data['settings']['target']}',
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(height: 12),
                                    for (final p in seats)
                                      ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        minVerticalPadding: 0,
                                        leading: Icon(
                                          p['bot'] == true
                                              ? Icons.smart_toy_outlined
                                              : Icons.person_outline,
                                        ),
                                        title: Text(
                                          '${p['name']}${p['bot'] == true ? ' · BOT' : ''}',
                                        ),
                                        trailing: Text(
                                          p['bot'] == true ? 'BOT' : 'MASADA',
                                        ),
                                      ),
                                    if (seats.length < 2)
                                      const ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        leading: Icon(
                                          Icons.event_seat_outlined,
                                        ),
                                        title: Text(
                                          'Boş koltuk · Oyuncu bekleniyor',
                                        ),
                                      ),
                                    Text(
                                      room['casual'] == true
                                          ? 'Arkadaşın katılınca maç başlar. Coin veya rating değişmez.'
                                          : 'İkinci oyuncu katılınca maç başlar; giriş bedeli bir kez kesilir.',
                                    ),
                                  ],
                                ),
                              ),
                              if (viewer >= 0)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    seats.length == 1
                                        ? room['casual'] == true
                                              ? 'Özel masan hazır. Mevcut arkadaşlarından birini davet et.'
                                              : 'Masan açık. Davet bölümünden oyuncu veya bot çağırabilirsin.'
                                        : 'Oyuncular tamam. Maç başlıyor…',
                                    style: const TextStyle(
                                      color: worldGold,
                                      fontSize: 10,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              if (viewer >= 0 && seats.length == 1)
                                OutlinedButton.icon(
                                  onPressed: controller.busy ? null : _invite,
                                  icon: const Icon(
                                    Icons.person_add_alt_1_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    controller.busy
                                        ? 'Masa güncelleniyor…'
                                        : room['casual'] == true
                                        ? 'Arkadaş davet et'
                                        : 'Oyuncu davet et',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (game != null &&
                  ((status == 'finished' && _showResult) || status == 'closed'))
                Positioned.fill(
                  child: Theme(
                    data: gameWorldTheme(context),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: PistiResult(
                              game: PistiGame.remote(
                                Map<String, dynamic>.from(game as Map),
                                viewer,
                              ),
                              online: true,
                              titleOverride: viewer < 0
                                  ? 'Maç tamamlandı'
                                  : game['reason'] == 'normal'
                                  ? null
                                  : game['reason'] == 'admin_cancel'
                                  ? 'Maç iptal edildi'
                                  : game['winner'] == viewer
                                  ? 'Hükmen kazandın.'
                                  : 'Hükmen yenilgi.',
                              replayEnabled:
                                  status == 'finished' &&
                                  viewer >= 0 &&
                                  !controller.busy,
                              names: [
                                seats[viewer < 0 ? 0 : viewer]['name']
                                    as String,
                                seats[viewer < 0 ? 1 : 1 - viewer]['name']
                                    as String,
                              ],
                              onReplay: () {
                                if (viewer >= 0) {
                                  unawaited(controller.send('rematch'));
                                }
                              },
                            ),
                          ),
                          Positioned(
                            left: 20,
                            bottom: 12,
                            right: 20,
                            child: Text(
                              '${_reason(game['reason'] as String?)} · ${room['casual'] == true
                                  ? 'Ücretsiz Pişti Molası · Coin ve rating değişmez'
                                  : viewer >= 0
                                  ? game['reason'] == 'admin_cancel'
                                        ? '${room['entry_coin']} Coin iade'
                                        : game['winner'] == viewer
                                        ? '${(room['entry_coin'] as int) * 2} Coin ödül'
                                        : '${room['entry_coin']} Coin giriş'
                                  : ''} · ${status == 'closed'
                                  ? 'Masa kapandı. Lobiye dönebilirsin.'
                                  : viewer < 0
                                  ? 'SEYİRCİ'
                                  : (data['rematch'] as List).contains(controller.service.client.auth.currentUser?.id)
                                  ? 'Rövanş için rakibin onayı bekleniyor'
                                  : 'Yeni maç iki tarafın kabulüyle başlar.'}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (status == 'closed' && game == null)
                const Positioned.fill(
                  child: GameWorldBackdrop(
                    child: GameEmptyState(
                      title: 'Masa kapandı',
                      message: 'Lobiye dönerek yeni bir masaya katılabilirsin.',
                      icon: Icons.meeting_room_outlined,
                    ),
                  ),
                ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 5,
                right: 12,
                child: Material(
                  color: const Color(0xee10231b),
                  borderRadius: BorderRadius.circular(16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'playing' && viewer < 0)
                        const Text(
                          'SEYİRCİ',
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      if (status != 'closed')
                        IconButton(
                          tooltip: 'Sohbet, ses ve hediyeler',
                          onPressed: _social,
                          icon: const Icon(
                            Icons.chat_bubble_outline,
                            color: Color(0xffe3c78c),
                            size: 20,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Kurallar ve el puanları',
                        onPressed: () => showPistiRules(
                          context,
                          game: game == null
                              ? null
                              : Map<String, dynamic>.from(game as Map),
                          settings: Map<String, dynamic>.from(
                            data['settings'] as Map,
                          ),
                        ),
                        icon: const Icon(
                          Icons.help_outline,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Lobiye dön',
                        onPressed: _leave,
                        icon: const Icon(
                          Icons.exit_to_app,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (controller.error != null && game != null)
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 6,
                  child: Material(
                    color: const Color(0xff352b2a),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              controller.error!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: controller.busy ? null : controller.retry,
                          child: const Text('Yeniden dene'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_notice != null)
                Positioned(
                  left: MediaQuery.sizeOf(context).width * .25,
                  right: MediaQuery.sizeOf(context).width * .25,
                  top: MediaQuery.paddingOf(context).top + 52,
                  child: IgnorePointer(
                    child: _notice!['kind'] == 'gift'
                        ? TweenAnimationBuilder<double>(
                            key: ValueKey(_notice!['id']),
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 1400),
                            builder: (context, v, child) => Transform.translate(
                              offset: Offset(0, -18 * v),
                              child: Transform.scale(
                                scale:
                                    .6 + .4 * Curves.easeOutBack.transform(v),
                                child: child,
                              ),
                            ),
                            child: Image.asset(
                              'assets/images/hediyeler/${_notice!['body']}.png',
                              height: 64,
                            ),
                          )
                        : Material(
                            color: const Color(0xee10231b),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                '${_notice!['username']}: ${_notice!['kind'] == 'voice' ? '🎤 Sesli mesaj' : _notice!['body']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _reason(String? reason) => switch (reason) {
    'normal' => 'Maç tamamlandı',
    'leave' => 'Ayrılma · hükmen sonuç',
    'timeout' => 'Süre aşımı · hükmen sonuç',
    'disconnect' => 'Bağlantı koptu · hükmen sonuç',
    'admin_cancel' => 'Yönetici iptali · girişler iade edildi',
    _ => 'Maç sonucu',
  };
  Future<void> _invite() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => GameInviteDialog(
        invitationHint: 'İki kişilik Pişti masası',
        loadPlayers: () => controller.service.invitablePlayers(widget.roomId),
        avatarBuilder: (url, name) =>
            LobbyAvatar(username: name, avatarUrl: url, size: 22),
        onInvite: (player) async {
          if (player['is_bot'] == true) {
            await controller.send('bot', {'bot_id': player['id']});
          } else {
            await controller.send('invite', {'to_user': player['id']});
          }
          if (controller.error != null) throw StateError(controller.error!);
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        },
      ),
    );
  }

  Future<void> _social() async {
    await showDialog<void>(
      context: context,
      builder: (_) => PistiSocialDialog(controller: controller),
    );
    if (mounted) controller.setActive(_foreground);
  }
}

class PistiSocialDialog extends StatefulWidget {
  const PistiSocialDialog({super.key, required this.controller});
  final PistiController controller;
  @override
  State<PistiSocialDialog> createState() => _PistiSocialDialogState();
}

class _PistiSocialDialogState extends State<PistiSocialDialog>
    with WidgetsBindingObserver {
  final text = TextEditingController(),
      recorder = AudioRecorder(),
      player = AudioPlayer();
  final bytes = BytesBuilder();
  StreamSubscription<Uint8List>? recording;
  Timer? limit;
  RealtimeChannel? channel;
  List<Map<String, dynamic>> messages = [], gifts = [];
  bool busy = false, recordingNow = false;
  bool _recordBusy = false;
  String? error;
  PistiController get c => widget.controller;
  bool get spectator => (c.snapshot?['viewer'] as int? ?? -1) < 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    channel = c.service.client
        .channel('pisti-chat:${c.roomId}:${const Uuid().v4()}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'okeyix_pisti_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: c.roomId,
          ),
          callback: (_) => unawaited(_load()),
        )
        .subscribe();
  }

  Future<void> _load() async {
    try {
      final rows = await c.service.client
          .from('okeyix_pisti_messages')
          .select()
          .eq('table_id', c.roomId)
          .order('created_at', ascending: false)
          .limit(50);
      final catalog = await c.service.client
          .from('okeyix_gift_catalog')
          .select()
          .eq('enabled', true)
          .order('sort_order');
      if (mounted) {
        setState(() {
          messages = rows;
          gifts = catalog;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = pistiError(e));
    }
  }

  Future<void> _send(String kind, String body, {String? request}) async {
    if (busy || (spectator && kind != 'text') || recordingNow) return;
    setState(() => busy = true);
    try {
      await c.send(kind, {'body': body}, request);
      if (c.error != null) {
        if (mounted) setState(() => error = c.error);
      } else {
        text.clear();
        await _load();
      }
    } catch (e) {
      if (mounted) setState(() => error = pistiError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _record() async {
    if (_recordBusy || (busy && !recordingNow) || spectator) return;
    _recordBusy = true;
    var uploadingVoice = false;
    try {
      if (recordingNow) {
        await recorder.stop();
        await recording?.cancel();
        limit?.cancel();
        if (mounted) setState(() => recordingNow = false);
        final pcm = bytes.takeBytes();
        if (pcm.isEmpty) return;
        final id = const Uuid().v4(),
            path = '${c.service.client.auth.currentUser!.id}/$id.wav';
        uploadingVoice = true;
        if (mounted) setState(() => busy = true);
        await c.service.client.storage
            .from('pisti-voice')
            .uploadBinary(
              path,
              _wav(pcm),
              fileOptions: const FileOptions(contentType: 'audio/wav'),
            );
        if (!mounted) {
          await c.service.client.storage.from('pisti-voice').remove([path]);
          return;
        }
        setState(() => busy = false);
        await _send('voice', path, request: id);
      } else {
        if (!await recorder.hasPermission()) return;
        bytes.clear();
        final stream = await recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        );
        recording = stream.listen(bytes.add);
        if (mounted) setState(() => recordingNow = true);
        limit = Timer(const Duration(seconds: 15), () => unawaited(_record()));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = 'Ses kaydı gönderilemedi. Mikrofon iznini kontrol et.',
        );
      }
    } finally {
      _recordBusy = false;
      if (uploadingVoice && mounted) setState(() => busy = false);
    }
  }

  Uint8List _wav(Uint8List pcm) {
    final out = ByteData(44 + pcm.length);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        out.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    out.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVEfmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little);
    out.setUint16(22, 1, Endian.little);
    out.setUint32(24, 16000, Endian.little);
    out.setUint32(28, 32000, Endian.little);
    out.setUint16(32, 2, Endian.little);
    out.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    out.setUint32(40, pcm.length, Endian.little);
    final result = out.buffer.asUint8List();
    result.setAll(44, pcm);
    return result;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      limit?.cancel();
      unawaited(recorder.cancel());
      unawaited(recording?.cancel());
      unawaited(player.stop());
      if (mounted) setState(() => recordingNow = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    limit?.cancel();
    unawaited(recording?.cancel());
    unawaited(recorder.dispose());
    unawaited(player.dispose());
    if (channel != null) unawaited(c.service.client.removeChannel(channel!));
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GameWindow(
    insetPadding: const EdgeInsets.all(12),
    child: SizedBox(
      width: 720,
      height:
          MediaQuery.sizeOf(context).height -
          MediaQuery.viewInsetsOf(context).bottom -
          32,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: Text('MASA SOHBETİ · PİŞTİ')),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ListView(
                      reverse: true,
                      children: [
                        if (messages.isEmpty)
                          const GameEmptyState(
                            title: 'Sohbete ilk sen başla',
                            message: 'Masadaki mesajlar burada görünür.',
                            icon: Icons.chat_bubble_outline_rounded,
                          ),
                        for (final m in messages)
                          ListTile(
                            dense: true,
                            title: Text(m['username'] as String),
                            subtitle: m['kind'] == 'voice'
                                ? TextButton(
                                    onPressed: () async {
                                      try {
                                        final url = await c
                                            .service
                                            .client
                                            .storage
                                            .from('pisti-voice')
                                            .createSignedUrl(
                                              m['body'] as String,
                                              60,
                                            );
                                        await player.setUrl(url);
                                        unawaited(player.play());
                                      } catch (_) {
                                        if (mounted) {
                                          setState(
                                            () => error = 'Ses açılamadı.',
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('▶ Sesli mesaj'),
                                  )
                                : Text(
                                    m['kind'] == 'gift'
                                        ? '🎁 ${m['body']}'
                                        : m['body'] as String,
                                  ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!spectator)
                    Expanded(
                      flex: 2,
                      child: ListView(
                        children: [
                          const Text('RAKİBE HEDİYE'),
                          for (final g in gifts)
                            ListTile(
                              dense: true,
                              leading: Image.asset(
                                'assets/images/hediyeler/${g['filename']}',
                                width: 28,
                                errorBuilder: (_, e, s) =>
                                    const Icon(Icons.card_giftcard),
                              ),
                              title: Text(
                                g['name_tr'] as String,
                                style: const TextStyle(fontSize: 11),
                              ),
                              subtitle: Text(
                                '${g['price']} Coin',
                                style: const TextStyle(fontSize: 10),
                              ),
                              onTap: busy
                                  ? null
                                  : () => _send('gift', g['id'] as String),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (error != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await c.retry();
                      if (mounted) setState(() => error = c.error);
                      await _load();
                    },
                    child: const Text('Yeniden dene'),
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: text,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Masaya mesaj',
                      counterText: '',
                    ),
                    onSubmitted: busy ? null : (v) => _send('text', v),
                  ),
                ),
                if (!spectator)
                  IconButton(
                    tooltip: recordingNow
                        ? 'Kaydı gönder'
                        : 'Ses kaydet (en çok 15 sn)',
                    onPressed: busy ? null : _record,
                    icon: Icon(
                      recordingNow ? Icons.stop_circle : Icons.mic,
                      color: recordingNow ? Colors.red : Colors.white,
                    ),
                  ),
                IconButton(
                  tooltip: 'Gönder',
                  onPressed: busy
                      ? null
                      : () => _send('text', text.text.trim()),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
