import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okeyix/screens/login_screen.dart';
import 'package:okeyix/screens/lobby_screen.dart';
import 'package:okeyix/screens/okey_game_screen.dart';
import 'package:okeyix/services/device_registration_service.dart';
import 'package:okeyix/services/gift_listener.dart';
import 'package:okeyix/services/presence_service.dart';
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
final GlobalKey<OverlayState> overlayKey = GlobalKey<OverlayState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool _giftListenerStarted = false;

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      PushNotificationService.instance.init(
        onToken: (token) async {
          try {
            await DeviceRegistrationService.registerCurrentDevice(
              pushTokenOverride: token,
            );
          } catch (e) {
            debugPrint('TOKEN REGISTER ERROR: $e');
            _showPushDebug('TOKEN REGISTER ERROR: $e');
          }
        },
        onDebug: _showPushDebug,
        onNotificationTapData: _handlePushTapData,
      ),
    );

    _hideSystemUI();
    _authSub = supabase.auth.onAuthStateChange.listen((event) async {
      final session = event.session;
      if (session != null) {
        await PresenceService.instance.startForCurrentUser();
      } else {
        await PresenceService.instance.stopForCurrentUser();
      }
    });
    if (supabase.auth.currentSession != null) {
      PresenceService.instance.startForCurrentUser();
    }
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
      PresenceService.instance.onAppResumed();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      PresenceService.instance.onAppBackgrounded();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    PushNotificationService.instance.dispose();
    PresenceService.instance.onAppBackgrounded();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _handlePushTapData(Map<String, dynamic> data) async {
    final tableId = data['table_id']?.toString();
    if (tableId == null || tableId.isEmpty) return;
    if (supabase.auth.currentSession == null) return;

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    await Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => OkeyGameScreen(tableId: tableId, isCreator: false),
      ),
    );
  }

  void _showPushDebug(String message) {
    debugPrint(message);
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 4),
      ),
    );
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
        fontFamily: "Montserrat",
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

class AgeGateScreen extends StatelessWidget {
  final VoidCallback onApproved;

  const AgeGateScreen({super.key, required this.onApproved});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B), // 🔥 deep black
      body: Center(
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A), // card
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.amber.withOpacity(0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.7),
                blurRadius: 25,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔥 Logo / Title
              Text(
                "OkeyIX",
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 16),

              // 🔥 Welcome
              Text(
                "Hoş geldin",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 16),

              // 🔥 Message
              Text(
                "Bu oyun 13 yaş ve üzeri kullanıcılar içindir.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 24),

              // 🔥 Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onApproved,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    "Devam Et",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
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
