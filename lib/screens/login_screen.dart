import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'lobby_screen.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../ui/lobby/lobby_shimmer_loaders.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

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

  late final AnimationController _fadeController;
  late final AnimationController _particleController;

  bool _loading = false;
  bool _loadingGuest = false;
  String? _error;

  final List<Particle> particles = [];

  @override
  void initState() {
    super.initState();

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

    /// basit email format kontrolü
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
      /// 1️⃣ önce login dene
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
      /// 2️⃣ kullanıcı yoksa register
      if (e.code == "invalid_credentials") {
        try {
          await supabase.auth.signUp(email: email, password: password);

          /// 3️⃣ auto login
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
      await supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: 'okeyix://login-callback',
        authScreenLaunchMode: LaunchMode.platformDefault,
      );
    } catch (e) {
      final msg = e.toString();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Login error: $msg")));
      }
    }
  }

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    String? storedId = prefs.getString("device_id");

    if (storedId != null) {
      return storedId;
    }

    final deviceInfo = DeviceInfoPlugin();
    String id;

    if (kIsWeb) {
      id = const Uuid().v4();
    } else if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      id = android.id;
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      id = ios.identifierForVendor ?? const Uuid().v4();
    } else {
      id = const Uuid().v4();
    }

    await prefs.setString("device_id", id);

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
      /// 1️⃣ önce login dene
      await supabase.auth.signInWithPassword(email: email, password: password);
    } on AuthApiException catch (e) {
      /// 2️⃣ kullanıcı yoksa oluştur
      if (e.code == 'invalid_credentials') {
        await supabase.auth.signUp(
          email: email,
          password: password,
          data: {"guest": true, "device_hash": deviceHash},
        );

        /// 3️⃣ sonra tekrar login
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
          /// BACKGROUND
          Positioned.fill(
            child: Image.asset(
              "assets/images/lobby/lobby.png",
              fit: BoxFit.cover,
            ),
          ),

          /// CONTENT
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: isKeyboardOpen ? keyboard + 20 : 20,
              ),
              child: Row(
                children: [
                  /// 🔥 SOL PANEL (LOGO + SOCIAL)
                  Expanded(
                    flex: 4,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: isKeyboardOpen ? 0.4 : 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          /// LOGO ANİMASYON
                          AnimatedScale(
                            scale: isKeyboardOpen ? 0.8 : 1,
                            duration: const Duration(milliseconds: 250),
                            child: const OkeyixLogo(),
                          ),

                          const SizedBox(height: 24),

                          _socialButtons(),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 20),

                  /// 🔥 SAĞ PANEL (FORM)
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: SingleChildScrollView(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 420,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x990B1612),
                            borderRadius: BorderRadius.circular(22),

                            /// 🔥 GOLD BORDER
                            border: Border.all(
                              color: const Color(0x66F2C14E),
                              width: 1.2,
                            ),

                            /// 🔥 GLOW
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0x33F2C14E),
                                blurRadius: isKeyboardOpen ? 30 : 20,
                                spreadRadius: 1,
                              ),
                              const BoxShadow(
                                color: Color(0x88000000),
                                blurRadius: 40,
                                offset: Offset(0, 20),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              /// GUEST
                              _guestButton(),

                              const SizedBox(height: 12),

                              const Text(
                                "veya e-posta ile giriş",
                                style: TextStyle(color: Colors.white70),
                              ),

                              const SizedBox(height: 12),

                              _inputField(
                                controller: emailController,
                                hint: "E-posta",
                                icon: Icons.alternate_email,
                              ),

                              const SizedBox(height: 10),

                              _inputField(
                                controller: passwordController,
                                hint: "Şifre",
                                icon: Icons.lock,
                                obscure: true,
                              ),

                              const SizedBox(height: 10),

                              _errorBox(),

                              const SizedBox(height: 14),

                              SizedBox(
                                width: double.infinity,
                                child: _loginButton(),
                              ),
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

  Widget _googleButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _loginWithGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          elevation: 10,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset("assets/images/google.png", height: 22),
            const SizedBox(width: 10),
            const Text(
              "Google",
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appleButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _loginWithApple,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F0F0F),
          elevation: 8,
          shadowColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(
              color: Color(0x33FFFFFF), // ince açık border
              width: 1,
            ),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.apple, size: 20, color: Colors.white),
            SizedBox(width: 8),
            Text(
              "Apple",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guestButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _loadingGuest ? null : _playAsGuest,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0x11F2C14E),
          elevation: 0,
          side: const BorderSide(color: Color(0x55F2C14E)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _loadingGuest
            ? const LobbyLoading()
            : const Text(
                "MİSAFİR OLARAK OYNA",
                style: TextStyle(
                  color: Color(0xFFF2C14E),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
      ),
    );
  }

  Widget _socialButtons() {
    return Row(
      children: [
        Expanded(child: _googleButton()),
        const SizedBox(width: 12),
        Expanded(child: _appleButton()),
      ],
    );
  }

  Widget _loginButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _loading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF2C14E),
          foregroundColor: Colors.black,
          elevation: 18,
          shadowColor: const Color(0x99F2C14E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: _loading
            ? const LobbyLoading()
            : const Text(
                "GİRİŞ YAP",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
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

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    const gold = Color(0xFFF2C14E);

    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      cursorColor: gold,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0x809FB0A9)),
        prefixIcon: Icon(icon, color: gold),

        filled: true,
        fillColor: const Color(0xFF15211B),

        /// NORMAL BORDER
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x55F2C14E), width: 1.5),
        ),

        /// FOCUS BORDER
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: gold, width: 2),
        ),

        /// ERROR BORDER
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),
      ),
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
            /// glow katmanı

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
                  fontSize: 16,
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
