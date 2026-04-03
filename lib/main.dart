import 'package:flutter/material.dart';
import 'package:okeyix/screens/login_screen.dart';
import 'package:okeyix/screens/lobby_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';

const _defaultSupabaseUrl = 'https://esqpgtedmojrzoftchis.supabase.co';
const _defaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVzcXBndGVkbW9qcnpvZnRjaGlzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIzMjEyMTIsImV4cCI6MjA4Nzg5NzIxMn0.-XiDoQJtwn_I3PHTc3wxHD_3jhrwoPIqTLpKomOR74o';
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await Supabase.initialize(
    url: _supabaseUrl.isEmpty ? _defaultSupabaseUrl : _supabaseUrl,
    anonKey: _supabaseAnonKey.isEmpty
        ? _defaultSupabaseAnonKey
        : _supabaseAnonKey,
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _deviceRegistered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _hideSystemUI();
  }

  @override
  void didChangeMetrics() {
    Future.delayed(const Duration(milliseconds: 100), () {
      _hideSystemUI();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _hideSystemUI();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        initialData: AuthState(
          AuthChangeEvent.initialSession,
          supabase.auth.currentSession,
        ),
        builder: (context, snapshot) {
          final session =
              snapshot.data?.session ?? supabase.auth.currentSession;

          if (session == null) {
            return const LoginScreen();
          }

          if (!_deviceRegistered) {
            Future.microtask(() async {
              try {
                await registerDevice();
                _deviceRegistered = true;
              } catch (e) {
                if (!mounted) return;

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(
                      error: "Bu cihazdan en fazla 3 hesap açabilirsiniz.",
                    ),
                  ),
                );
              }
            });
          }

          return const LobbyScreen();
        },
      ),
    );
  }
}

void _hideSystemUI() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

Future<String> getDeviceId() async {
  final deviceInfo = DeviceInfoPlugin();

  if (Platform.isAndroid) {
    final android = await deviceInfo.androidInfo;
    return android.id; // Android cihaz id
  }

  if (Platform.isIOS) {
    final ios = await deviceInfo.iosInfo;
    return ios.identifierForVendor ?? "ios_unknown";
  }

  return "unknown_device";
}

Future<void> registerDevice() async {
  try {
    final deviceId = await getDeviceId();

    final deviceInfo = DeviceInfoPlugin();
    final packageInfo = await PackageInfo.fromPlatform();

    String platform = "";
    String deviceModel = "";
    String osVersion = "";

    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      platform = "android";
      deviceModel = android.model;
      osVersion = android.version.release;
    }

    if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      platform = "ios";
      deviceModel = ios.utsname.machine;
      osVersion = ios.systemVersion;
    }

    await supabase.from('user_devices').upsert({
      "user_id": supabase.auth.currentUser!.id,
      "device_id": deviceId,
      "platform": platform,
      "device_model": deviceModel,
      "os_version": osVersion,
      "app_version": packageInfo.version,
      "last_seen": DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,device_id');
  } catch (e) {
    /// cihaz limit hatası
    await supabase.auth.signOut();

    throw Exception("Bu cihazdan maksimum 3 hesap açılabilir.");
  }
}
