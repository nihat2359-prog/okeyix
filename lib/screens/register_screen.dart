import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  final supabase = Supabase.instance.client;

  late final AnimationController _fadeController;
  late final AnimationController _bgMotionController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _bgMotionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(
      begin: 0.97,
      end: 1,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _bgMotionController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirm = confirmController.text.trim();

    if (email.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _error = "Tüm alanlar zorunlu.");
      return;
    }

    if (!email.contains("@")) {
      setState(() => _error = "Geçerli bir e-posta gir.");
      return;
    }

    if (password.length < 6) {
      setState(() => _error = "Şifre en az 6 karakter olmalı.");
      return;
    }

    if (password != confirm) {
      setState(() => _error = "Şifreler eşleşmiyor.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await supabase.auth.signUp(email: email, password: password);

      if (res.user == null) {
        setState(() => _error = "Kayıt başarısız.");
        return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Doğrulama e-postası gönderildi. Lütfen gelen kutunu kontrol et.",
          ),
        ),
      );

      Navigator.pop(context);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final wide = size.width >= 980;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset("assets/images/lobby.png", fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgMotionController,
              builder: (_, child) {
                final t = _bgMotionController.value;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1 + t, -1),
                      end: Alignment(1 - t, 1),
                      colors: const [
                        Color(0xCC07130E),
                        Color(0xCC0E2C21),
                        Color(0xCC07130E),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: -120,
            top: -80,
            child: _glowOrb(300, const Color(0x99F2C14E)),
          ),
          Positioned(
            right: -100,
            bottom: -120,
            child: _glowOrb(320, const Color(0x6646A36A)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          color: const Color(0xCC081710),
                          border: Border.all(color: const Color(0x55E0B84D)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x80000000),
                              blurRadius: 32,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: wide
                              ? Row(
                                  children: [
                                    Expanded(child: _buildShowcase()),
                                    const SizedBox(width: 18),
                                    SizedBox(
                                      width: 430,
                                      child: _buildRegisterCard(),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildRegisterCard(),
                                    const SizedBox(height: 14),
                                    _buildShowcase(compact: true),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowcase({bool compact = false}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF103B2D), Color(0xFF0B231A)],
        ),
        border: Border.all(color: const Color(0x33F2C14E)),
      ),
      padding: EdgeInsets.all(compact ? 18 : 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person_add_alt_1, color: Color(0xFFF2C14E), size: 26),
              SizedBox(width: 10),
              Text(
                "YENİ OYUNCU",
                style: TextStyle(
                  color: Color(0xFFF2C14E),
                  letterSpacing: 1.8,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            "Hesabını oluştur ve lig masalarına katıl.",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "Kayıt sonrası e-posta doğrulaması ile hesabını aktif et. Sonrasında onboarding ile kullanıcı adını ve avatarını tamamlayıp oyuna geç.",
            style: TextStyle(color: Color(0xFFB7C7C1), height: 1.5),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _FeatureTag(
                label: "E-posta Doğrulama",
                icon: Icons.mark_email_read,
              ),
              _FeatureTag(label: "Profil Onboarding", icon: Icons.badge),
              _FeatureTag(label: "Lig Masaları", icon: Icons.table_restaurant),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 18),
            Container(
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: const DecorationImage(
                  image: AssetImage("assets/images/table.png"),
                  fit: BoxFit.cover,
                ),
                border: Border.all(color: const Color(0x44F2C14E)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRegisterCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xCC0C1310),
        border: Border.all(color: const Color(0x44F2C14E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Hesap Oluştur",
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 6),

          const Text(
            "Yeni bir OKEYIX hesabı oluştur.",
            style: TextStyle(color: Color(0xFF9FB0A9)),
          ),

          const SizedBox(height: 20),

          /// GOOGLE LOGIN
          _socialButton(
            label: "Google ile devam et",
            icon: Icons.g_mobiledata,
            color: Colors.white,
            textColor: Colors.black,
            onTap: _loginWithGoogle,
          ),

          const SizedBox(height: 10),

          /// APPLE LOGIN
          _socialButton(
            label: "Apple ile devam et",
            icon: Icons.apple,
            color: Colors.black,
            textColor: Colors.white,
            onTap: _loginWithApple,
          ),

          const SizedBox(height: 16),

          /// DIVIDER
          Row(
            children: const [
              Expanded(child: Divider(color: Color(0x334F8F75))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  "veya e-posta ile kayıt ol",
                  style: TextStyle(color: Color(0xFF809A90)),
                ),
              ),
              Expanded(child: Divider(color: Color(0x334F8F75))),
            ],
          ),

          const SizedBox(height: 16),

          /// EMAIL
          _inputField(
            controller: emailController,
            hint: "E-posta",
            icon: Icons.alternate_email,
          ),

          const SizedBox(height: 12),

          /// PASSWORD
          _inputField(
            controller: passwordController,
            hint: "Şifre",
            icon: Icons.lock,
            obscure: true,
          ),

          const SizedBox(height: 12),

          /// CONFIRM
          _inputField(
            controller: confirmController,
            hint: "Şifre Tekrar",
            icon: Icons.lock_reset,
            obscure: true,
          ),

          const SizedBox(height: 16),

          /// ERROR
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x33FF4D4D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x66FF7A7A)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFFB5B5)),
              ),
            ),

          if (_error != null) const SizedBox(height: 12),

          /// REGISTER BUTTON
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2C14E),
                foregroundColor: const Color(0xFF101410),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF1F3A2D),
                        ),
                        backgroundColor: Color(0x55FFFFFF),
                      ),
                    )
                  : const Text(
                      "KAYDI TAMAMLA",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 10),

          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Girişe Dön",
                style: TextStyle(
                  color: Color(0xFFF2C14E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),

          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              _legalLink(
                label: "Hizmet Şartları",
                url: "https://okeyix.com/hizmet-sartlari",
              ),
              const Text("·", style: TextStyle(color: Color(0xFF809A90))),
              _legalLink(
                label: "Gizlilik Politikası",
                url: "https://okeyix.com/gizlilik-politikasi",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _socialButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Future<void> _loginWithGoogle() async {
    await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'okeyix://login-callback',
    );
  }

  Future<void> _loginWithApple() async {
    await Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.apple);
  }

  Widget _legalLink({required String label, required String url}) {
    return TextButton(
      onPressed: () => _showLegalPlaceholder(url),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF9FB0A9),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF9FB0A9),
          fontSize: 12,
        ),
      ),
    );
  }

  void _showLegalPlaceholder(String url) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Bu sayfa yayınlandığında bağlantı: $url"),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0x809FB0A9)),
        prefixIcon: Icon(icon, color: const Color(0xFFF2C14E)),
        filled: true,
        fillColor: const Color(0xFF15211B),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x333A5D4B)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xAAE0B84D), width: 1.5),
        ),
      ),
    );
  }

  Widget _glowOrb(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
        transform: Matrix4.rotationZ(math.pi / 12),
      ),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  final String label;
  final IconData icon;

  const _FeatureTag({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF173126),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x44F2C14E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFF2C14E)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFDCE7E2),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
