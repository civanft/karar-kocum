import '../../domain/entities/decision.dart';
import '../../domain/repositories/decision_repository.dart';

/// Release'de servise bağlanılamadığında kullanılan karar deposu.
///
/// InMemory DEĞİLDİR: in-memory depo, kullanıcıya kalıcı sanacağı kararlar
/// yazdırır ve uygulama kapanınca sessizce kaybolur. Burada her işlem açık
/// bir [DecisionUnavailableException] ile reddedilir; ham teknik ayrıntı
/// taşınmaz.
class UnavailableDecisionRepository implements DecisionRepository {
  const UnavailableDecisionRepository();

  Never _fail() => throw const DecisionUnavailableException();

  @override
  Stream<List<Decision>> watchAll() => Stream.error(
        const DecisionUnavailableException(),
      );

  @override
  Stream<Decision?> watchById(String id) => Stream.error(
        const DecisionUnavailableException(),
      );

  @override
  Future<Decision?> getById(String id) async => _fail();

  @override
  Future<void> upsert(Decision decision) async => _fail();

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) async => _fail();

  @override
  Future<void> delete(String id) async => _fail();
}

/// Kullanıcıya gösterilebilir, teknik ayrıntı taşımayan hata.
class DecisionUnavailableException implements Exception {
  const DecisionUnavailableException();

  static const String message =
      'Servise bağlanılamadı. Bağlantını kontrol edip tekrar dene.';

  @override
  String toString() => message;
}
