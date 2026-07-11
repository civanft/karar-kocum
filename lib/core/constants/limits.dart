/// Ürün limitleri — PRD §5 kabul kriterleri ve Firestore rules ile senkron tutulur.
abstract final class Limits {
  static const int minOptions = 2;
  static const int maxOptions = 10;

  static const int titleMinLength = 3;
  static const int titleMaxLength = 100;

  static const int prosConsItemMaxLength = 140;

  static const int criterionWeightMin = 1;
  static const int criterionWeightMax = 10;
  static const int scoreMin = 1;
  static const int scoreMax = 10;

  /// Kredi modeli (PR #6C-2): kullanıcı başına 5 ücretsiz analiz,
  /// YENİLENMEZ. functions/src/config.ts INITIAL_FREE_CREDITS ile
  /// ve firestore.rules korumasıyla senkron.
  static const int freeAnalysisCredits = 5;

  /// Reklamla kazanılabilecek ödül kredisi üst sınırı (cost hotfix madde 4).
  /// functions/src/config.ts MAX_REWARD_CREDITS ile senkron.
  static const int maxRewardCredits = 5;

  /// Kullanıcı başına karar üst sınırı (cost hotfix madde 5).
  /// functions/src/config.ts MAX_DECISIONS_PER_USER + firestore.rules
  /// maxDecisions() ile senkron.
  static const int maxDecisionsPerUser = 50;

  static const int freeHistoryLimit = 10;
}
