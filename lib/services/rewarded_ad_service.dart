import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okeyix/core/rewarded_ad_phase.dart';

class RewardedAdService {
  RewardedAdService(this.client);
  final SupabaseClient client;
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static const _android = String.fromEnvironment('ADMOB_REWARDED_ANDROID',
    defaultValue: 'ca-app-pub-4157424138716357/2553824684');
  static const _ios = String.fromEnvironment('ADMOB_REWARDED_IOS',
    defaultValue: 'ca-app-pub-4157424138716357/3727305559');
  static const enabled = bool.fromEnvironment(
    'ADMOB_REWARDS_ENABLED', defaultValue: true,
  );
  // Show the scene without requiring deployed RPCs while IDs are pending.
  static bool get preview => !supported ||
      (defaultTargetPlatform == TargetPlatform.android ? _android.isEmpty : _ios.isEmpty);
  static Future<void>? _initializing;
  bool _busy = false;
  String? _pendingAttempt;
  String? _pendingUser;

  // Development builds use Google's sample units; release uses Okeyix units.
  String get _unit => defaultTargetPlatform == TargetPlatform.android
      ? (kDebugMode ? 'ca-app-pub-3940256099942544/5224354917' : _android)
      : (kDebugMode ? 'ca-app-pub-3940256099942544/1712485313' : _ios);

  Future<Map<String, dynamic>> status() async {
    final uid = client.auth.currentUser?.id;
    final result = Map<String, dynamic>.from(await client
            .rpc('okeyix_ad_reward_status')
            .timeout(const Duration(seconds: 8))
        as Map);
    final day = result['day_key'];
    if (day is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      throw const FormatException('Missing server reward day');
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('ad_video_completed_$uid') == day) {
      result['available'] = false;
    }
    return result;
  }

  static Future<void> _initialize() async {
    final consent = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (!consent.isCompleted) consent.complete();
      }),
      (error) {
        if (!consent.isCompleted) consent.complete();
      },
    );
    await consent.future.timeout(const Duration(seconds: 45));
    if (!await ConsentInformation.instance.canRequestAds()) {
      throw StateError('Reklam şu anda yüklenemiyor. Lütfen yeniden dene.');
    }
    await MobileAds.instance.initialize().timeout(const Duration(seconds: 35));
  }

  static Future<void> privacyOptions() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error == null) {
        done.complete();
      } else {
        done.completeError(StateError(error.message));
      }
    });
    await done.future.timeout(const Duration(seconds: 45));
  }

  Future<bool> claim({ValueChanged<RewardedAdPhase>? onProgress}) async {
    if (_busy || !supported || !enabled) return false;
    _busy = true;
    final userId = client.auth.currentUser?.id;
    try {
      if (userId == null) throw StateError('Oturumun sona erdi. Yeniden giriş yap.');
      onProgress?.call(RewardedAdPhase.preparing);
      if (_pendingUser != userId) {
        _pendingAttempt = null;
        _pendingUser = userId;
      }
      // Retrying a delayed verification never requires watching another ad.
      if (_pendingAttempt != null) {
        onProgress?.call(RewardedAdPhase.verifying);
        return await _waitForCredit(_pendingAttempt!, userId);
      }
      try {
        await (_initializing ??= _initialize());
      } catch (_) {
        _initializing = null;
        rethrow;
      }
      final loaded = Completer<RewardedAd>();
      var abandoned = false;
      onProgress?.call(RewardedAdPhase.loading);
      final loadRequest = RewardedAd.load(
        adUnitId: _unit,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (abandoned || loaded.isCompleted) {
              ad.dispose();
            } else {
              loaded.complete(ad);
            }
          },
          onAdFailedToLoad: (error) {
            if (!abandoned && !loaded.isCompleted)
              loaded.completeError(
                StateError('Şu an video bulunamadı. Biraz sonra tekrar dene.'),
              );
          },
        ),
      );
      final RewardedAd ad;
      try {
        // Observe platform errors without waiting indefinitely for a callback.
        unawaited(loadRequest.catchError((Object error) {
          if (!abandoned && !loaded.isCompleted) {
            loaded.completeError(StateError('Video yüklenemedi. Lütfen yeniden dene.'));
          }
        }));
        ad = await loaded.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        abandoned = true;
        rethrow;
      }
      try {
        if (client.auth.currentUser?.id != userId)
          throw StateError('Oturum değişti.');
        final eligibility = await status();
        if (eligibility['available'] != true) {
          throw StateError('Bugünkü reklam ödülün tamamlandı. Yarın tekrar gel!');
        }
        final rewardDay = eligibility['day_key'] as String;
        final attempt = await client.rpc('okeyix_begin_ad_reward')
            .timeout(const Duration(seconds: 8)) as String;
        await ad.setServerSideOptions(
          ServerSideVerificationOptions(userId: userId, customData: attempt),
        ).timeout(const Duration(seconds: 8));
        final closed = Completer<bool>();
        var earned = false;
        var failedToOpen = false;
        Future<void>? savedCompletion;
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (_) {
            if (!closed.isCompleted) closed.complete(earned);
          },
          onAdFailedToShowFullScreenContent: (_, error) {
            failedToOpen = true;
            if (!closed.isCompleted)
              closed.complete(false);
          },
        );
        onProgress?.call(RewardedAdPhase.opening);
        final showing = ad.show(
          onUserEarnedReward: (_, reward) {
            earned = true;
            _pendingAttempt = attempt;
            savedCompletion = () async {
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('ad_video_completed_$userId', rewardDay);
              } catch (_) { /* Server credit remains authoritative. */ }
            }();
          },
        );
        unawaited(showing.catchError((Object error) {
          failedToOpen = true;
          if (!closed.isCompleted) closed.complete(false);
        }));
        if (!await closed.future.timeout(const Duration(minutes: 10))) {
          throw StateError(failedToOpen
              ? 'Video açılamadı. Ödül hakkın duruyor; yeniden dene.'
              : 'Video tamamlanmadı. Ödül hakkın duruyor; kazanmak için videoyu tamamla.');
        }
        // Suppress repeat offers even while Google's credit callback is delayed.
        // This flag never credits coins; the server remains the wallet authority.
        if (savedCompletion != null) await savedCompletion;
        _pendingAttempt = attempt;
        onProgress?.call(RewardedAdPhase.verifying);
        return await _waitForCredit(attempt, userId);
      } finally {
        ad.dispose();
      }
    } on TimeoutException {
      throw StateError(_pendingAttempt != null
          ? 'Videon tamamlandı. Onay gecikti; tekrar dene ile ödül durumunu kontrol edebilirsin.'
          : 'Bağlantı beklenenden uzun sürdü. Lütfen yeniden dene.');
    } finally {
      _busy = false;
    }
  }

  Future<bool> _waitForCredit(String attempt, String? userId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    for (var i = 0; i < 12; i++) {
      if (DateTime.now().isAfter(deadline)) break;
      if (client.auth.currentUser?.id != userId)
        throw StateError('Oturum değişti.');
      final credited = await client
          .rpc('okeyix_ad_reward_receipt', params: {'p_attempt': attempt})
          .timeout(const Duration(seconds: 8));
      if (credited == true) {
        _pendingAttempt = null;
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw StateError(
      'Video tamamlandı. Ödülün doğrulanıyor; tekrar dene. Coinlerin doğrulama sonrası otomatik eklenecek.',
    );
  }
}
