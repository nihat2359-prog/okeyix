import 'dart:math' as math;
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:okeyix/widgets/aaa_button.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'lobby_screen.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  final String? error;
  const LoginScreen({super.key, this.error});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final supabase = Supabase.instance.client;
  static const _secureStorage = FlutterSecureStorage();

  late final AnimationController _fadeController;
  late final AnimationController _particleController;

  bool _loading = false;
  bool _loadingGuest = false;
  String? _error;

  final List<Particle> particles = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAgeGate();
    });
    bool _navigated = false;

    supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;

      if (session != null && mounted && !_navigated) {
        _navigated = true;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LobbyScreen()),
          (route) => false,
        );
      }
    });

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _generateParticles();
    _error = widget.error;
    WidgetsBinding.instance.addObserver(this);
  }

  void _generateParticles() {
    final rand = math.Random();
    for (int i = 0; i < 40; i++) {
      particles.add(
        Particle(
          x: rand.nextDouble(),
          y: rand.nextDouble(),
          speed: 0.02 + rand.nextDouble() * 0.04,
          size: 1 + rand.nextDouble() * 2,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeController.dispose();
    _particleController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = "E-posta ve şifre zorunlu.");
      return;
    }

    /// Basit e-posta format kontrolü
    final emailRegex = RegExp(r'^[\w\.-]+@([\w-]+\.)+[a-zA-Z]{2,}$');

    if (!emailRegex.hasMatch(email)) {
      setState(() => _error = "Geçerli bir e-posta adresi gir.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      /// Önce giriş dene
      final res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (res.user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LobbyScreen()),
        );
        return;
      }
    } on AuthApiException catch (e) {
      /// Kullanıcı yoksa kayıt ol
      if (e.code == "invalid_credentials") {
        try {
          await supabase.auth.signUp(email: email, password: password);

          /// Sonra otomatik giriş yap
          final res = await supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );

          if (res.user != null && mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LobbyScreen()),
            );
          }
        } on AuthException catch (e) {
          setState(() => _error = e.message);
        }
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String? id;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      id = prefs.getString("device_id");
      id ??= 'web_${const Uuid().v4()}';
      await prefs.setString("device_id", id);
    } else if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      id = 'android_${android.id}';
    } else if (Platform.isIOS) {
      id = await _secureStorage.read(key: 'stable_device_id');
      if (id == null || id.isEmpty) {
        final ios = await deviceInfo.iosInfo;
        final vendor = ios.identifierForVendor;
        id = (vendor != null && vendor.isNotEmpty)
            ? 'ios_$vendor'
            : 'ios_${const Uuid().v4()}';
        await _secureStorage.write(key: 'stable_device_id', value: id);
      }
    } else {
      id = await _secureStorage.read(key: 'stable_device_id');
      id ??= 'device_${const Uuid().v4()}';
      await _secureStorage.write(key: 'stable_device_id', value: id);
    }
    return id;
  }

  Future<void> _playAsGuest() async {
    final rawDeviceId = await getDeviceId();

    final deviceHash = hashDeviceId(rawDeviceId);

    final email = "guest_$deviceHash@okeyix.com";
    final password = deviceHash;
    setState(() {
      _loadingGuest = true;
      _error = null;
    });
    try {
      /// Önce giriş dene
      await supabase.auth.signInWithPassword(email: email, password: password);
    } on AuthApiException catch (e) {
      /// Kullanıcı yoksa oluştur
      if (e.code == 'invalid_credentials') {
        await supabase.auth.signUp(
          email: email,
          password: password,
          data: {"guest": true, "device_hash": deviceHash},
        );

        /// Sonra tekrar giriş yap
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } else {
        rethrow;
      }
    } finally {
      if (mounted) setState(() => _loadingGuest = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'okeyix://login-callback',
      );
    } catch (e) {
      setState(() => _error = "Google ile giriş başarısız.");
    }
  }

  Future<void> _loginWithApple() async {
    try {
      final rawNonce = generateNonce();
      final hashedNonce = sha256ofString(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      final authCode = credential.authorizationCode;

      if (idToken == null) {
        throw Exception("Apple login failed - idToken null");
      }

      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        accessToken: authCode,
        nonce: rawNonce, // 🔥 BU ÇOK ÖNEMLİ
      );
    } catch (e) {
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text("LOGIN ERROR: $e"), backgroundColor: Colors.red),
      // );
    }
  }

  String generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String hashDeviceId(String deviceId) {
    final bytes = utf8.encode(deviceId);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  String sanitizeDeviceId(String deviceId) {
    return deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final isKeyboardOpen = keyboard > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          /// 🔥 BACKGROUND
          Positioned.fill(
            child: Image.asset(
              "assets/images/lobby/lobby.png",
              fit: BoxFit.cover,
            ),
          ),

          /// 🔥 DARK OVERLAY (focus verir)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.4, 0),
                  radius: 1.2,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: isKeyboardOpen ? keyboard + 20 : 20,
              ),
              child: Row(
                children: [
                  /// 🔥 SOL (LOGO)
                  Expanded(
                    flex: 4,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: isKeyboardOpen ? 0.3 : 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          /// 🔥 LOGO (daha dramatik)
                          Transform.translate(
                            offset: const Offset(0, -10),
                            child: AnimatedScale(
                              scale: isKeyboardOpen ? 0.75 : 1,
                              duration: const Duration(milliseconds: 250),
                              child: Column(
                                children: [
                                  const OkeyixLogo(),
                                  const SizedBox(height: 18),
                                  const OkeyixLegalBlock(),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 24),

                  /// 🔥 SAĞ PANEL (LOGIN CARD)
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: SingleChildScrollView(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 420,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 22,
                          ),

                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),

                            /// 🔥 GLASS DEPTH
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.35),
                                Colors.black.withOpacity(0.75),
                              ],
                            ),

                            border: Border.all(
                              color: const Color(0xFFE7C66A).withOpacity(0.4),
                              width: 1.3,
                            ),

                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.9),
                                blurRadius: 60,
                                offset: const Offset(0, 25),
                              ),
                              BoxShadow(
                                color: const Color(
                                  0xFFE7C66A,
                                ).withOpacity(0.15),
                                blurRadius: 30,
                              ),
                            ],
                          ),

                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              /// 🔥 HEADER BLOCK
                              Column(
                                children: [
                                  Text(
                                    "MASAYA KATIL",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.4,
                                      shadows: [
                                        Shadow(
                                          color: Colors.amber.withOpacity(0.6),
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 6),

                                  const Text(
                                    "Gerçek oyuncularla rekabet et",
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 13,
                                    ),
                                  ),

                                  const SizedBox(height: 14),

                                  /// 🔥 ALTIN SEPARATOR
                                  Container(
                                    width: 60,
                                    height: 2,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFD4AF37),
                                          Color(0xFFFFD700),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              /// 🔥 BUTON ALANI (senin butonlar aynen kalacak)
                              AuthButton(
                                icon: const Icon(
                                  Icons.apple,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                text: "Apple ile devam et",
                                type: AuthButtonType.apple,
                                onTap: _loginWithApple,
                              ),
                              const SizedBox(height: 12),

                              AuthButton(
                                icon: Image.asset(
                                  "assets/images/google.png",
                                  height: 20,
                                ),
                                text: "Google ile devam et",
                                type: AuthButtonType.google,
                                onTap: _loginWithGoogle,
                              ),
                              const SizedBox(height: 12),

                              AuthButton(
                                icon: const Icon(
                                  Icons.person_outline,
                                  color: Color(0xFFE7C66A),
                                ),
                                text: "Misafir olarak oyna",
                                type: AuthButtonType.guest,
                                onTap: _loadingGuest ? null : _playAsGuest,
                                loading: _loadingGuest,
                              ),

                              const SizedBox(height: 12),

                              _errorBox(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guestButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _loadingGuest ? null : _playAsGuest,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),

            // 🟡 subtle gradient (premium hissi)
            gradient: LinearGradient(
              colors: [Color(0x11F2C14E), Color(0x22F2C14E)],
            ),

            // 🟡 border
            border: Border.all(color: Color(0x66F2C14E), width: 1),

            // ✨ glow
            boxShadow: [
              BoxShadow(color: Colors.amber.withOpacity(0.15), blurRadius: 10),
            ],
          ),
          child: Container(
            alignment: Alignment.center,
            child: _loadingGuest
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFF2C14E),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: Color(0xFFF2C14E),
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "Misafir olarak oyna",
                        style: TextStyle(
                          color: Color(0xFFF2C14E),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _googleButton() {
    return SizedBox(
      height: 66,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loginWithGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset("assets/images/google.png", height: 24),
                SizedBox(width: 10),
                Text(
                  "Google ile devam et",
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _appleButton() {
    return SizedBox(
      height: 66, // 🔥 eski yüksekliğini koru
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loginWithApple,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [Color(0xFF1C1C1C), Color(0xFF0A0A0A)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal: 16,
            ), // 🔥 kalınlık buradan
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.apple, size: 26, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  "Apple ile devam et",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBox() {
    if (_error == null) return const SizedBox();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xAA2A0F10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent),
        boxShadow: const [
          BoxShadow(color: Colors.redAccent, blurRadius: 12, spreadRadius: 1),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAgeGate() async {
    final prefs = await SharedPreferences.getInstance();
    final ageVerified = prefs.getBool("age_verified") ?? false;

    if (!ageVerified) {
      Future.delayed(Duration.zero, () {
        _showAgeDialog();
      });
    }
  }

  void _showAgeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (_) {
        final screenWidth = MediaQuery.of(context).size.width;

        return Center(
          child: Container(
            width: screenWidth * 0.6, // 🔥 yatayda geniş
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.withOpacity(0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 25,
                  offset: const Offset(0, 12),
                ),
              ],
            ),

            // 🔥 underline fix (hepsine uygular)
            child: DefaultTextStyle(
              style: const TextStyle(decoration: TextDecoration.none),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🔥 Title
                  Text(
                    "OkeyIX",
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      decoration: TextDecoration.none,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 🔥 Welcome
                  Text(
                    "Hoş geldiniz",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 🔥 Message (daha düzgün metin)
                  Text(
                    "Bu oyun 13 yaş ve üzeri kullanıcılar içindir.\nDevam ederek bu şartı kabul etmiş olursunuz.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.5,
                      decoration: TextDecoration.none,
                    ),
                  ),

                  const SizedBox(height: 22),

                  // 🔥 Button
                  SizedBox(
                    width: 220,
                    child: ElevatedButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool("age_verified", true);

                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        "Devam Et",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ParticlePainter extends CustomPainter {
  final double progress;
  final List<Particle> particles;

  ParticlePainter({required this.progress, required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x66F2C14E);

    for (final p in particles) {
      final x = p.x * size.width;
      final y = ((p.y + progress * p.speed) % 1.0) * size.height;

      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class Particle {
  double x;
  double y;
  double speed;
  double size;

  Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
  });
}

class OkeyixLogo extends StatelessWidget {
  const OkeyixLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Color(0x66F2C14E),
                blurRadius: 50,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Image.asset(
            "assets/images/logo/okeyix_logo.png",
            width: 280,
            filterQuality: FilterQuality.high,
          ),
        ),

        const SizedBox(height: 20),

        Stack(
          alignment: Alignment.center,
          children: [
            /// Glow katmanı

            /// ana text
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFFF2C14E),
                  Color(0xFFFFE7A3),
                  Color(0xFFD4A24C),
                ],
              ).createShader(bounds),
              child: const Text(
                "ADİL DAĞITIM • GERÇEK REKABET",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class OkeyixLegalBlock extends StatelessWidget {
  const OkeyixLegalBlock({super.key});

  Future<void> _openPrivacy() async {
    final uri = Uri.parse("https://www.okeyix.com/gizlilik-politikasi");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openWebsite() async {
    final uri = Uri.parse("https://www.okeyix.com");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        /// 🔹 GİZLİLİK METNİ
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
                height: 1.4,
              ),
              children: [
                const TextSpan(text: "Giriş yaparak "),
                TextSpan(
                  text: "Gizlilik Politikası",
                  style: const TextStyle(
                    color: Color(0xFFE7C66A),
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()..onTap = _openPrivacy,
                ),
                const TextSpan(text: "’nı kabul etmiş olursun."),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        /// 🔹 WEBSITE (DAHA SAKİN)
        GestureDetector(
          onTap: _openWebsite,
          child: Text(
            "www.okeyix.com",
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}
