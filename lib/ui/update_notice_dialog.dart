import 'package:flutter/material.dart';
import 'lobby/lobby_metal_surface.dart';

class UpdateNoticeDialog extends StatelessWidget {
  final String? version;
  final String actionLabel;
  const UpdateNoticeDialog({
    super.key,
    this.version,
    this.actionLabel = 'Güncelle',
  });

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: LobbyMetalSurface(
        radius: 22,
        surfaceOpacity: 2.6,
        metal: const Color(0xFFE5C585),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF3B5945), Color(0xFF101E1A)],
                          ),
                          border: Border.all(color: const Color(0xFFE5C585)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x55000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.system_update_alt_rounded,
                          size: 30,
                          color: Color(0xFFF3DCAC),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'YENİ SÜRÜM HAZIR',
                              style: TextStyle(
                                color: Color(0xFFE5C585),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .7,
                              ),
                            ),
                            if (version != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Okeyix $version',
                                style: const TextStyle(
                                  color: Color(0xFFF2E6CD),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            const Text(
                              'Yeni özellikler ve iyileştirmeler seni bekliyor. Okeyix’i güncelleyerek masaya dön.',
                              style: TextStyle(
                                color: Color(0xFFD2DED5),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('update-later'),
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        foregroundColor: const Color(0xFFD2DED5),
                        side: const BorderSide(color: Color(0x667E937F)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Daha sonra'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      key: const ValueKey('update-now'),
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        backgroundColor: const Color(0xFFE5C585),
                        foregroundColor: const Color(0xFF1B281E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        actionLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800),
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
  );
}
