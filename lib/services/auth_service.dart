import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final _supabase = Supabase.instance.client;

  static User? get currentUser => _supabase.auth.currentUser;

  static String? get userId => _supabase.auth.currentUser?.id;

  static bool isLoggedIn() {
    return _supabase.auth.currentUser != null;
  }

  static bool isGuest() {
    final email = _supabase.auth.currentUser?.email ?? "";
    return email.startsWith("guest_");
  }
}
