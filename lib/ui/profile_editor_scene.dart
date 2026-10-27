import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'lobby/lobby_metal_surface.dart';

/// Stateless game presentation; the existing dialog owns all account operations.
class ProfileEditorScene extends StatelessWidget {
  final Widget avatar;
  final TextEditingController username;
  final bool forceComplete, saving, asPage;
  final bool focusUsername;
  final String renameInfo, costInfo;
  final String? error;
  final VoidCallback onAvatar, onPhoto, onSave, onClose;
  const ProfileEditorScene({
    super.key,
    required this.avatar,
    required this.username,
    required this.renameInfo,
    required this.costInfo,
    required this.onAvatar,
    required this.onPhoto,
    required this.onSave,
    required this.onClose,
    this.forceComplete = false,
    this.focusUsername = false,
    this.saving = false,
    this.asPage = false,
    this.error,
  });

  static const gold = Color(0xFFE5C585);

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final panel = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 400),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final height = math.min(bounds.maxHeight, 400.0);
          final compact = height < 290;
          return SizedBox(
            height: height,
            child: Material(
              color: const Color(0x80141B23),
              borderRadius: BorderRadius.circular(24),
              child: LobbyMetalSurface(
                radius: 24,
                surfaceOpacity: 2.5,
                child: CustomPaint(
                  painter: const _IdentityFrame(),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(18, compact ? 8 : 14, 18, 12),
                    child: Column(
                      children: [
                        SizedBox(
                          height: compact ? 40 : 50,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.workspace_premium_outlined,
                                color: gold,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'OYUNCU KİMLİĞİ',
                                        style: TextStyle(
                                          color: gold,
                                          fontSize: 9,
                                          letterSpacing: 2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        forceComplete
                                            ? 'Masada yerini al'
                                            : 'Profili Düzenle',
                                        style: const TextStyle(
                                          color: Color(0xFFF4E9D5),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (!forceComplete)
                                IconButton(
                                  key: const ValueKey('profile-close'),
                                  tooltip: 'Kapat',
                                  onPressed: onClose,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFFC3C7CE),
                                    size: 22,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Row(
                            children: [
                              if (!keyboard) ...[
                                Expanded(
                                  flex: 4,
                                  child: LayoutBuilder(
                                    builder: (context, space) {
                                      final portraitSize =
                                          (space.maxHeight - 56).clamp(
                                            48.0,
                                            144.0,
                                          );
                                      return SingleChildScrollView(
                                        child: Column(
                                          children: [
                                            SizedBox(
                                              width: portraitSize,
                                              height: portraitSize,
                                              child: CustomPaint(
                                                painter:
                                                    const _AvatarMedallion(),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    7,
                                                  ),
                                                  child: ClipOval(
                                                    child: avatar,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _action(
                                                    'Avatar Seç',
                                                    Icons.grid_view_rounded,
                                                    onAvatar,
                                                  ),
                                                ),
                                                if (!forceComplete) ...[
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: _action(
                                                      'Fotoğraf',
                                                      Icons
                                                          .photo_camera_outlined,
                                                      onPhoto,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 24),
                              ],
                              Expanded(
                                flex: 5,
                                child: SingleChildScrollView(
                                  key: const ValueKey('profile-edit-content'),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        forceComplete
                                            ? 'OYUNA HAZIRSIN'
                                            : 'MASADAKİ ADIN',
                                        style: const TextStyle(
                                          color: gold,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      if (forceComplete)
                                        const Text(
                                          'Avatarını seç; sana özel, benzersiz bir oyuncu adı oluşturulsun.',
                                          style: TextStyle(
                                            color: Color(0xFFE3E6EC),
                                            fontSize: 14,
                                            height: 1.45,
                                          ),
                                        )
                                      else
                                        TextField(
                                          key: const ValueKey(
                                            'profile-username',
                                          ),
                                          controller: username,
                                          autofocus: focusUsername,
                                          maxLength: 20,
                                          scrollPadding: const EdgeInsets.all(
                                            12,
                                          ),
                                          style: const TextStyle(
                                            color: Color(0xFFFFEBC4),
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          cursorColor: gold,
                                          decoration: const InputDecoration(
                                            counterText: '',
                                            hintText: 'Oyuncu adın',
                                            hintStyle: TextStyle(
                                              color: Color(0xFF777E89),
                                            ),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 12,
                                                ),
                                            enabledBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                color: Color(0x997E704E),
                                              ),
                                            ),
                                            focusedBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                color: gold,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      Text(
                                        forceComplete
                                            ? 'Kimliğini daha sonra profilinden düzenleyebilirsin.'
                                            : renameInfo,
                                        style: const TextStyle(
                                          color: Color(0xFFAEB6C4),
                                          fontSize: 11,
                                          height: 1.45,
                                        ),
                                      ),
                                      if (error != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          error!,
                                          key: const ValueKey('profile-error'),
                                          style: const TextStyle(
                                            color: Color(0xFFF2A59B),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 46,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.toll_rounded,
                                color: gold,
                                size: 16,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    costInfo,
                                    style: const TextStyle(
                                      color: Color(0xFFBAC1CB),
                                      fontSize: 10,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: math.min(bounds.maxWidth * .32, 160),
                                child: _action(
                                  saving ? 'Kaydediliyor...' : 'Kaydet',
                                  saving
                                      ? Icons.hourglass_top_rounded
                                      : Icons.check_rounded,
                                  onSave,
                                  primary: true,
                                  enabled: !saving,
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
          );
        },
      ),
    );
    if (asPage) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A1018),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(child: panel),
          ),
        ),
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: panel,
    );
  }

  Widget _action(
    String label,
    IconData icon,
    VoidCallback callback, {
    bool primary = false,
    bool enabled = true,
  }) => Semantics(
    button: true,
    enabled: enabled,
    label: label,
    child: SizedBox(
      height: primary ? 46 : 40,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: primary
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: enabled
                        ? const [Color(0xFFF3DBA3), Color(0xFFC69A50)]
                        : const [Color(0xFF676452), Color(0xFF474638)],
                  )
                : null,
            border: Border.all(
              color: primary
                  ? const Color(0xFFCFAE70)
                  : const Color(0x557D8996),
              width: .8,
            ),
          ),
          child: InkWell(
            key: ValueKey('profile-$label'),
            onTap: enabled ? callback : null,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: primary ? const Color(0xFF35270F) : gold,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: primary
                              ? const Color(0xFF35270F)
                              : const Color(0xFFDDE1E8),
                          fontSize: primary ? 13 : 11,
                          fontWeight: FontWeight.w700,
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

class _AvatarMedallion extends CustomPainter {
  const _AvatarMedallion();
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide / 2;
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF8E7B5),
            Color(0xFF9C7538),
            Color(0xFF5C4527),
            Color(0xFFE9CA86),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(c, r - 4, Paint()..color = const Color(0xFF0A121B));
    canvas.drawCircle(
      c,
      r - 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = const Color(0xFF8D774C),
    );
  }

  @override
  bool shouldRepaint(covariant _AvatarMedallion oldDelegate) => false;
}

class _IdentityFrame extends CustomPainter {
  const _IdentityFrame();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x99D3B575);
    canvas.drawPath(
      Path()
        ..moveTo(12, 34)
        ..lineTo(12, 24)
        ..quadraticBezierTo(12, 12, 24, 12)
        ..lineTo(34, 12),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width - 34, size.height - 12)
        ..lineTo(size.width - 24, size.height - 12)
        ..quadraticBezierTo(
          size.width - 12,
          size.height - 12,
          size.width - 12,
          size.height - 24,
        )
        ..lineTo(size.width - 12, size.height - 34),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _IdentityFrame oldDelegate) => false;
}
