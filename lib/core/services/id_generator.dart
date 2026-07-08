import 'dart:math';

/// Basit, bağımlılıksız kimlik üretici.
/// Sprint 2'de Firestore doc().id devralır; arayüz aynı kalır.
class IdGenerator {
  IdGenerator([Random? random]) : _random = random ?? Random.secure();
  final Random _random;

  static const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  String call({int length = 20}) =>
      List.generate(length, (_) => _chars[_random.nextInt(_chars.length)])
          .join();
}
