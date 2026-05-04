import 'dart:convert';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/okey_game.dart';
import 'package:okeyix/game/rack/rack_config.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui' as ui;

class SpectatorGame extends FlameGame {
  final String tableId;
  final VoidCallback? onTableClosed;
  SpectatorGame({required this.tableId, this.onTableClosed});

  final supabase = Supabase.instance.client;

  @override
  late final World world;
  late final CameraComponent cameraComponent;

  late Vector2 deckPos;
  late Vector2 indicatorPos;
  late Vector2 discardLeftPos;
  late Vector2 discardRightPos;
  final center = Vector2(800, 450);
  late final OkeyGame _game;
  List<TileComponent> discardLeftStack = [];
  List<TileComponent> discardRightStack = [];
  TileComponent? indicatorTile;

  late TextComponent deckCountText;
  Map<String, int> playerSeatMap = {};
  @override
  Future<void> onLoad() async {
    await super.onLoad();

    /// POSITIONS
    deckPos = center;
    indicatorPos = center + Vector2(110, 0);

    discardLeftPos = center + Vector2(-300, 0);
    discardRightPos = center + Vector2(300, 0);
    world = World();

    cameraComponent = CameraComponent.withFixedResolution(
      world: world,
      width: 1600,
      height: 900,
    );

    cameraComponent.viewfinder.position = center;

    add(world);
    add(cameraComponent);

    /// 1️⃣ BACKGROUND
    await _loadTableSurface();

    /// 3️⃣ DECK (üstüne text gelecek)
    await _loadDeck();

    /// 4️⃣ INDICATOR
    await _loadIndicator();

    /// 5️⃣ PLAYERS (mapping)
    await _loadPlayers();

    /// 6️⃣ DISCARD INITIAL
    await _loadDiscards();

    /// 7️⃣ DECK COUNT (EN SON → üstte kalır)
    await _loadDeckCount();

    /// 8️⃣ REALTIME
    startRealtime();
  }

  Future<void> _loadDeckCount() async {
    final table = await supabase
        .from('tables')
        .select('deck_count')
        .eq('id', tableId)
        .single();

    final count = table['deck_count'] ?? 0;

    deckCountText.text = count.toString();
  }

  int _getSeatFromPlayer(String userId) {
    return playerSeatMap[userId] ?? 0;
  }

  // =========================
  // TABLE
  // =========================

  Future<void> _loadTableSurface() async {
    final img = await images.load("lobby/table_surface.png");

    world.add(
      SpriteComponent(
        sprite: Sprite(img),
        size: Vector2(1600, 900),
        position: Vector2(800, 450),
        anchor: Anchor.center,
      ),
    );
  }

  // =========================
  // DECK
  // =========================

  Future<void> _loadDeck() async {
    final img = await images.load("tile_back.png");

    for (int i = 0; i < 6; i++) {
      world.add(
        SpriteComponent(
          sprite: Sprite(img),
          size: Vector2(RackConfig.tileWidth, RackConfig.tileHeight),
          position: deckPos + Vector2(i * 2, -i * 2),
          anchor: Anchor.center,
        ),
      );
    }

    /// 🔥 SADECE COMPONENT OLUŞTUR
    deckCountText = TextComponent(
      text: "0",
      position: deckPos + Vector2(5, -10),
      anchor: Anchor.center,
      priority: 999,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color.fromARGB(255, 0, 12, 78),
          fontSize: 46,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    world.add(deckCountText);
  }

  // =========================
  // INDICATOR
  // =========================

  Future<void> _loadIndicator() async {
    final table = await supabase
        .from('tables')
        .select('indicator_tile')
        .eq('id', tableId)
        .single();

    final raw = table['indicator_tile'];

    if (raw == null) {
      return;
    }

    final tile = raw is String ? jsonDecode(raw) : raw;

    indicatorTile?.removeFromParent();

    indicatorTile = _createTileFromModel(tile, indicatorPos);
    indicatorTile!.priority = 500;

    world.add(indicatorTile!);
  }

  // =========================
  // DISCARDS INITIAL
  // =========================

  Future<void> _loadDiscards() async {
    final rows = await supabase
        .from('table_discards')
        .select()
        .eq('table_id', tableId)
        .order('created_at', ascending: true); // 🔥 ÖNEMLİ

    for (final r in rows) {
      final seat = r['seat_index'];
      final raw = r['tile'];
      final tile = raw is String ? jsonDecode(raw) : raw;

      final pos = seat == 0 ? discardRightPos : discardLeftPos;

      final stack = seat == 0 ? discardRightStack : discardLeftStack;

      final newTile = _createTileFromModel(tile, pos);

      /// 🔥 STACK OFFSET (üst üste dizilim)
      final offset = Vector2(0, -2.0 * stack.length.toDouble());
      newTile.position = pos + offset;

      newTile.priority = 100 + stack.length;

      stack.add(newTile);
      world.add(newTile);
    }
  }

  void startRealtime() {
    final channel = supabase.channel('realtime:$tableId');

    /// 🔥 MATCH MOVES (zaten vardı)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'match_moves',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'table_id',
        value: tableId,
      ),
      callback: (payload) {
        final row = payload.newRecord;
        final type = row['move_type'];
        final tile = row['tile_data'];
        final playerId = row['player_id'];

        final parsed = tile is String ? jsonDecode(tile) : tile;
        final seat = _getSeatFromPlayer(playerId);

        switch (type) {
          case 'discard':
            _animateDiscard(parsed, seat);
            _decreaseDeck();
            break;

          case 'draw_deck':
            animateDrawFromDeck(seat, parsed);
            break;

          case 'draw_discard':
            animatePickupFromDiscard(seat, parsed);
            break;
        }
      },
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'tables',
      callback: (payload) {
        final old = payload.oldRecord;
        if (old['id'] == tableId) {
          onTableClosed?.call();
        }
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'tables',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: tableId,
      ),
      callback: (payload) async {
        final row = payload.newRecord;

        final finishAt = row['last_finish_at'];

        if (finishAt != null) {
          // snapshot çek
          final snapshot = await _loadFinishSnapshot(tableId);
          final winnerId = row['last_winner_user_id'];
          final user = await supabase
              .from('users')
              .select('username')
              .eq('id', winnerId)
              .single();

          final winnerName = user['username'];
          if (snapshot != null) {
            _openFinishScreen(snapshot, winnerName); // 🔥 AYNI METHOD
          }
        }
      },
    );

    /// 🔥 EN SON subscribe
    channel.subscribe((status, err) {
      if (err != null) {
        print("REALTIME ERROR: $err");
      }
    });
  }

  Future<Map<String, dynamic>?> _loadFinishSnapshot(tableId) async {
    final res = await supabase
        .from('table_finish_snapshots')
        .select()
        .eq('table_id', tableId)
        .order('finished_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return res;
  }

  void _openFinishScreen(Map<String, dynamic> snapshot, String winnerName) {
    final playersWrapper = snapshot['players'];
    if (playersWrapper == null) return;

    final players = playersWrapper['players'];
    if (players == null || players is! List) return;

    final winner = players.firstWhere((p) => p['is_winner'] == true);

    final rawSlots = winner['slots'];
    if (rawSlots == null || rawSlots is! List) return;

    final slots = List<Map<String, dynamic>>.from(rawSlots);

    _game.showFinishFromGame(
      slots,
      const <String, dynamic>{},
      winnerName,
      false,
      true,
      0,
      false,
      false,
    ); // 🔥 SADECE BU
  }

  void _decreaseDeck() {
    final current = int.tryParse(deckCountText.text) ?? 0;
    final next = (current - 1).clamp(0, 999);

    deckCountText.text = next.toString();

    deckCountText.add(
      ScaleEffect.to(
        Vector2.all(1.3),
        EffectController(duration: 0.15),
        onComplete: () {
          deckCountText.add(
            ScaleEffect.to(Vector2.all(1.0), EffectController(duration: 0.15)),
          );
        },
      ),
    );
  }

  Future<void> _loadPlayers() async {
    final rows = await supabase
        .from('table_players')
        .select('user_id, seat_index')
        .eq('table_id', tableId);

    for (final r in rows) {
      playerSeatMap[r['user_id']] = r['seat_index'];
    }
  }

  void animateDrawFromDeck(int seat, Map tile) {
    final start = deckPos;

    final end = seat == 0 ? bottomAvatarPos : topAvatarPos;

    final t = _createBackTile(start.clone()); // 👈 kapalı taş

    world.add(t);

    t.add(
      MoveEffect.to(
        end,
        EffectController(duration: 0.4),
        onComplete: () => t.removeFromParent(),
      ),
    );
  }

  void animatePickupFromDiscard(int seat, Map tile) {
    late Vector2 start;
    late List<TileComponent> stack;

    if (seat == 0) {
      // ALT oyuncu → soldan alır
      start = discardLeftPos;
      stack = discardLeftStack;
    } else {
      // ÜST oyuncu → sağdan alır
      start = discardRightPos;
      stack = discardRightStack;
    }

    /// ✅ EN ÜSTTEKİ TAŞI AL (KRİTİK)
    if (stack.isNotEmpty) {
      final topTile = stack.removeLast();

      topTile.removeFromParent(); // sadece üstteki gider
    }

    final end = seat == 0 ? bottomAvatarPos : topAvatarPos;

    final t = _createBackTile(start.clone());
    t.priority = 300;

    world.add(t);

    t.add(
      MoveEffect.to(
        end,
        EffectController(duration: 0.4),
        onComplete: () => t.removeFromParent(),
      ),
    );
  }

  void _animateDiscard(Map tile, int seat) {
    final start = seat == 0 ? bottomAvatarPos : topAvatarPos;
    final end = seat == 0 ? discardRightPos : discardLeftPos;

    // 🔥 önce parse et
    final model = _tileModelFromPayload(Map<String, dynamic>.from(tile));
    if (model == null) {
      print("Invalid discard tile: $tile");
      return;
    }

    // 🔥 artık model ile çalış
    final t = _createTileFromModel(model, start.clone());

    world.add(t);

    t.add(
      MoveEffect.to(
        end,
        EffectController(duration: 0.45),
        onComplete: () {
          t.removeFromParent();

          // 🔥 burada da model kullan
          _setDiscard(model, seat);
        },
      ),
    );
  }

  // =========================
  // ANIMATIONS
  // =========================

  void _setDiscard(TileModel tile, int seat) {
    final pos = seat == 0 ? discardRightPos : discardLeftPos;

    final newTile = _createTileFromModel(tile, pos);

    newTile.priority =
        100 + (seat == 0 ? discardRightStack.length : discardLeftStack.length);

    if (seat == 0) {
      discardRightStack.add(newTile);
    } else {
      discardLeftStack.add(newTile);
    }

    world.add(newTile);
  }

  // =========================
  // TILE
  // =========================

  TileComponent _createTileFromModel(TileModel model, Vector2 pos) {
    return TileComponent(tile: model, position: pos)..isLocked = true;
  }

  TileComponent _createBackTile(Vector2 pos) {
    final fakeModel = TileModel(
      id: "BACK", // ⚠️ özel id
      value: 0,
      color: TileColor.red,
      isJoker: true,
    );

    return TileComponent(tile: fakeModel, position: pos)..isLocked = true;
  }

  TileColorType _mapColor(String c) {
    switch (c) {
      case "red":
        return TileColorType.red;
      case "blue":
        return TileColorType.blue;
      case "black":
        return TileColorType.black;
      case "yellow":
        return TileColorType.yellow;
      default:
        return TileColorType.red;
    }
  }

  TileModel? _tileModelFromPayload(Map<String, dynamic> raw) {
    // 🔥 ID ZORUNLU
    final id = raw['id'];
    if (id == null || id.toString().isEmpty) {
      print("Tile payload missing id: $raw");
      return null;
    }

    // value / number
    final valueRaw = raw['number'] ?? raw['value'];
    final value = valueRaw is int ? valueRaw : int.tryParse('$valueRaw');

    // color
    final colorRaw = raw['color'];
    TileColor? color;

    if (colorRaw is int) {
      color = TileColor.values[colorRaw];
    } else if (colorRaw is String) {
      switch (colorRaw) {
        case 'red':
          color = TileColor.red;
          break;
        case 'blue':
          color = TileColor.blue;
          break;
        case 'black':
          color = TileColor.black;
          break;
        case 'yellow':
          color = TileColor.yellow;
          break;
      }
    }

    if (value == null || color == null) {
      print("Invalid tile payload: $raw");
      return null;
    }

    return TileModel(
      id: id.toString(), // 🔥 EN KRİTİK
      value: value,
      color: color,
      isJoker:
          raw['joker'] == true ||
          raw['is_joker'] == true ||
          raw['isJoker'] == true,
      isFakeJoker:
          raw['fake_joker'] == true ||
          raw['is_fake_joker'] == true ||
          raw['isFakeJoker'] == true,
    );
  }

  Future<Sprite> loadAvatarFromAsset(String fullPath) async {
    final data = await rootBundle.load(fullPath);
    final bytes = data.buffer.asUint8List();

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    return Sprite(frame.image);
  }

  Vector2 topAvatarPos = Vector2(800, 80);
  Vector2 bottomAvatarPos = Vector2(800, 820);

  void setAvatarPositions(Vector2 top, Vector2 bottom) {
    topAvatarPos.setFrom(top);
    bottomAvatarPos.setFrom(bottom);
  }
}
