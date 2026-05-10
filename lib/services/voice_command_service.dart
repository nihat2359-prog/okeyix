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
  Timer? _resultDebounceTimer;

  bool _keepListening = false;
  String _lastExecutedTranscript = '';
  String _lastExecutedCommandKey = '';
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
  bool get isSessionActive => _keepListening;
  String get recognizedText => _recognizedText;
  VoiceCommandFeedback? get feedback => _feedback;

  Future<void> initialize() async {
    if (_ready) return;

    _available = await _speech.initialize(
      onStatus: (status) {
        final s = status.toLowerCase();
        if (_keepListening && (s.contains('notlistening') || s == 'done')) {
          _isListening = false;
          notifyListeners();
        }
      },
      onError: (_) {
        if (_keepListening) {
          _isListening = false;
          notifyListeners();
        }
      },
    );

    _ready = true;
    notifyListeners();
  }

  Future<void> toggleListening(OkeyGame game) async {
    if (_keepListening || _isListening) {
      await stopListening();
      return;
    }
    _keepListening = true;
    _feedback = null;
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

        final normalizedInput = _normalizeIntentText(_normalize(_recognizedText));
        debugPrint('[VOICE] heard="$_recognizedText" normalized="$normalizedInput" final=${result.finalResult}');

        if (_containsBabosIntent(normalizedInput)) {
          _feedback = const VoiceCommandFeedback(message: 'Canımsın');
          notifyListeners();
          return;
        }

        final parsed = _parse(_recognizedText);
        debugPrint('[VOICE] parsed=${parsed.type} color=${parsed.color} value=${parsed.value}');
        if (parsed.type == VoiceCommandType.unknown) return;

        // Fast path: do not wait for final sentence on fast in-turn commands.
        final isFastDiscard = parsed.type == VoiceCommandType.discardTile &&
            parsed.color != null &&
            parsed.value != null;
        final isFastDraw = parsed.type == VoiceCommandType.drawFromClosed ||
            parsed.type == VoiceCommandType.drawFromDiscard;
        if (isFastDiscard || isFastDraw) {
          _resultDebounceTimer?.cancel();
          await _tryExecuteTranscript(game, _recognizedText);
          if (_keepListening && !_speech.isListening) {
            _scheduleRestart(game);
          }
          return;
        }

        if (result.finalResult) {
          _resultDebounceTimer?.cancel();
          await _tryExecuteTranscript(game, _recognizedText);
          if (_keepListening && !_speech.isListening) {
            _scheduleRestart(game);
          }
          return;
        }

        _resultDebounceTimer?.cancel();
        _resultDebounceTimer = Timer(const Duration(milliseconds: 280), () async {
          if (!_keepListening || _isExecuting) return;
          await _tryExecuteTranscript(game, _recognizedText);
        });
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
    _resultDebounceTimer?.cancel();
    _resultDebounceTimer = null;
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
    _resultDebounceTimer?.cancel();
    _speech.cancel();
    super.dispose();
  }

  Future<void> _tryExecuteTranscript(OkeyGame game, String transcript) async {
    if (_isExecuting) return;
    final parsed = _parse(transcript);
    if (parsed.type == VoiceCommandType.unknown) {
      debugPrint('[VOICE] skip unknown transcript="$transcript"');
      return;
    }
    if (!_canExecuteNow(transcript, parsed)) {
      debugPrint('[VOICE] dedup blocked transcript="$transcript"');
      return;
    }

    _isExecuting = true;
    notifyListeners();
    await _executeTranscript(game, transcript);
    _markExecuted(transcript, parsed);
    if (_feedback == null) {
      // Do not keep repeating successful command text on HUD.
      _recognizedText = '';
    }
    _isExecuting = false;
    notifyListeners();
  }

  Future<void> _executeTranscript(OkeyGame game, String transcript) async {
    final parsed = _parse(transcript);

    switch (parsed.type) {
      case VoiceCommandType.drawFromClosed:
        final ok = game.drawFromClosedPileByVoice();
        debugPrint('[VOICE] action=drawFromClosed ok=$ok');
        _feedback = ok
            ? null
            : const VoiceCommandFeedback(
                message: 'Ortadan çekme şu an mümkün değil.',
                isError: true,
              );
        break;
      case VoiceCommandType.drawFromDiscard:
        final ok = game.takeFromDiscardByVoice();
        debugPrint('[VOICE] action=drawFromDiscard ok=$ok');
        _feedback = ok
            ? null
            : const VoiceCommandFeedback(
                message: 'Yandan alma şu an mümkün değil.',
                isError: true,
              );
        break;
      case VoiceCommandType.arrangeSerial:
        final ok = game.arrangeSerialByVoice();
        debugPrint('[VOICE] action=arrangeSerial ok=$ok');
        _feedback = ok
            ? null
            : const VoiceCommandFeedback(
                message: 'Şu an seri dizilemedi.',
                isError: true,
              );
        break;
      case VoiceCommandType.finishGame:
        final ok = await game.finishGameByVoice();
        debugPrint('[VOICE] action=finishGame ok=$ok');
        _feedback = ok
            ? null
            : const VoiceCommandFeedback(
                message: 'Şu an bitirilemiyor.',
                isError: true,
              );
        break;
      case VoiceCommandType.discardTile:
        final color = parsed.color;
        final value = parsed.value;
        if (color == null || value == null) {
          debugPrint('[VOICE] action=discardTile invalid args color=$color value=$value');
          _feedback = const VoiceCommandFeedback(
            message: 'Taş atma komutu anlaşılamadı.',
            isError: true,
          );
          break;
        }
        final ok = await game.discardTileByVoice(color: color, value: value);
        debugPrint('[VOICE] action=discardTile color=$color value=$value ok=$ok');
        _feedback = ok
            ? null
            : VoiceCommandFeedback(
                message: '${_tileColorName(color)} $value atılamadı.',
                isError: true,
              );
        break;
      case VoiceCommandType.unknown:
        _feedback = const VoiceCommandFeedback(
          message: 'Komut anlaşılamadı. Örn: "ortadan çek", "sarı 13 at".',
          isError: true,
        );
        break;
    }
    notifyListeners();
  }

  ParsedVoiceCommand _parse(String rawText) {
    final normalized = _normalizeIntentText(_normalize(rawText));
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
      'ortadan al da',
      'ortadan alda',
      'desteden cek',
      'kapalidan cek',
      'yerden cek',
      'tas cek',
    ])) {
      return const ParsedVoiceCommand(type: VoiceCommandType.drawFromClosed);
    }

    if (normalized == 'cek' || normalized == 'tas cek') {
      return const ParsedVoiceCommand(type: VoiceCommandType.drawFromClosed);
    }

    // Broad intent fallback:
    // if sentence contains "ortadan" -> draw from closed,
    // if sentence contains "yan/yandan" -> draw from discard.
    if (normalized.contains('ortadan')) {
      return const ParsedVoiceCommand(type: VoiceCommandType.drawFromClosed);
    }
    if (normalized.contains('yandan') ||
        normalized.contains(' yandan ') ||
        normalized.startsWith('yan ') ||
        normalized.contains(' yan ')) {
      return const ParsedVoiceCommand(type: VoiceCommandType.drawFromDiscard);
    }

    // If "ortadan" is detected alone, treat as closed-pile draw intent.
    if (normalized == 'ortadan' ||
        normalized.startsWith('ortadan ') ||
        normalized.contains(' ortadan ')) {
      return const ParsedVoiceCommand(type: VoiceCommandType.drawFromClosed);
    }

    // If "yandan" is detected alone, treat as discard-pile draw intent.
    if (normalized == 'yandan' ||
        normalized.startsWith('yandan ') ||
        normalized.contains(' yandan ')) {
      return const ParsedVoiceCommand(type: VoiceCommandType.drawFromDiscard);
    }

    // For fast-paced turns, color + number is enough to discard (\"at\" not required).
    final color = _extractColor(normalized);
    final value = _extractNumber(normalized);
    if (color != null && value != null) {
      return ParsedVoiceCommand(
        type: VoiceCommandType.discardTile,
        color: color,
        value: value,
      );
    }

    final hasDiscardVerb =
        normalized.contains(' at') ||
        normalized.startsWith('at ') ||
        normalized.contains(' birak') ||
        normalized.contains(' ver');
    if (hasDiscardVerb) {
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
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeIntentText(String text) {
    if (text.isEmpty) return text;
    var s = ' $text ';

    // Phrase-level normalization for frequent STT confusion.
    const phraseAliases = <String, String>{
      ' noktadan ': ' ortadan ',
      ' notkadan ': ' ortadan ',
      ' ortan dan ': ' ortadan ',
      ' orta dan ': ' ortadan ',
      ' yandanan ': ' yandan ',
      ' iskata dan ': ' iskartadan ',
      ' iskatadan ': ' iskartadan ',
      ' iskardan ': ' iskartadan ',
      ' deste den ': ' desteden ',
      ' kapali dan ': ' kapalidan ',
      ' yer den ': ' yerden ',
    };
    phraseAliases.forEach((from, to) {
      s = s.replaceAll(from, to);
    });

    final tokenAliases = <String, String>{
      // action keywords
      'noktadan': 'ortadan',
      'ortan': 'ortadan',
      'ortana': 'ortadan',
      'orta': 'ortadan',
      'yandam': 'yandan',
      'yandanm': 'yandan',
      'cek': 'cek',
      'cekir': 'cek',
      'sek': 'cek',
      'al': 'al',
      'aal': 'al',
      'at': 'at',
      'birak': 'birak',
      'ver': 'ver',
      'tas': 'tas',
      'task': 'tas',
      // command nouns
      'iskartadan': 'iskartadan',
      'iskatadan': 'iskartadan',
      'iskardan': 'iskartadan',
      'desteden': 'desteden',
      'kapalidan': 'kapalidan',
      // colors
      'sari': 'sari',
      'sarya': 'sari',
      'sara': 'sari',
      'kirmizi': 'kirmizi',
      'kirmisi': 'kirmizi',
      'mavi': 'mavi',
      'siyah': 'siyah',
      // numbers often misheard
      'uc': 'uc',
      'uuc': 'uc',
      'dort': 'dort',
      'bes': 'bes',
      'alti': 'alti',
      'yedi': 'yedi',
      'sekiz': 'sekiz',
      'dokuz': 'dokuz',
      'on': 'on',
      'bir': 'bir',
      'iki': 'iki',
      // other intents
      'seri': 'seri',
      'bitir': 'bitir',
      'biter': 'bitir',
      'bitirr': 'bitir',
      'bitur': 'bitir',
    };

    final words = s.trim().split(RegExp(r'\s+'));
    final normalizedWords = words.map((w) => tokenAliases[w] ?? w).toList();
    return normalizedWords.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
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

  bool _canExecuteNow(String transcript, ParsedVoiceCommand parsed) {
    final now = DateTime.now();
    final normalized = _normalize(transcript);
    final commandKey = _buildCommandKey(parsed, normalized);
    final last = _lastExecutedAt;
    if (last == null) return true;

    final deltaMs = now.difference(last).inMilliseconds;

    // Strong dedupe for same semantic command, even if transcript text differs slightly.
    if (deltaMs < 1500 && commandKey == _lastExecutedCommandKey) {
      return false;
    }

    // Fallback dedupe for exact same transcript bursts.
    if (deltaMs < 800 && normalized == _lastExecutedTranscript) {
      return false;
    }

    return true;
  }

  String _buildCommandKey(ParsedVoiceCommand parsed, String normalized) {
    switch (parsed.type) {
      case VoiceCommandType.discardTile:
        final c = parsed.color?.name ?? 'x';
        final v = parsed.value?.toString() ?? 'x';
        return 'discard:$c:$v';
      case VoiceCommandType.drawFromClosed:
        return 'draw:closed';
      case VoiceCommandType.drawFromDiscard:
        return 'draw:discard';
      case VoiceCommandType.arrangeSerial:
        return 'arrange:serial';
      case VoiceCommandType.finishGame:
        return 'finish';
      case VoiceCommandType.unknown:
        return 'unknown:$normalized';
    }
  }

  void _markExecuted(String transcript, ParsedVoiceCommand parsed) {
    _lastExecutedTranscript = _normalize(transcript);
    _lastExecutedCommandKey = _buildCommandKey(parsed, _lastExecutedTranscript);
    _lastExecutedAt = DateTime.now();
  }

  void _scheduleRestart(OkeyGame game) {
    if (!_keepListening) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 40), () async {
      if (!_keepListening || _isExecuting || _speech.isListening) return;
      debugPrint('[VOICE] restarting listen session');
      await startListening(game);
    });
  }

  bool _containsBabosIntent(String normalizedText) {
    return normalizedText.contains('babos') ||
        normalizedText.contains('babosh') ||
        normalizedText.contains('babo') ||
        normalizedText.contains('babus');
  }
}
