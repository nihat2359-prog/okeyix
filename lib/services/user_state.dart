class UserState {
  /// Only reuse lobby identity for the same authenticated account.
  static Map<String, dynamic>? tableIdentityFor(String? authenticatedUserId) {
    if (authenticatedUserId == null || userId != authenticatedUserId ||
        userName.trim().isEmpty) {
      return null;
    }
    return {
      'id': authenticatedUserId,
      'username': userName.trim(),
      'avatar_url': userAvatarUrl?.trim() ?? '',
      'is_bot': false,
    };
  }
  static String? userId;
  static int userCoin = 0;
  static String userName = 'Oyuncu';
  static int userRating = 1200;
  static String? userRowId;
  static String? userAvatarUrl;
  static int? wins;
  static int? losses;
  static Set<String> friendIds = {};
  static Set<String> blockedUserIds = {};
  static Set<String> incomingRequestIds = {};
  static Set<String> outgoingRequestIds = {};
  static bool colorBlindMode = false;
}
