/// Failure hiyerarşisi — TEKNIK-MIMARI.md §8.1
/// Her failure kullanıcı dostu, yerelleştirilmiş mesaja map edilir (l10n).
sealed class Failure {
  const Failure();
}

class NetworkFailure extends Failure {
  const NetworkFailure();
}

class QuotaFailure extends Failure {
  const QuotaFailure();
}

class AiFailure extends Failure {
  const AiFailure({required this.retryable});
  final bool retryable;
}

class ModeratedFailure extends Failure {
  const ModeratedFailure({required this.safeRedirectMessage});
  final String safeRedirectMessage;
}

class AuthFailure extends Failure {
  const AuthFailure(this.code);
  final String code;
}

class ValidationFailure extends Failure {
  const ValidationFailure({required this.field, required this.message});
  final String field;
  final String message;
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

/// Kullanıcıya gösterilecek mesaj eşlemesi.
/// NOT (audit O-2): metinler l10n'a taşındığında bu extension presentation
/// katmanına inecek; domain code-only Failure taşıyacak.
extension FailureMessage on Failure {
  String get userMessage => switch (this) {
        ValidationFailure(:final message) => message,
        NetworkFailure() => 'Bağlantı yok — internet gelince tekrar dene.',
        QuotaFailure() => 'Aylık karar hakkın doldu.',
        AiFailure(:final retryable) => retryable
            ? 'Analiz şu an yapılamadı, birazdan tekrar dene.'
            : 'Analiz yapılamadı.',
        ModeratedFailure(:final safeRedirectMessage) => safeRedirectMessage,
        AuthFailure() => 'Oturum hatası — yeniden giriş yapmayı dene.',
        UnexpectedFailure() => 'Kaydedilemedi — tekrar dene.',
      };
}

/// Basit Result tipi: ya değer ya Failure.
sealed class Result<T> {
  const Result();
  R when<R>({required R Function(T) ok, required R Function(Failure) err}) =>
      switch (this) {
        Ok<T>(:final value) => ok(value),
        Err<T>(:final failure) => err(failure),
      };
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
