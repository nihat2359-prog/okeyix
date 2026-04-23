import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okeyix/screens/login_screen.dart';
import 'package:okeyix/screens/lobby_screen.dart';
import 'package:okeyix/services/auth_service.dart';
import 'package:okeyix/services/gift_listener.dart';
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

  FlutterError.onError = (details) {
    debugPrint("🔥 ERROR: ${details.exception}");
    debugPrint("${details.stack}");
  };

  runZonedGuarded(
    () {
      runApp(const MyApp());
    },
    (error, stack) {
      debugPrint("🔥 ZONE ERROR: $error");
      debugPrint("$stack");
    },
  );
}

final supabase = Supabase.instance.client;
final GlobalKey<OverlayState> overlayKey = GlobalKey<OverlayState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool _giftListenerStarted = false;

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

  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,

      // 🔥 BURASI EKLENECEK
      builder: (context, child) {
        return Overlay(
          key: overlayKey,
          initialEntries: [OverlayEntry(builder: (context) => child!)],
        );
      },

      theme: ThemeData(
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,

          // 🔥 hafif transparan + derin ton
          backgroundColor: const Color(0xE61B2E28), // %90 opacity

          elevation: 18,

          // 🔥 daha yumuşak spacing
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),

          // 🔥 text daha premium
          contentTextStyle: const TextStyle(
            color: Color(0xFFF1F5F3),
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            height: 1.3,
          ),

          // 🔥 glass + gold border
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: Color(0x66E9C46A), // daha soft gold
              width: 1.2,
            ),
          ),

          // 🔥 action renkleri
          actionTextColor: const Color(0xFFF2C14E),
          disabledActionTextColor: const Color(0x80F2C14E),

          showCloseIcon: true,
          closeIconColor: const Color(0xFFEAF2EE),
        ),
      ),

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

          final user = session.user;

          // 🔥 SPAM ENGELLE (çok önemli)
          if (!_giftListenerStarted) {
            listenIncomingGifts(user.id);
            _giftListenerStarted = true;
          }

          return const AppRoot();
        },
      ),
    );
  }
}

void _hideSystemUI() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // sadece 1 kere çalışsın
    if (!_initialized) {
      final user = supabase.auth.currentUser;
      if (user != null) {
        listenIncomingGifts(user.id);
      }
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LobbyScreen(); // senin ana ekranın
  }
}
