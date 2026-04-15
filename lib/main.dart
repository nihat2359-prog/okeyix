import 'package:flutter/material.dart';
import 'package:okeyix/screens/login_screen.dart';
import 'package:okeyix/screens/lobby_screen.dart';
import 'package:okeyix/services/push_notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _hideSystemUI();
    PushNotificationService.instance.initialize();
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

          return const LobbyScreen();
        },
      ),
    );
  }
}

void _hideSystemUI() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}
