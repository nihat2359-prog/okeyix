import 'package:flutter/material.dart';
import 'lobby/lobby_metal_surface.dart';

class PlayerNameReminderResult {
  final bool edit, neverAgain;
  const PlayerNameReminderResult({
    required this.edit,
    required this.neverAgain,
  });
}

class PlayerNameReminderDialog extends StatefulWidget {
  const PlayerNameReminderDialog({super.key});
  @override
  State<PlayerNameReminderDialog> createState() =>
      _PlayerNameReminderDialogState();
}

class _PlayerNameReminderDialogState extends State<PlayerNameReminderDialog> {
  bool _neverAgain = false;
  void _close(bool edit) => Navigator.pop(
    context,
    PlayerNameReminderResult(edit: edit, neverAgain: _neverAgain),
  );
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: LobbyMetalSurface(
          radius: 22,
          surfaceOpacity: 2.5,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFFE5C585),
                        size: 30,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Masalarda kendi adınla tanın',
                          style: TextStyle(
                            color: Color(0xFFFFEAC5),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sana özel oyuncu adını seç. Seçtiğin adı başka bir oyuncu kullanamaz. '
                    'Gerçek adını kullanman gerekmez.',
                    style: TextStyle(color: Color(0xFFD0D3D9), height: 1.4),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: const Color(0xFFE5C585),
                    checkColor: Colors.black,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Bir daha gösterme',
                      style: TextStyle(color: Color(0xFFC2C6CC), fontSize: 12),
                    ),
                    value: _neverAgain,
                    onChanged: (v) => setState(() => _neverAgain = v ?? false),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => _close(false),
                          child: const Text(
                            'Daha sonra',
                            style: TextStyle(color: Color(0xFFC2C6CC)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE5C585),
                            foregroundColor: const Color(0xFF252019),
                          ),
                          onPressed: () => _close(true),
                          icon: const Icon(Icons.edit_rounded, size: 17),
                          label: const Text('Adımı seç'),
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
  );
}
