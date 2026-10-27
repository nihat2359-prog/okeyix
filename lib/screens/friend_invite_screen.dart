import 'package:okeyix/core/format.dart';
import 'package:flutter/material.dart';
import '../ui/lobby/lobby_metal_surface.dart';
import 'package:flutter/services.dart';
import 'package:okeyix/services/friend_invite_service.dart';
import 'package:okeyix/ui/invite_strings.dart';
import 'package:okeyix/ui/lobby/lobby_avatar.dart';

const _gold = Color(0xFFE8CA8C);

class FriendInviteScreen extends StatefulWidget {
  const FriendInviteScreen({super.key, this.service});
  final FriendInviteService? service;
  @override
  State<FriendInviteScreen> createState() => _FriendInviteScreenState();
}

class _FriendInviteScreenState extends State<FriendInviteScreen>
    with WidgetsBindingObserver {
  late final FriendInviteService _service =
      widget.service ?? FriendInviteService();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _shareKey = GlobalKey();
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true,
      _failed = false,
      _redeeming = false,
      _sharing = false,
      _more = false;
  bool _paging = false;
  String? _status;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait<dynamic>([
        _service.dashboard(),
        _service.friends(),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = results[0] as Map<String, dynamic>;
        _friends = results[1] as List<Map<String, dynamic>>;
        _more = _friends.length == 30;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _next() async {
    if (_paging || _loading || _friends.isEmpty) return;
    final generation = _generation;
    setState(() => _paging = true);
    try {
      final page = await _service.friends(before: _friends.last);
      if (!mounted || generation != _generation) return;
      setState(() {
        _friends.addAll(page);
        _more = page.length == 30;
      });
    } catch (_) {
      if (mounted) _message(InviteStrings.of(context).status('error'));
    } finally {
      if (mounted) setState(() => _paging = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  Future<void> _redeem() async {
    if (_redeeming || _code.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _redeeming = true;
      _status = null;
    });
    try {
      final result = await _service.redeem(_code.text);
      if (!mounted) return;
      setState(() => _status = result);
      if (result == 'accepted' || result == 'already_used') await _load();
    } catch (_) {
      if (mounted) setState(() => _status = 'error');
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  Future<void> _share(InviteStrings s) async {
    if (_sharing || _data == null) return;
    final box = _shareKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    try {
      await _service.shareWhatsApp(
        s.shareMessage(_data!['code'] as String),
        origin,
      );
    } catch (_) {
      if (mounted) {
        _message(
          s.t(
            'WhatsApp açılamadı. Kodu kopyalayarak gönderebilirsin.',
            'Could not open WhatsApp. You can copy and send your code.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = InviteStrings.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: const Color(0xFF10161E),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/lobby/lobby.png',
              fit: BoxFit.cover,
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x66151B22), Color(0x99101822)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) => Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: bounds.maxWidth.clamp(620.0, 1100.0),
                    height: bounds.maxHeight.clamp(
                      keyboard ? 215.0 : 300.0,
                      480.0,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 42,
                            child: Row(
                              children: [
                                Image.asset(
                                  'assets/images/logo/okeyix_logo.png',
                                  width: 88,
                                  height: 35,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    s.title,
                                    style: const TextStyle(
                                      color: _gold,
                                      fontSize: 12,
                                      letterSpacing: 1.3,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: s.t('Yenile', 'Refresh'),
                                  onPressed: _loading ? null : _load,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    color: _gold,
                                    size: 20,
                                  ),
                                ),
                                IconButton(
                                  tooltip: s.t('Kapat', 'Close'),
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white70,
                                    size: 21,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _loading && _data == null
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      color: _gold,
                                    ),
                                  )
                                : _failed
                                ? Center(
                                    child: _action(
                                      label: s.t('Tekrar dene', 'Retry'),
                                      icon: Icons.refresh,
                                      onTap: _load,
                                    ),
                                  )
                                : keyboard
                                ? Center(
                                    child: SizedBox(
                                      width: 460,
                                      child: _redeemPanel(s),
                                    ),
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(flex: 5, child: _invitation(s)),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        flex: 5,
                                        child: Column(
                                          children: [
                                            Expanded(
                                              flex: 5,
                                              child: _redeemPanel(s),
                                            ),
                                            const SizedBox(height: 10),
                                            Expanded(
                                              flex: 4,
                                              child: _friendsPanel(s),
                                            ),
                                          ],
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _invitation(InviteStrings s) => LobbyMetalSurface(
    radius: 22,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.t('BİRLİKTE KAZANIN', 'WIN TOGETHER'),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                    const Text(
                      '1 Mn COIN',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 44,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Color(0x665C4917), blurRadius: 18),
                        ],
                      ),
                    ),
                    Text(
                      s.t(
                        'Sana da, arkadaşına da.',
                        'For you and your friend.',
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Image.asset(
                  'assets/images/coins/coins_small.png',
                  width: 56,
                  height: 56,
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          s.t(
            'Arkadaşın 10 gerçek oyunculu el tamamlasın.',
            'Your friend completes 10 hands with real players.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 10),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: const Color(0x66141B24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x446D7254)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t('DAVET KODUN', 'YOUR INVITE CODE'),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 8,
                        letterSpacing: 1.2,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SelectableText(
                        _data?['code'] as String? ?? '—',
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 20,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: s.t('Kodu Kopyala', 'Copy code'),
                onPressed: _data == null
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: _data!['code'] as String),
                        );
                        if (mounted) {
                          _message(
                            s.t(
                              'Davet kodu kopyalandı.',
                              'Invite code copied.',
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.copy_rounded, size: 18, color: _gold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _action(
          key: _shareKey,
          label: _sharing
              ? s.t('Açılıyor…', 'Opening…')
              : s.t('WhatsApp ile Davet Gönder', 'Invite via WhatsApp'),
          icon: Icons.send_rounded,
          primary: true,
          onTap: _sharing ? null : () => _share(s),
        ),
      ],
    ),
  );

  Widget _redeemPanel(InviteStrings s) {
    final redemption = _data?['redemption'] as Map?;
    final progress = (redemption?['progress'] as num?)?.toInt() ?? 0;
    final rewarded = redemption?['rewarded'] == true;
    return _panel(
      s.t('DAVET KODU KULLAN', 'REDEEM AN INVITE CODE'),
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (redemption == null)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('invite-code-input'),
                    focusNode: _codeFocus,
                    controller: _code,
                    enabled: !_redeeming,
                    cursorColor: _gold,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 12,
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                    ],
                    onSubmitted: (_) => _redeem(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: s.t('Arkadaşının kodu', 'Friend’s code'),
                      hintStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0x77121922),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0x556D7254)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _gold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                _action(
                  label: _redeeming
                      ? s.t('Bekle…', 'Wait…')
                      : s.t('Kodu Doğrula', 'Verify code'),
                  onTap: _redeeming ? null : _redeem,
                ),
              ],
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.t('Davet ilerlemem', 'My invitation progress'),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
                Text(
                  '$progress / 10',
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress / 10,
              color: _gold,
              backgroundColor: Colors.white12,
              minHeight: 5,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(height: 6),
            Text(
              rewarded
                  ? s.t(
                      'Tamamlandı · 1 Mn coin kazanıldı!',
                      'Completed · 1 Mn coins received!',
                    )
                  : s.t(
                      '$progress / 10 el tamamlandı',
                      '$progress / 10 hands completed',
                    ),
              style: const TextStyle(color: _gold, fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(
              '${s.t('Kullanılan kod', 'Redeemed code')}: ${redemption['code']}',
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            ),
          ],
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                s.status(_status!),
                maxLines: 2,
                style: TextStyle(
                  color: _status == 'accepted'
                      ? _gold
                      : const Color(0xFFFFB6A1),
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _friendsPanel(InviteStrings s) => _panel(
    s.t('DAVETLERİM', 'MY INVITATIONS'),
    Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Expanded(
              child: _summary(
                s.t('Toplam', 'Invited'),
                '${_data?['total_invites'] ?? 0}',
              ),
            ),
            Expanded(
              child: _summary(
                s.t('Başarılı', 'Successful'),
                '${_data?['successful_invites'] ?? 0}',
              ),
            ),
            Expanded(
              child: _summary(
                s.t('Coin', 'Coins'),
                _coin(_data?['earned_coin']),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _action(
          label: s.t('Davet ettiğim arkadaşlar', 'Friends I invited'),
          icon: Icons.chevron_right_rounded,
          onTap: () => _showFriends(s),
        ),
      ],
    ),
  );

  String _coin(dynamic value) => Format.balance((value as num?) ?? 0);

  Widget _summary(String label, String value) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: _gold,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
    ],
  );

  Widget _panel(String title, Widget content) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0x8818202A),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _gold.withValues(alpha: .23)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _gold,
            fontSize: 9,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) => FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(width: bounds.maxWidth, child: content),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _action({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    bool primary = false,
  }) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    child: Opacity(
      opacity: onTap == null ? .45 : 1,
      child: Container(
        key: key,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: LinearGradient(
            colors: primary
                ? const [Color(0xFFF3DBA5), Color(0xFFB99A58)]
                : const [Color(0x88303943), Color(0x99101822)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: primary ? const Color(0xFFFFE8AF) : const Color(0x776D7254),
          ),
          boxShadow: [
            BoxShadow(
              color: primary
                  ? const Color(0x224D3710)
                  : const Color(0x44000000),
              blurRadius: 9,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 16,
                      color: primary ? const Color(0xFF17261E) : _gold,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: primary ? const Color(0xFF17261E) : _gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
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
  );

  Future<void> _showFriends(InviteStrings s) => _dialog(
    s.t('Davet ettiğim arkadaşlar', 'Friends I invited'),
    StatefulBuilder(
      builder: (context, local) => _friends.isEmpty
          ? Center(
              child: Text(
                s.t(
                  'İlk davetini gönder, birlikte kazanın!',
                  'Send your first invitation and win together!',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            )
          : ListView.builder(
              itemCount: _friends.length + (_more ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _friends.length) {
                  return _action(
                    label: s.t('Daha fazla göster', 'Load more'),
                    onTap: _paging
                        ? null
                        : () async {
                            final request = _next();
                            local(() {});
                            await request;
                            if (context.mounted) local(() {});
                          },
                  );
                }
                final f = _friends[index];
                return ListTile(
                  leading: ClipOval(
                    child: LobbyAvatar(
                      username: f['username'] as String,
                      avatarUrl: f['avatar_url'] as String?,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    f['username'] as String,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${f['progress']} / 10 · ${f['rewarded'] == true ? s.t('Ödül kazanıldı', 'Reward earned') : s.t('Ödül bekleniyor', 'Reward pending')}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: Text(
                    '${_coin(f['earned_coin'])} coin',
                    style: const TextStyle(color: _gold, fontSize: 12),
                  ),
                );
              },
            ),
    ),
  );

  Future<void> _dialog(String title, Widget body) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: const Color(0xC018202A),
      insetPadding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x887D754F)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 360),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: InviteStrings.of(context).t('Kapat', 'Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: _gold),
                  ),
                ],
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    ),
  );
}
