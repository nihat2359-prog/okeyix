import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  bool _didCheckThisSession = false;
  bool _checkInFlight = false;
  bool _dialogOpen = false;
  String? _shownUpdateTokenThisSession;

  Future<void> checkForUpdatesOnStartup(BuildContext context) async {
    if (_didCheckThisSession || _checkInFlight) return;
    _checkInFlight = true;
    _didCheckThisSession = true;

    try {
      if (Platform.isAndroid) {
        await _checkAndroid(context);
        return;
      }
      if (Platform.isIOS) {
        await _checkIos(context);
      }
    } catch (e) {
      debugPrint('UPDATE_CHECK_ERROR: $e');
    } finally {
      _checkInFlight = false;
    }
  }

  Future<void> _checkAndroid(BuildContext context) async {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability != UpdateAvailability.updateAvailable) return;

    final staleDays = info.clientVersionStalenessDays ?? 0;
    final critical = info.immediateUpdateAllowed && staleDays >= 7;
    final androidToken =
        'android:${info.availableVersionCode ?? 0}:${info.installStatus.name}';
    if (_shownUpdateTokenThisSession == androidToken) return;

    if (critical) {
      _shownUpdateTokenThisSession = androidToken;
      await InAppUpdate.performImmediateUpdate();
      return;
    }

    if (info.flexibleUpdateAllowed) {
      _shownUpdateTokenThisSession = androidToken;
      final accepted = await _showOptionalUpdateDialog(
        context,
        title: 'Yeni Surum Hazir',
        message:
            'Daha iyi performans ve duzeltmeler icin guncellemeyi simdi yukleyebilirsin.',
        updateNowLabel: 'Guncelle',
      );
      if (accepted) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      }
      return;
    }

    if (info.immediateUpdateAllowed) {
      _shownUpdateTokenThisSession = androidToken;
      final accepted = await _showOptionalUpdateDialog(
        context,
        title: 'Yeni Surum Hazir',
        message: 'Yeni surume gecmek icin guncelleme gerekli.',
        updateNowLabel: 'Guncelle',
      );
      if (accepted) {
        await InAppUpdate.performImmediateUpdate();
      }
    }
  }

  Future<void> _checkIos(BuildContext context) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final bundleId = packageInfo.packageName;
    final currentVersion = packageInfo.version;

    final lookupUri = Uri.parse(
      'https://itunes.apple.com/lookup?bundleId=$bundleId',
    );

    final client = HttpClient();
    try {
      final req = await client.getUrl(lookupUri);
      final res = await req.close();
      if (res.statusCode != 200) return;

      final payload = await utf8.decoder.bind(res).join();
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final count = map['resultCount'] as int? ?? 0;
      if (count == 0) return;

      final results = map['results'] as List<dynamic>;
      if (results.isEmpty) return;

      final first = results.first as Map<String, dynamic>;
      final latest = (first['version'] as String?)?.trim();
      final appStoreUrl = (first['trackViewUrl'] as String?)?.trim();
      if (latest == null || appStoreUrl == null || appStoreUrl.isEmpty) return;

      final needsUpdate = _compareVersion(currentVersion, latest) < 0;
      if (!needsUpdate) return;
      final iosToken = 'ios:$latest';
      if (_shownUpdateTokenThisSession == iosToken) return;
      _shownUpdateTokenThisSession = iosToken;

      final accepted = await _showOptionalUpdateDialog(
        context,
        title: 'Yeni Surum Hazir',
        message:
            'Yeni ozellikler ve hata duzeltmeleri yayinda. App Store sayfasina gitmek ister misin?',
        updateNowLabel: 'App Store',
      );
      if (accepted) {
        final uri = Uri.parse(appStoreUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } finally {
      client.close(force: true);
    }
  }

  int _compareVersion(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen = pa.length > pb.length ? pa.length : pb.length;

    for (var i = 0; i < maxLen; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  Future<bool> _showOptionalUpdateDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String updateNowLabel,
  }) async {
    if (_dialogOpen || !context.mounted) return false;
    _dialogOpen = true;

    bool shouldUpdate = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xEE14221D), Color(0xEE0D1512)],
              ),
              border: Border.all(color: const Color(0x66D9B86D), width: 1.1),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.system_update_alt_rounded,
                        color: Color(0xFFE2C67A), size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Guncelleme',
                      style: TextStyle(
                        color: Color(0xFFF2E3BC),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFFCAD7D1),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD4DFDA),
                          side: const BorderSide(color: Color(0x55D8B86D)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Daha Sonra'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          shouldUpdate = true;
                          Navigator.of(ctx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD3A33A),
                          foregroundColor: const Color(0xFF1A1204),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(updateNowLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    _dialogOpen = false;
    return shouldUpdate;
  }
}
