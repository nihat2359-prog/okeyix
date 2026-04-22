class UserState {
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
}
