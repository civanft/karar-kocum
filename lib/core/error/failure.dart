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
