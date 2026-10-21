import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Opt-in on release/profile: --dart-define=OKEYIX_STORE_TRACE=true.
/// Never log balances, user IDs, product responses or purchase receipts.
class StoreDiagnostics {
  static const enabled = bool.fromEnvironment('OKEYIX_STORE_TRACE', defaultValue: kDebugMode);
  static bool _installed = false;
  static int _active = 0, _session = 0;
  static bool _painted = false;
  static final _seen = <String>{};

  static void begin() {
    if (!enabled) return;
    _install();
    _active++;
    _session++;
    _seen.clear();
    _painted = false;
    if (_active == 1) WidgetsBinding.instance.addTimingsCallback(_timings);
    log('navigation_request');
  }
  static void end() {
    log('navigation_return');
    if (_active > 0) _active--;
    if (enabled && _active == 0) WidgetsBinding.instance.removeTimingsCallback(_timings);
  }
  static void log(String stage, [Map<String, Object?> fields = const {}]) {
    if (!enabled || _active == 0) return;
    if (stage == 'scene_paint_complete') _painted = true;
    debugPrint('[STORE_TRACE] ${jsonEncode({'session': _session, 'stage': stage, ...fields})}');
  }
  static void _timings(List<FrameTiming> timings) {
    if (!_painted || timings.isEmpty) return;
    once('frame_timing_after_store_paint', {
      'build_us': timings.last.buildDuration.inMicroseconds,
      'raster_us': timings.last.rasterDuration.inMicroseconds,
    });
  }
  static void once(String stage, [Map<String, Object?> fields = const {}]) {
    if (!enabled || _active == 0 || !_seen.add(stage)) return;
    log(stage, fields);
  }
  static void error(String stage, Object error, StackTrace? stack) {
    log(stage, {'error_type': error.runtimeType.toString(), 'message': error.toString()});
    if (enabled && _active > 0 && stack != null) {
      for (final line in stack.toString().split('\n')) {
        debugPrint('[STORE_TRACE] stack $stage $line');
      }
    }
  }
  static void _install() {
    if (_installed) return;
    _installed = true;
    final previousFramework = FlutterError.onError;
    FlutterError.onError = (details) {
      error('framework_error', details.exception, details.stack);
      if (previousFramework != null) {
        previousFramework(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    final previousAsync = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      StoreDiagnostics.error('uncaught_async_error', error, stack);
      return previousAsync?.call(error, stack) ?? false;
    };
  }
}

class StorePaintProbe extends SingleChildRenderObjectWidget {
  const StorePaintProbe({super.key, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _StorePaintProbe();
}

class _StorePaintProbe extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    StoreDiagnostics.once('scene_paint_begin', {'width': size.width, 'height': size.height});
    try {
      super.paint(context, offset);
      StoreDiagnostics.once('scene_paint_complete');
    } catch (error, stack) {
      StoreDiagnostics.error('scene_paint_error', error, stack);
      rethrow;
    }
  }
}
