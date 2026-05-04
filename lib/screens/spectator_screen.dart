import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:okeyix/services/feedback_settings_service.dart';
import '../game/spectator_game.dart';

class SpectatorScreen extends StatefulWidget {
  final String tableId;

  const SpectatorScreen({super.key, required this.tableId});

  @override
  State<SpectatorScreen> createState() => _SpectatorScreenState();
}

class _SpectatorScreenState extends State<SpectatorScreen> {
  final supabase = Supabase.instance.client;
  final topAvatarKey = GlobalKey();
  final bottomAvatarKey = GlobalKey();
  late SpectatorGame game;
  late RealtimeChannel spectatorChannel;
  Map<String, dynamic>? table;
  List players = [];
  int spectators = 0;
  final ScrollController _chatScrollController = ScrollController();
  Map<String, dynamic>? _lastIncomingMessage;
  bool _showMessageBanner = false;
  bool chatOpen = false;
  final TextEditingController chatController = TextEditingController();
  List messages = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, String> _avatarChatByUserId = {};
  final Map<String, Timer> _avatarChatTimers = {};
  DateTime? _lastFinishAt;
  bool _showFinishOverlay = false;
  String _finishWinnerName = 'Oyuncu';

  bool _isPressing = false;
  bool _isRecording = false;
  bool _showPreview = false;
  bool _previewPlaying = false;

  int _recordSeconds = 0;
  Timer? _recordTimer;
  Timer? _safetyTimer;
  DateTime? _recordStartTime;
  bool _longPressActive = false;
  String? _recordPath;
  bool _canStop = false;
  DateTime? _pressStartTime;
  String? _playingMessageId;
  String? _previewPath;
  String _recordDuration = "0:00";
  final _recorder = AudioRecorder();

  final quickMessages = [
    "Tebrikler",
    "Teşekkürler",
    "Hızlı oyna",
    "İyi oyun",
    "Şanslısın",
    "Harika hamle",
  ];
  @override
  void initState() {
    super.initState();

    game = SpectatorGame(
      tableId: widget.tableId,
      onTableClosed: () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
    );
    _joinSpectator();
    _load();
  }

  Future<void> _load() async {
    await FeedbackSettingsService.load();
    final t = await supabase
        .from('tables')
        .select()
        .eq('id', widget.tableId)
        .single();

    final p = await supabase
        .from('table_players')
        .select('user_id,seat_index,users(username,avatar_url)')
        .eq('table_id', widget.tableId);

    final s = await supabase
        .from('table_spectators')
        .select()
        .eq('table_id', widget.tableId);

    final m = await supabase
        .from('table_messages')
        .select('*,users(username)')
        .eq('table_id', widget.tableId)
        .order('created_at');

    spectatorChannel = supabase.channel('spectators:${widget.tableId}');

    spectatorChannel
        /// 👀 BİRİ GİRİNCE
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'table_spectators',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: widget.tableId,
          ),
          callback: (payload) {
            if (!mounted) return;

            setState(() {
              spectators++;
            });
          },
        )
        /// 👀 BİRİ ÇIKINCA
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'table_spectators',
          callback: (payload) {
            final old = payload.oldRecord;

            if (old['table_id'] == widget.tableId) {
              if (!mounted) return;

              setState(() {
                spectators = (spectators - 1).clamp(0, 9999);
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'table_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: widget.tableId,
          ),
          callback: (payload) async {
            if (!mounted) return;
            final msg = Map<String, dynamic>.from(payload.newRecord);
            final senderId = msg['sender_id']?.toString();
            if (senderId != null) {
              final u = await supabase
                  .from('users')
                  .select('username')
                  .eq('id', senderId)
                  .maybeSingle();
              if (u != null) {
                msg['users'] = {'username': u['username'] ?? 'Oyuncu'};
              }
            }
            setState(() {
              messages = [...messages, msg];
            });
            _handleIncomingMessageEffects(msg);
            _scrollToBottom();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tables',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.tableId,
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            final finishAtRaw = row['last_finish_at']?.toString();
            final finishAt = finishAtRaw == null
                ? null
                : DateTime.tryParse(finishAtRaw);
            if (finishAt != null &&
                (_lastFinishAt == null || finishAt.isAfter(_lastFinishAt!))) {
              _lastFinishAt = finishAt;
              final winnerId = row['last_winner_user_id']?.toString();
              String winnerName = 'Oyuncu';
              if (winnerId != null) {
                final u = await supabase
                    .from('users')
                    .select('username')
                    .eq('id', winnerId)
                    .maybeSingle();
                final name = u?['username']?.toString().trim() ?? '';
                if (name.isNotEmpty) winnerName = name;
              }
              _openFinishOverlay(winnerName);
            }
          },
        )
        .subscribe((status, err) {
          if (err != null) {
            print("SPECTATOR ERROR: $err");
          }
        });

    setState(() {
      table = t;
      players = p;
      spectators = s.length;
      messages = m;
    });
  }

  Map? player(int seat) {
    try {
      return players.firstWhere((e) => e['seat_index'] == seat);
    } catch (_) {
      return null;
    }
  }

  Widget avatar(String? path, {Key? key}) {
    if (path == null || path.isEmpty) {
      return CircleAvatar(key: key, radius: 26, backgroundColor: Colors.black);
    }

    if (path.startsWith("http")) {
      return CircleAvatar(
        key: key,
        radius: 26,
        backgroundImage: NetworkImage(path),
      );
    }

    return CircleAvatar(
      key: key,
      radius: 26,
      backgroundColor: Colors.black,
      child: ClipOval(
        child: Image.asset(path, fit: BoxFit.cover, width: 52, height: 52),
      ),
    );
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> sendMessage() async {
    if (chatController.text.isEmpty) return;

    final user = supabase.auth.currentUser;

    await supabase.from('table_messages').insert({
      "table_id": widget.tableId,
      "sender_id": user!.id,
      "content": chatController.text,
      "role": "spectator",
      "type": "text", // 🔥 EKLENDİ
    });

    chatController.clear();
    await _load();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final top = player(1);
    final bottom = player(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (topAvatarKey.currentContext == null ||
          bottomAvatarKey.currentContext == null) {
        return;
      }

      final topPos = _getAvatarWorldPosition(topAvatarKey);
      final bottomPos = _getAvatarWorldPosition(bottomAvatarKey);

      game.setAvatarPositions(topPos, bottomPos);
    });
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          /// MASA (FLAME)
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: GameWidget(game: game),
            ),
          ),

          /// HEADER
          if (table != null)
            Positioned(
              top: 10,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "${table!['league_id']}  •  ${table!['entry_coin']} coin",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    Row(
                      children: [
                        const Icon(
                          Icons.remove_red_eye,
                          color: Colors.white70,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          spectators.toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          /// ÜST OYUNCU
          if (top != null)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  if ((_avatarChatByUserId[top['user_id']?.toString()] ?? '')
                      .isNotEmpty)
                    _buildAvatarBubble(
                      _avatarChatByUserId[top['user_id']?.toString()]!,
                    ),
                  if ((_avatarChatByUserId[top['user_id']?.toString()] ?? '')
                      .isNotEmpty)
                    const SizedBox(height: 6),
                  avatar(top['users']['avatar_url'], key: topAvatarKey),
                  const SizedBox(height: 6),
                  Text(
                    top['users']['username'] ?? "",
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),

          /// ALT OYUNCU
          if (bottom != null)
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  if ((_avatarChatByUserId[bottom['user_id']?.toString()] ?? '')
                      .isNotEmpty)
                    _buildAvatarBubble(
                      _avatarChatByUserId[bottom['user_id']?.toString()]!,
                    ),
                  if ((_avatarChatByUserId[bottom['user_id']?.toString()] ?? '')
                      .isNotEmpty)
                    const SizedBox(height: 6),
                  avatar(bottom['users']['avatar_url'], key: bottomAvatarKey),
                  const SizedBox(height: 6),
                  Text(
                    bottom['users']['username'] ?? "",
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),

          /// CHAT BUTTON
          Positioned(
            right: 20,
            bottom: 20,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  chatOpen = !chatOpen;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          /// CLOSE BUTTON
          Positioned(
            left: 20,
            bottom: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),

          /// CHAT PANEL
          if (chatOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    chatOpen = false;
                  });
                },
                child: Container(
                  color: Colors.black.withOpacity(.55),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () {},

                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,

                        width: 360,
                        margin: const EdgeInsets.fromLTRB(0, 40, 12, 20),
                        padding: const EdgeInsets.all(12),

                        decoration: BoxDecoration(
                          color: const Color(0xEE0F141A),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x33FFFFFF)),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black87,
                              blurRadius: 30,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),

                        child: Column(
                          children: [
                            /// HEADER
                            Row(
                              children: [
                                const Icon(
                                  Icons.forum_rounded,
                                  color: Color(0xFFD4AF37),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "Masa Sohbeti",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () {
                                    setState(() => chatOpen = false);
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            /// 🔥 MESSAGE LIST
                            Expanded(
                              child: ListView.builder(
                                controller: _chatScrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                itemCount: messages.length,
                                itemBuilder: (_, i) {
                                  final m = messages[i];

                                  final mine =
                                      m['sender_id'] ==
                                      supabase.auth.currentUser?.id;

                                  final isVoice = m['type'] == 'voice';

                                  final username =
                                      m['users']?['username'] ?? "Oyuncu";

                                  return Align(
                                    alignment: mine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      padding: const EdgeInsets.all(10),
                                      constraints: const BoxConstraints(
                                        maxWidth: 240,
                                      ),
                                      decoration: BoxDecoration(
                                        color: mine
                                            ? const Color(0xFF2A3D1B)
                                            : const Color(0xFF1A222A),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: mine
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            username,
                                            style: const TextStyle(
                                              color: Color(0xFFD4AF37),
                                              fontSize: 11,
                                            ),
                                          ),
                                          const SizedBox(height: 4),

                                          isVoice
                                              ? _voiceBubble(m, mine)
                                              : Text(
                                                  m['content'] ?? '',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                            /// 🔥 PREVIEW
                            if (_showPreview && _previewPath != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A222A),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.play_arrow,
                                        color: Colors.white,
                                      ),
                                      onPressed: () async {
                                        if (!FeedbackSettingsService.soundEnabled) {
                                          await FeedbackSettingsService.triggerHaptic();
                                          return;
                                        }
                                        await _audioPlayer.setFilePath(
                                          _previewPath!,
                                        );
                                        await _audioPlayer.play();
                                        await FeedbackSettingsService.triggerHaptic();
                                      },
                                    ),
                                    Expanded(child: _waveform(false)),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                      ),
                                      onPressed: () async {
                                        await File(_previewPath!).delete();
                                        setState(() {
                                          _previewPath = null;
                                          _showPreview = false;
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.send,
                                        color: Colors.green,
                                      ),
                                      onPressed: () async {
                                        await sendVoiceMessage(_previewPath!);
                                        setState(() {
                                          _previewPath = null;
                                          _showPreview = false;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),

                            /// 🔥 QUICK CHAT
                            SizedBox(
                              height: 42,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: quickMessages.map((msg) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: GestureDetector(
                                      onTap: () {
                                        chatController.text = msg;
                                        sendMessage();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1A222A),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          msg,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),

                            const SizedBox(height: 8),

                            /// 🔥 INPUT + VOICE
                            Row(
                              children: [
                                /// 🎤 RECORD
                                Listener(
                                  onPointerDown: (_) async {
                                    _isPressing = true;

                                    await Future.delayed(
                                      const Duration(milliseconds: 250),
                                    );

                                    if (_isPressing) {
                                      await _startRecording();
                                    }
                                  },
                                  onPointerUp: (_) async {
                                    _isPressing = false;
                                    await _stopRecording(send: false);
                                  },
                                  child: _recordButton(),
                                ),

                                const SizedBox(width: 6),

                                /// TEXT
                                Expanded(
                                  child: TextField(
                                    controller: chatController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: "Mesaj yaz...",
                                      hintStyle: const TextStyle(
                                        color: Colors.white54,
                                      ),
                                      filled: true,
                                      fillColor: const Color(0x221A222A),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    onSubmitted: (_) => sendMessage(),
                                  ),
                                ),

                                const SizedBox(width: 6),

                                /// SEND
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD4AF37),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: IconButton(
                                    onPressed: sendMessage,
                                    icon: const Icon(
                                      Icons.send,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_showMessageBanner && _lastIncomingMessage != null)
            Positioned(top: 60, right: 12, width: 320, child: _buildMessageBanner()),
          if (_showFinishOverlay) Positioned.fill(child: _buildFinishOverlay()),
        ],
      ),
    );
  }

  Future<void> _playVoice(Map<String, dynamic> msg) async {
    try {
      final path = msg['voice_url'];
      if (path == null) return;
      if (!FeedbackSettingsService.soundEnabled) {
        await FeedbackSettingsService.triggerHaptic();
        return;
      }

      /// aynı mesaj → stop
      if (_playingMessageId == msg['id']) {
        await _audioPlayer.stop();
        setState(() => _playingMessageId = null);
        return;
      }

      /// yeni mesaj başlat
      final url = await supabase.storage
          .from('voice')
          .createSignedUrl(path, 60);

      await _audioPlayer.stop(); // 💥 önemli (önceki sesi kes)

      await _audioPlayer.setUrl(url);

      setState(() => _playingMessageId = msg['id']);

      await _audioPlayer.play();
      await FeedbackSettingsService.triggerHaptic();
    } catch (e) {
      debugPrint("VOICE PLAY ERROR: $e");
    }
  }

  Widget _buildAvatarBubble(String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF2D596), Color(0xFFE7BE6A)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xCC7A5A1F), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1D2A25),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBanner() {
    final msg = _lastIncomingMessage!;
    final name = (msg['users']?['username'] ?? 'İzleyici').toString();
    final text = (msg['content'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xEE223A32), Color(0xEE162720)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x99E3BB62)),
      ),
      child: Text(
        '$name: $text',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFEAF3EE),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildFinishOverlay() {
    return Container(
      color: const Color(0xB3000000),
      child: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF213A32), Color(0xFF132620)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xB3E3BB62), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'EL BİTTİ',
                style: TextStyle(
                  color: Color(0xFFF2D596),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_finishWinnerName kazandı',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isPlayerSender(String? senderId) {
    if (senderId == null) return false;
    return players.any((p) => p['user_id']?.toString() == senderId);
  }

  void _handleIncomingMessageEffects(Map<String, dynamic> msg) {
    final senderId = msg['sender_id']?.toString();
    if (senderId == null) return;
    final text = (msg['content'] ?? '').toString().trim();
    final role = (msg['role'] ?? '').toString();
    final mine = senderId == supabase.auth.currentUser?.id;

    if (_isPlayerSender(senderId) && text.isNotEmpty) {
      _avatarChatTimers[senderId]?.cancel();
      setState(() {
        _avatarChatByUserId[senderId] = text;
      });
      _avatarChatTimers[senderId] = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _avatarChatByUserId.remove(senderId);
        });
        _avatarChatTimers.remove(senderId);
      });
      return;
    }

    if (!mine && role == 'spectator') {
      setState(() {
        _lastIncomingMessage = msg;
        _showMessageBanner = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _showMessageBanner = false);
      });
    }
  }

  void _openFinishOverlay(String winnerName) {
    if (!mounted) return;
    setState(() {
      _finishWinnerName = winnerName;
      _showFinishOverlay = true;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _showFinishOverlay = false);
    });
  }

  Widget _voiceBubble(Map<String, dynamic> msg, bool mine) {
    final isPlaying = _playingMessageId == msg['id'];

    return Row(
      mainAxisSize: MainAxisSize.min, // ❗ önemli
      children: [
        /// ▶️ PLAY
        GestureDetector(
          onTap: () => _playVoice(msg),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPlaying
                  ? const Color(0xFFE7C06A)
                  : (mine ? Colors.white : Colors.black26),
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              size: 18,
              color: isPlaying
                  ? Colors.black
                  : (mine ? Colors.black : Colors.white),
            ),
          ),
        ),

        const SizedBox(width: 8),

        /// 🔊 WAVE
        SizedBox(
          width: 80, // ❗ sabit width
          child: Row(
            children: List.generate(12, (i) {
              final height = (i % 5 + 3).toDouble();

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                width: 3,
                height: height * 2,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.85),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        ),

        const SizedBox(width: 6),

        /// ⏱️ süre
        Text(
          "${msg['duration'] ?? 0}s",
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  Widget _waveform(bool playing) {
    return Row(
      children: List.generate(20, (i) {
        final baseHeight = (i % 5 + 3).toDouble();

        return AnimatedContainer(
          duration: Duration(milliseconds: 200 + (i * 20)),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: 3,
          height: playing ? baseHeight * 5 : baseHeight * 2,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.85),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Future<void> sendVoiceMessage(String filePath) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final file = File(filePath);

      if (!await file.exists()) return;

      /// 🆔 unique id
      final messageId = const Uuid().v4();

      /// 🔗 storage path (table bazlı)
      final storagePath = 'table/${widget.tableId}/$messageId.m4a';

      /// 📦 STORAGE UPLOAD
      await supabase.storage.from('voice').upload(storagePath, file);

      /// 🧾 DB INSERT
      await supabase.from('table_messages').insert({
        "table_id": widget.tableId,
        "sender_id": user.id,
        "role": "spectator", // veya player
        "content": "", // boş
        "type": "voice",
        "voice_url": storagePath,
        "duration": 5, // şimdilik sabit
      });

      /// 🧹 local temizle
      await file.delete();

      /// 🔄 refresh
      await _load();
      _scrollToBottom();
    } catch (e) {
      debugPrint("VOICE SEND ERROR: $e");
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    if (!await _recorder.hasPermission()) return;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${const Uuid().v4()}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );

    _recordPath = path;

    setState(() => _isRecording = true);

    _startTimer();

    /// 💥 EN KRİTİK (recorder warmup)
    _canStop = false;

    Future.delayed(const Duration(milliseconds: 300), () {
      _canStop = true;
    });
  }

  void _startTimer() {
    _recordSeconds = 0;

    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        _recordSeconds++;
      });
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_isRecording) return;

    if (!_canStop) return;

    final path = await _recorder.stop();

    _stopTimer();
    setState(() => _isRecording = false);

    if (path == null) return;

    final file = File(path);
    final size = await file.length();

    if (size < 8000) {
      await file.delete();
      return;
    }

    /// ❗ ARTIK GÖNDERMEYİZ
    setState(() {
      _previewPath = path;
      _showPreview = true;
    });
  }

  void _stopTimer() {
    _recordTimer?.cancel();
  }

  Widget _recordButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,

      height: _isRecording ? 54 : 44,
      width: _isRecording ? 54 : 44,

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),

        /// 🎨 BACKGROUND
        color: _isRecording ? Colors.redAccent : const Color(0xFF1E2A25),

        /// 💎 BORDER
        border: Border.all(
          color: _isRecording ? Colors.redAccent : const Color(0x3359A588),
          width: _isRecording ? 1.6 : 1,
        ),

        /// ✨ GLOW
        boxShadow: _isRecording
            ? [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(.7),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : [BoxShadow(color: Colors.black.withOpacity(.25), blurRadius: 6)],
      ),

      child: Center(
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: _isRecording ? 1.2 : 1,

          child: Icon(
            _isRecording ? Icons.mic : Icons.mic_none,
            size: _isRecording ? 26 : 22,
            color: _isRecording ? Colors.white : const Color(0xFFE7C06A),
          ),
        ),
      ),
    );
  }

  Vector2 _getAvatarWorldPosition(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Vector2.zero();

    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;

    final centerX = pos.dx + size.width / 2;
    final centerY = pos.dy + size.height / 2;

    // 🔥 Flutter → Flame dönüşüm
    final screenSize = MediaQuery.of(context).size;

    final scaleX = 1600 / screenSize.width;
    final scaleY = 900 / screenSize.height;

    return Vector2(centerX * scaleX, centerY * scaleY);
  }

  @override
  void dispose() {
    for (final t in _avatarChatTimers.values) {
      t.cancel();
    }
    _avatarChatTimers.clear();
    _chatScrollController.dispose();
    spectatorChannel.unsubscribe();
    _leaveSpectator();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_chatScrollController.hasClients) return;

    _chatScrollController.animateTo(
      _chatScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _joinSpectator() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from('table_spectators').upsert({
        'table_id': widget.tableId,
        'user_id': user.id,
      });
    } catch (e) {
      print("JOIN ERROR: $e");
    }
  }

  Future<void> _leaveSpectator() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('table_spectators')
          .delete()
          .eq('table_id', widget.tableId)
          .eq('user_id', user.id);
    } catch (e) {
      print("LEAVE ERROR: $e");
    }
  }
}
