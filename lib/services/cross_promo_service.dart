import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum PromoStore { ios, android }

class CrossPromoGame {
  final String id, name, description, androidPackage, iosBundle, iosAppId;
  final String? artworkUrl;
  const CrossPromoGame({
    required this.id,
    required this.name,
    required this.description,
    this.androidPackage = '',
    this.iosBundle = '',
    this.iosAppId = '',
    this.artworkUrl,
  });
  bool configured(PromoStore store) => store == PromoStore.ios
      ? iosBundle.isNotEmpty
      : androidPackage.isNotEmpty;
  Uri storeUrl(PromoStore store) => store == PromoStore.ios
      ? Uri.https('apps.apple.com', '/app/id$iosAppId')
      : Uri.https('play.google.com', '/store/apps/details', {
          'id': androidPackage,
        });
  CrossPromoGame withIosId(String id, {String? artworkUrl}) => CrossPromoGame(
    id: this.id,
    name: name,
    description: description,
    androidPackage: androidPackage,
    iosBundle: iosBundle,
    iosAppId: id,
    artworkUrl: artworkUrl ?? this.artworkUrl,
  );
  CrossPromoGame withArtwork(String? url) =>
      withIosId(iosAppId, artworkUrl: url);
}

/// Empty IDs are intentional: unreleased/unconfigured apps never appear.
class CrossPromoService {
  static final instance = CrossPromoService();
  static const games = [
    CrossPromoGame(
      id: 'okix',
      name: 'Okix',
      description: 'Renkli Ok Bulmacası',
      androidPackage: String.fromEnvironment(
        'OKIX_ANDROID_PACKAGE',
        defaultValue: 'com.okeyix.okix',
      ),
      iosBundle: String.fromEnvironment(
        'OKIX_IOS_BUNDLE',
        defaultValue: 'com.okeyix.okix',
      ),
      iosAppId: String.fromEnvironment(
        'OKIX_IOS_APP_ID',
        defaultValue: '6838298677',
      ),
    ),
    CrossPromoGame(
      id: 'sirenix',
      name: 'Sirenix',
      description: 'Ambulans Kurtarma',
      androidPackage: String.fromEnvironment(
        'SIRENIX_ANDROID_PACKAGE',
        defaultValue: 'com.okeyix.sirenix',
      ),
      iosBundle: String.fromEnvironment(
        'SIRENIX_IOS_BUNDLE',
        defaultValue: 'com.okeyix.sirenix',
      ),
      iosAppId: String.fromEnvironment(
        'SIRENIX_IOS_APP_ID',
        defaultValue: '6836349354',
      ),
    ),
    CrossPromoGame(
      id: 'kartix',
      name: 'Kartix',
      description: 'Üçlü Taş Eşleştirme',
      androidPackage: String.fromEnvironment(
        'KARTIX_ANDROID_PACKAGE',
        defaultValue: 'com.okeyix.kartix',
      ),
      iosBundle: String.fromEnvironment(
        'KARTIX_IOS_BUNDLE',
        defaultValue: 'com.okeyix.kartix',
      ),
      iosAppId: String.fromEnvironment(
        'KARTIX_IOS_APP_ID',
        defaultValue: '6837629065',
      ),
    ),
  ];
  final http.Client _http;
  final Future<bool> Function(Uri) _open;
  final List<CrossPromoGame> catalog;
  final PromoStore? store;
  Future<List<CrossPromoGame>>? _published;
  final Set<String> _claiming = {};

  CrossPromoService({
    http.Client? client,
    this.catalog = games,
    PromoStore? platform,
    Future<bool> Function(Uri)? openStore,
  }) : _http = client ?? http.Client(),
       _open = openStore ?? _openStore,
       store = platform ?? currentStore;

  static Future<bool> _openStore(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  static PromoStore? get currentStore => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => PromoStore.ios,
    TargetPlatform.android => PromoStore.android,
    _ => kIsWeb ? PromoStore.ios : null,
  };

  Future<List<CrossPromoGame>> publishedGames() => _published ??= _lookupAll();

  Future<List<CrossPromoGame>> _lookupAll() async {
    if (store == null) return const [];
    final results = await Future.wait(
      catalog.where((g) => g.configured(store!)).map(_lookup),
    );
    return List.unmodifiable(results.whereType<CrossPromoGame>());
  }

  Future<CrossPromoGame?> _lookup(CrossPromoGame game) async {
    try {
      final uri = store == PromoStore.ios
          ? Uri.https('itunes.apple.com', '/lookup', {
              'bundleId': game.iosBundle,
              'country': 'tr',
            })
          : Uri.https('play.google.com', '/store/apps/details', {
              'id': game.androidPackage,
              'hl': 'tr',
              'gl': 'TR',
            });
      final response = await _http.get(uri).timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return null;
      if (store == PromoStore.ios) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        for (final row in (body['results'] as List? ?? const [])) {
          if (row['bundleId'] == game.iosBundle &&
              row['kind'] == 'software' &&
              row['trackId'] != null) {
            return game.withIosId(
              row['trackId'].toString(),
              artworkUrl:
                  _artwork(row['artworkUrl512']) ??
                  _artwork(row['artworkUrl100']) ??
                  _artwork(row['artworkUrl60']),
            );
          }
        }
        return null;
      }
      // A 200 response alone can be a consent, error or private-test page.
      // Only accept public app structured data with the exact package ID.
      final scripts = RegExp(
        r'<script[^>]*type=["\x27]application/ld\+json["\x27][^>]*>([\s\S]*?)</script>',
        caseSensitive: false,
      );
      for (final match in scripts.allMatches(response.body)) {
        final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;
        final url = Uri.tryParse(data['url']?.toString() ?? '');
        if (data['@type'] == 'SoftwareApplication' &&
            url?.host == 'play.google.com' &&
            url?.queryParameters['id'] == game.androidPackage &&
            data['offers'] != null &&
            data['name'] is String) {
          return game.withArtwork(_artwork(data['image']));
        }
      }
    } catch (_) {
      // Offline, CORS, throttling and ambiguous responses all fail closed.
    }
    return null;
  }

  static String? _artwork(dynamic value) {
    if (value is Map) value = value['url'];
    final uri = value is String ? Uri.tryParse(value) : null;
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? uri.toString()
        : null;
  }

  String _key(String userId, CrossPromoGame game) =>
      'cross_promo.v1.$userId.${game.id}';

  Future<bool> claimed(String userId, CrossPromoGame game) async =>
      (await SharedPreferences.getInstance()).getBool(_key(userId, game)) ??
      false;

  /// Opening the store is the reward trigger; this does not claim to verify install.
  Future<int> openAndReward(CrossPromoGame game, SupabaseClient client) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null || store == null) throw StateError('Oturum gerekli.');
    if (!(await publishedGames()).any((g) => g.id == game.id)) {
      throw StateError('Oyun mağazada bulunamadı.');
    }
    final key = _key(userId, game);
    if (!_claiming.add(key)) return 0;
    try {
      final published = (await publishedGames()).firstWhere(
        (g) => g.id == game.id,
      );
      final opened = await _open(published.storeUrl(store!));
      if (!opened) throw StateError('Mağaza açılamadı.');
      if (client.auth.currentUser?.id != userId) {
        throw StateError('Oturum değişti.');
      }
      if (await claimed(userId, game)) return 0;
      final result = Map<String, dynamic>.from(
        await client.rpc(
              'okeyix_claim_cross_promo',
              params: {'p_game_id': game.id, 'p_store': store!.name},
            )
            as Map,
      );
      final amount = (result['amount'] as num?)?.toInt() ?? 0;
      if (result['credited'] != true && result['already_claimed'] != true) {
        throw StateError('Ödül alınamadı.');
      }
      if (result['credited'] == true && amount != 5000) {
        throw const FormatException('Invalid promo reward');
      }
      await (await SharedPreferences.getInstance()).setBool(key, true);
      return result['credited'] == true ? amount : 0;
    } finally {
      _claiming.remove(key);
    }
  }
}
