import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class AuthService {
  static bool isGuest() {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    return user.email?.startsWith("guest_") == true ||
        user.userMetadata?['guest'] == true;
  }
}
