import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/okey_game.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceCommandType {
  drawFromClosed,
  drawFromDiscard,
  discardTile,
  arrangeSerial,
  finishGame,
  unknown,
}

class ParsedVoiceCommand {
  final VoiceCommandType type;
  final TileColor? color;
  final int? value;

  const ParsedVoiceCommand({required this.type, this.color, this.value});
}

class VoiceCommandFeedback {
  final String message;
  final bool isError;

  const VoiceCommandFeedback({required this.message, this.isError = false});
}

class VoiceCommandService extends ChangeNotifier {
  final SpeechToText _speech = SpeechToText();
  Timer? _restartTimer;
  Timer? _watchdogTimer;
  bool _keepListening = false;
  String _lastExecutedTranscript = '';
  DateTime? _lastExecutedAt;

  bool _ready = false;
  bool _available = false;
  bool _isListening = false;
  bool _isExecuting = false;
  String _recognizedText = '';
  VoiceCommandFeedback? _feedback;

  bool get isReady => _ready;
  bool get isAvailable => _available;
  bool get isListening => _isListening;
  bool get isExecuting => _isExecuting;
  String get recognizedText => _recognizedText;
  VoiceCommandFeedback? get feedback => _feedback;

  Future<void> initialize() async {
    if (_ready) return;
    _available = await _speech.initialize();
    _ready = true;
    notifyListeners();
  }

  Future<void> toggleListening(OkeyGame game) async {
    if (_isListening) {
      await stopListening();
      return;
    }
    _keepListening = true;
    await startListening(game);
  }

  Future<void> startListening(OkeyGame game) async {
    if (_isExecuting) return;
    if (!_ready) {
      await initialize();
    }
    if (!_available) {
      _feedback = const VoiceCommandFeedback(
        message: 'Mikrofon/ses algılama hazır değil.',
        isError: true,
      );
      notifyListeners();
      return;
    }

    _recognizedText = '';
    _isListening = true;
    notifyListeners();

    await _speech.listen(
      localeId: 'tr_TR',
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.dictation,
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(minutes: 10),
      onResult: (result) async {
        _recognizedText = result.recognizedWords.trim();
        notifyListeners();
        if (_isExecuting) return;
        final parsed = _parse(_recognizedText);
        if (parsed.type == VoiceCommandType.unknown) return;
        if (!_canExecuteNow(_recognizedText)) return;

        _isExecuting = true;
        notifyListeners();
        await _executeTranscript(game, _recognizedText);
        _markExecuted(_recognizedText);
        _isExecuting = false;
        notifyListeners();
        if (_keepListening && !_speech.isListening) {
          _scheduleRestart(game);
        }
      },
    );

    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!_keepListening || _isExecuting) return;
      if (_speech.isListening) return;
      _isListening = false;
      notifyListeners();
      _scheduleRestart(game);
    });
  }

  Future<void> stopListening() async {
    _keepListening = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    if (_speech.isListening) {
      await _speech.stop();
    }
    if (_isListening) {
      _isListening = false;
      notifyListeners();
    }
  }

  void clearFeedback() {
    _feedback = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _keepListening = false;
    _restartTimer?.cancel();
    _watchdogTimer?.cancel();
    _speech.cancel();
    super.dispose();
  }

  Future<void> _executeTranscript(OkeyGame game, String transcript) async {
    final parsed = _parse(transcript);

    switch (parsed.type) {
      case VoiceCommandType.drawFromClosed:
        final ok = game.drawFromClosedPileByVoice();
        _feedback = VoiceCommandFeedback(
          message: ok ? 'Ortadan taş çekildi.' : 'Ortadan çekme şu an mümkün değil.',
          isError: !ok,
        );
        break;
      case VoiceCommandType.drawFromDiscard:
        final ok = game.takeFromDiscardByVoice();
        _feedback = VoiceCommandFeedback(
          message: ok ? 'Yandaki taş alındı.' : 'Yandan alma şu an mümkün değil.',
          isError: !ok,
        );
        break;
      case VoiceCommandType.arrangeSerial:
        final ok = game.arrangeSerialByVoice();
        _feedback = VoiceCommandFeedback(
          message: ok ? 'Seri dizildi.' : 'Şu an seri dizilemedi.',
          isError: !ok,
        );
        break;
      case VoiceCommandType.finishGame:
        final ok = await game.finishGameByVoice();
        _feedback = VoiceCommandFeedback(
          message: ok ? 'Oyun bitirme hamlesi yapıldı.' : 'Şu an bitirilemiyor.',
          isError: !ok,
        );
        break;
      case VoiceCommandType.discardTile:
        final color = parsed.color;
        final value = parsed.value;
        if (color == null || value == null) {
          _feedback = const VoiceCommandFeedback(
            message: 'Taş atma komutu anlaşılamadı.',
            isError: true,
          );
          break;
        }
        final ok = await game.discardTileByVoice(color: color, value: value);
        _feedback = VoiceCommandFeedback(
          message: ok
              ? '${_tileColorName(color)} $value atıldı.'
              : '${_tileColorName(color)} $value atılamadı.',
          isError: !ok,
        );
        break;
      case VoiceCommandType.unknown:
        _feedback = const VoiceCommandFeedback(
          message: 'Komut anlaşılmadı. Örn: "ortadan çek", "sarı 13 at".',
          isError: true,
        );
        break;
    }
    notifyListeners();
  }

  ParsedVoiceCommand _parse(String rawText) {
    final normalized = _normalize(rawText);
    if (normalized.isEmpty) {
      return const ParsedVoiceCommand(type: VoiceCommandType.unknown);
    }

    if (_matchesAny(normalized, const [
      'seri diz',
      'seri yap',
      'seriye diz',
      'diz serileri',
      'taslari seri diz',
      'taslari seriye diz',
    ])) {
      return const ParsedVoiceCommand(type: VoiceCommandType.arrangeSerial);
    }

    if (_matchesAny(normalized, const [
      'bitir',
      'oyunu bitir',
      'eli bitir',
      'bitir artik',
    ])) {
      return const ParsedVoiceCommand(type: VoiceCommandType.finishGame);
    }

    if (_matchesAny(normalized, const [
      'yandan al',
      'yandan cek',
      'yandan tas al',
      'yan tas al',
      'iskartadan al',
      'attan al',
      'yerden al sagdan',
    ])) {
      return const ParsedVoiceCommand(type: VoiceCommandType.drawFromDiscard);
    }

    if (_matchesAny(normalized, const [
      'ortadan cek',
      'ortadan tas cek',
      'ortadan al',
      'desteden cek',
      'kapalidan cek',
      'yerden cek',
      'tas cek',
    ])) {
      return const ParsedVoiceCommand(type: VoiceCommandType.drawFromClosed);
    }

    // Short fallback: when user only says "çek", prefer closed-pile draw.
    if (normalized == 'cek' || normalized == 'tas cek') {
      return const ParsedVoiceCommand(type: VoiceCommandType.drawFromClosed);
    }

    final hasDiscardVerb =
        normalized.contains(' at') ||
        normalized.startsWith('at ') ||
        normalized.contains(' birak') ||
        normalized.contains(' ver');
    if (hasDiscardVerb) {
      final color = _extractColor(normalized);
      final value = _extractNumber(normalized);
      if (color != null && value != null) {
        return ParsedVoiceCommand(
          type: VoiceCommandType.discardTile,
          color: color,
          value: value,
        );
      }
    }

    return const ParsedVoiceCommand(type: VoiceCommandType.unknown);
  }

  bool _matchesAny(String text, List<String> patterns) {
    for (final p in patterns) {
      if (text == p || text.contains(p)) return true;
    }
    return false;
  }

  String _normalize(String input) {
    final lower = input.toLowerCase().trim();
    if (lower.isEmpty) return '';
    return lower
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  TileColor? _extractColor(String normalized) {
    if (normalized.contains('kirmizi')) {
      return TileColor.red;
    }
    if (normalized.contains('mavi')) {
      return TileColor.blue;
    }
    if (normalized.contains('siyah')) {
      return TileColor.black;
    }
    if (normalized.contains('sari')) {
      return TileColor.yellow;
    }
    return null;
  }

  int? _extractNumber(String normalized) {
    final match = RegExp(r'\b(1[0-3]|[1-9])\b').firstMatch(normalized);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    const words = <String, int>{
      'bir': 1,
      'iki': 2,
      'uc': 3,
      'dort': 4,
      'bes': 5,
      'alti': 6,
      'yedi': 7,
      'sekiz': 8,
      'dokuz': 9,
      'on': 10,
      'on bir': 11,
      'on iki': 12,
      'on uc': 13,
    };

    for (final entry in words.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  String _tileColorName(TileColor color) {
    switch (color) {
      case TileColor.red:
        return 'Kırmızı';
      case TileColor.blue:
        return 'Mavi';
      case TileColor.black:
        return 'Siyah';
      case TileColor.yellow:
        return 'Sarı';
    }
  }

  bool _canExecuteNow(String transcript) {
    final now = DateTime.now();
    final normalized = _normalize(transcript);
    final last = _lastExecutedAt;
    if (last == null) return true;
    final tooSoon = now.difference(last).inMilliseconds < 800;
    if (!tooSoon) return true;
    return normalized != _lastExecutedTranscript;
  }

  void _markExecuted(String transcript) {
    _lastExecutedTranscript = _normalize(transcript);
    _lastExecutedAt = DateTime.now();
  }

  void _scheduleRestart(OkeyGame game) {
    if (!_keepListening) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 120), () async {
      if (!_keepListening || _isExecuting || _speech.isListening) return;
      await startListening(game);
    });
  }
}
