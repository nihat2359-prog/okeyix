class PlayerModel {
  final String id;
  final String name;
  final String avatarPath;
  int coins;
  int rating;
  bool isDoubleMode;

  bool isActive;
  double remainingTime;

  PlayerModel({
    required this.id,
    required this.name,
    required this.avatarPath,
    required this.coins,
    this.rating = 1000,
    this.isDoubleMode = false,
    this.isActive = false,
    this.remainingTime = 15,
  });
}
