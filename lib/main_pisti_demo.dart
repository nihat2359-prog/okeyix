import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dev/pisti/pisti_model.dart';
import 'dev/pisti/pisti_screen.dart';

/// Offline development entry. Does not initialize any production service.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode) {
    runApp(const SizedBox.shrink());
    return;
  }
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  const requested = String.fromEnvironment(
    'PISTI_SCENARIO',
    defaultValue: 'normal',
  );
  final name = Uri.base.queryParameters['scenario'] ?? requested;
  final scenario = PistiScenario.values.firstWhere(
    (s) => s.name == name,
    orElse: () => PistiScenario.normal,
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Montserrat'),
      home: PistiDemoScreen(initialScenario: scenario),
    ),
  );
}
