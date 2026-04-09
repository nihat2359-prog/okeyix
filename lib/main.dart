import 'package:flutter/material.dart';
import 'package:okeyix/screens/login_screen.dart';
import 'package:okeyix/screens/lobby_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
            return FutureBuilder(
              future: registerDevice(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return const LoginScreen(
                    error: "Bu cihazdan en fazla 3 hesap açabilirsiniz.",
                  );
                }

                _deviceRegistered = true;
                return const LobbyScreen();
              },
            );
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
  final prefs = await SharedPreferences.getInstance();

  // 🔥 önce kayıtlı var mı bak
  final cached = prefs.getString("device_id");
  if (cached != null) return cached;

  final deviceInfo = DeviceInfoPlugin();
  String deviceId = "";

  if (Platform.isAndroid) {
    final android = await deviceInfo.androidInfo;
    deviceId = android.id;
  } else if (Platform.isIOS) {
    final ios = await deviceInfo.iosInfo;

    deviceId = ios.identifierForVendor ?? const Uuid().v4();
  } else {
    deviceId = const Uuid().v4();
  }

  // 🔥 cache et
  await prefs.setString("device_id", deviceId);

  return deviceId;
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
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      platform = "ios";
      deviceModel = ios.utsname.machine;
      osVersion = ios.systemVersion;
    }

    final res = await supabase.functions.invoke(
      'register_device',
      body: {
        "device_id": deviceId,
        "platform": platform,
        "device_model": deviceModel,
        "os_version": osVersion,
        "app_version": packageInfo.version,
      },
    );

    /// 🔥 HATA KONTROLÜ BURADA
    if (res.data == null) {
      throw Exception("Sunucu yanıt vermedi");
    }

    if (res.data["error"] != null) {
      throw Exception(res.data["error"]);
    }
  } catch (e) {
    /// 🔥 SADECE SIGNOUT + FORWARD
    await supabase.auth.signOut();
    rethrow; // 🔥 EN DOĞRU
  }
}
