import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppReviewService {
  AppReviewService({DateTime Function()? now, Future<bool> Function()? available,
    Future<void> Function()? request, Future<String> Function()? version})
      : _now = now ?? DateTime.now,
        _available = available ?? InAppReview.instance.isAvailable,
        _request = request ?? InAppReview.instance.requestReview,
        _version = version ?? (() async => (await PackageInfo.fromPlatform()).version);
  static final instance = AppReviewService();
  final DateTime Function() _now;
  final Future<bool> Function() _available;
  final Future<void> Function() _request;
  final Future<String> Function() _version;
  bool _busy = false;

  static bool get supported => !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> recordVisit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey('review_first_visit')) {
        await prefs.setInt('review_first_visit', _now().millisecondsSinceEpoch);
      }
    } catch (_) { /* Reviewing must never block play. */ }
  }

  Future<void> recordCompletedGame(String roundKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('review_last_round') == roundKey) return;
      await prefs.setString('review_last_round', roundKey);
      await prefs.setInt('review_games', (prefs.getInt('review_games') ?? 0) + 1);
    } catch (_) { /* No gameplay effect. */ }
  }

  Future<void> maybeRequest({required bool Function() canPresent}) async {
    if (_busy || !supported || !canPresent()) return;
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final first = prefs.getInt('review_first_visit');
      final last = prefs.getInt('review_last_request');
      final now = _now();
      if (first == null || (prefs.getInt('review_games') ?? 0) < 3 ||
          now.difference(DateTime.fromMillisecondsSinceEpoch(first)) < const Duration(days: 3) ||
          (last != null && now.difference(DateTime.fromMillisecondsSinceEpoch(last)) < const Duration(days: 120))) return;
      final version = await _version().timeout(const Duration(seconds: 5));
      if (prefs.getString('review_version') == version ||
          !await _available().timeout(const Duration(seconds: 5)) || !canPresent()) return;
      // Store only an attempt. Platforms don't disclose whether a review was sent.
      await prefs.setInt('review_last_request', now.millisecondsSinceEpoch);
      await prefs.setString('review_version', version);
      if (canPresent()) await _request().timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('APP_REVIEW_REQUEST_ERROR: $e');
    } finally { _busy = false; }
  }

  Future<void> openStoreReview() async {
    if (!supported) throw StateError('Değerlendirme mobil uygulamada kullanılabilir.');
    await InAppReview.instance.openStoreListing(appStoreId: '6761813938')
        .timeout(const Duration(seconds: 10));
  }
}
