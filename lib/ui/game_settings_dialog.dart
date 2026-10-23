import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/feedback_settings_service.dart';
import '../services/tile_theme_service.dart';
import '../services/user_state.dart';
import 'lobby/lobby_utility_scenes.dart';
import 'tile_themes_dialog.dart';

/// Reuses the lobby settings presentation and its existing preference stores.
class GameSettingsDialog extends StatefulWidget {
  final bool initialInvites;
  final Future<void> Function(bool) saveInvites;
  const GameSettingsDialog({
    super.key,
    required this.initialInvites,
    required this.saveInvites,
  });
  @override
  State<GameSettingsDialog> createState() => _GameSettingsDialogState();
}

class _GameSettingsDialogState extends State<GameSettingsDialog> {
  late bool _invites = widget.initialInvites;

  Future<void> _chooseTheme() async {
    final selected = await showTileThemes(context, closeOnSelect: true);
    if (selected != null &&
        mounted &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _save(Future<void> Function() operation) async {
    try {
      await operation();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ayar kaydedilemedi. Tekrar dene.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => GameSettingsScene(
    sound: FeedbackSettingsService.soundEnabled,
    vibration: FeedbackSettingsService.vibrationEnabled,
    colorBlind: UserState.colorBlindMode,
    invites: _invites,
    showAccountActions: false,
    onTileThemes: _chooseTheme,
    onClose: () => Navigator.of(context).pop(),
    onDelete: () {},
    onSound: (value) =>
        _save(() => FeedbackSettingsService.setSoundEnabled(value)),
    onVibration: (value) =>
        _save(() => FeedbackSettingsService.setVibrationEnabled(value)),
    onColorBlind: (value) => _save(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool('color_blind_mode', value)) {
        throw StateError('Preference write failed');
      }
      UserState.colorBlindMode = value;
      TileThemeService.selected.refreshPresentation();
    }),
    onInvites: (value) => _save(() async {
      await widget.saveInvites(value);
      _invites = value;
    }),
  );
}
