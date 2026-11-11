import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _analytics.setAnalyticsCollectionEnabled(true);
    } catch (e) {
      debugPrint('ANALYTICS INIT ERROR: $e');
    }
  }

  Future<void> requestTrackingPermissionIfNeeded() async {
    if (!Platform.isIOS) return;
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (e) {
      debugPrint('ATT REQUEST ERROR: $e');
    }
  }

  Future<void> logLogin({required String method}) async {
    try {
      await _analytics.logLogin(loginMethod: method);
    } catch (e) {
      debugPrint('ANALYTICS LOGIN ERROR: $e');
    }
  }

  Future<void> logSignUp({required String method}) async {
    try {
      await _analytics.logSignUp(signUpMethod: method);
    } catch (e) {
      debugPrint('ANALYTICS SIGNUP ERROR: $e');
    }
  }

  Future<void> logCoinPurchase({
    required String productId,
    required int coins,
    required String platform,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'coin_purchase_success',
        parameters: {
          'product_id': productId,
          'coins': coins,
          'platform': platform,
        },
      );
    } catch (e) {
      debugPrint('ANALYTICS PURCHASE ERROR: $e');
    }
  }

  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint('ANALYTICS EVENT ERROR ($name): $e');
    }
  }
}
