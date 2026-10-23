import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../ui/update_notice_dialog.dart';

typedef StoreVersion = ({String current, String latest, Uri store});

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  @visibleForTesting
  UpdateService.forTesting({
    required TargetPlatform platform,
    Future<AppUpdateInfo> Function()? androidCheck,
    Future<StoreVersion?> Function()? iosLookup,
    Future<void> Function(Uri)? openStore,
    DateTime Function()? now,
  }) : _platform = platform,
       _androidCheck = androidCheck,
       _iosLookup = iosLookup,
       _openStore = openStore,
       _now = now;

  TargetPlatform? _platform;
  Future<AppUpdateInfo> Function()? _androidCheck;
  Future<StoreVersion?> Function()? _iosLookup;
  Future<void> Function(Uri)? _openStore;
  DateTime Function()? _now;
  bool _checkInFlight = false;
  bool _dialogOpen = false;
  DateTime? _nextCheck;
  String? _shownToken;

  Future<void> checkForUpdatesOnStartup(BuildContext context) async {
    if (kIsWeb || !context.mounted || _checkInFlight || _dialogOpen) return;
    final now = (_now ?? DateTime.now)();
    if (_nextCheck != null && now.isBefore(_nextCheck!)) return;
    _checkInFlight = true;
    try {
      switch (_platform ?? defaultTargetPlatform) {
        case TargetPlatform.android:
          await _checkAndroid(context);
        case TargetPlatform.iOS:
          await _checkIos(context);
        default:
          return;
      }
      _nextCheck = now.add(const Duration(hours: 4));
    } catch (e) {
      // A temporary connection/store failure must not disable the whole session.
      _nextCheck = now.add(const Duration(minutes: 1));
      debugPrint('UPDATE_CHECK_ERROR: $e');
    } finally {
      _checkInFlight = false;
    }
  }

  Future<void> _launchStore(Uri uri) async {
    if (_openStore != null) return _openStore!(uri);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('UPDATE_STORE_OPEN_FAILED');
    }
  }

  Future<void> _checkAndroid(BuildContext context) async {
    final info = await (_androidCheck ?? InAppUpdate.checkForUpdate)().timeout(
      const Duration(seconds: 12),
    );
    if (info.updateAvailability == UpdateAvailability.unknown) {
      throw StateError('UPDATE_AVAILABILITY_UNKNOWN');
    }
    if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
    final token = 'android:${info.availableVersionCode}';
    if (_shownToken == token || !context.mounted) return;
    if (info.immediateUpdateAllowed &&
        (info.clientVersionStalenessDays ?? 0) >= 7) {
      await InAppUpdate.performImmediateUpdate();
      _shownToken = token;
      return;
    }
    final accepted = await _offer(context);
    if (!context.mounted) return;
    _shownToken = token;
    if (!accepted) return;
    try {
      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      } else if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      } else {
        // Availability alone is enough to notify; offer the Play Store page.
        await _launchStore(
          Uri.https('play.google.com', '/store/apps/details', {
            'id': info.packageName,
          }),
        );
      }
    } catch (_) {
      _shownToken = null;
      rethrow;
    }
  }

  Future<StoreVersion?> _lookupIos(String country) async {
    final package = await PackageInfo.fromPlatform();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      for (final region in {country.toLowerCase(), 'us'}) {
        final uri = Uri.https('itunes.apple.com', '/lookup', {
          'bundleId': package.packageName,
          'country': region,
        });
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 8));
        final response = await request.close().timeout(
          const Duration(seconds: 8),
        );
        final body = await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw HttpException('Store lookup ${response.statusCode}');
        }
        final payload = jsonDecode(body) as Map<String, dynamic>;
        final results = payload['results'] as List? ?? [];
        if (results.isEmpty) continue;
        final item = results.first as Map;
        final version = item['version']?.toString();
        final storeUri = Uri.tryParse(item['trackViewUrl']?.toString() ?? '');
        if (version == null || storeUri == null || storeUri.scheme != 'https') {
          continue;
        }
        return (current: package.version, latest: version, store: storeUri);
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _checkIos(BuildContext context) async {
    final country =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? 'TR';
    final version = await (_iosLookup?.call() ?? _lookupIos(country));
    if (version == null) throw StateError('UPDATE_STORE_LOOKUP_EMPTY');
    if (compareVersions(version.current, version.latest) >= 0) return;
    final token = 'ios:${version.latest}';
    if (_shownToken == token || !context.mounted) return;
    final accepted = await _offer(
      context,
      version: version.latest,
      action: 'App Store',
    );
    if (!context.mounted) return;
    _shownToken = token;
    if (accepted) {
      try {
        await _launchStore(version.store);
      } catch (_) {
        _shownToken = null;
        rethrow;
      }
    }
  }

  @visibleForTesting
  static int compareVersions(String a, String b) {
    final left = a
        .split('+')
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final right = b
        .split('+')
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    for (
      var i = 0;
      i < (left.length > right.length ? left.length : right.length);
      i++
    ) {
      final order = (i < left.length ? left[i] : 0).compareTo(
        i < right.length ? right[i] : 0,
      );
      if (order != 0) return order;
    }
    return 0;
  }

  Future<bool> _offer(
    BuildContext context, {
    String? version,
    String action = 'Güncelle',
  }) async {
    if (_dialogOpen || !context.mounted) return false;
    _dialogOpen = true;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (_) =>
                UpdateNoticeDialog(version: version, actionLabel: action),
          ) ??
          false;
    } finally {
      _dialogOpen = false;
    }
  }
}

/// Lives above login and lobby; uses the actual Navigator overlay for dialogs.
class UpdateCheckHost extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final UpdateService? service;
  const UpdateCheckHost({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.service,
  });
  @override
  State<UpdateCheckHost> createState() => _UpdateCheckHostState();
}

class _UpdateCheckHostState extends State<UpdateCheckHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (!mounted) return;
    final context = widget.navigatorKey.currentState?.overlay?.context;
    // Avoid presenting above an active game or another modal route.
    if (context == null || widget.navigatorKey.currentState?.canPop() == true) {
      return;
    }
    unawaited(
      (widget.service ?? UpdateService.instance).checkForUpdatesOnStartup(
        context,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
