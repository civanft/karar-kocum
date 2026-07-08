import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/error/failure.dart';
import 'package:karar_veriyorum/core/services/id_generator.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/usecases/create_decision.dart';

void main() {
  late InMemoryDecisionRepository repo;
  late CreateDecision usecase;

  setUp(() {
    repo = InMemoryDecisionRepository();
    usecase = CreateDecision(repo, IdGenerator());
  });

  tearDown(() => repo.dispose());

  test('geçerli başlık: karar oluşturulur ve repoya kaydedilir', () async {
    final result = await usecase(
      ownerUid: 'u1',
      title: '  iPhone mu Samsung mu?  ',
      templateId: 'phone',
    );

    final decision = switch (result) {
      Ok<Decision>(:final value) => value,
      Err<Decision>() => fail('Ok bekleniyordu'),
    };

    expect(decision.title, 'iPhone mu Samsung mu?'); // trim edilmiş
    expect(decision.ownerUid, 'u1');
    expect(decision.templateId, 'phone');
    expect(decision.status, DecisionStatus.draft);
    expect(decision.options, isEmpty);
    expect(decision.id, hasLength(20));

    final persisted = await repo.getById(decision.id);
    expect(persisted, isNotNull);
  });

  test('geçersiz başlık: Err(ValidationFailure) döner, hiçbir şey kaydedilmez',
      () async {
    final result = await usecase(ownerUid: 'u1', title: 'ab');

    final failure = switch (result) {
      Err<Decision>(:final failure) => failure,
      Ok<Decision>() => fail('Err bekleniyordu'),
    };
    expect(failure, isA<ValidationFailure>());

    var count = 0;
    final sub = repo.watchAll().listen((list) => count = list.length);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(count, 0);
  });

  test('Result.when her iki dalı da doğru çalıştırır', () async {
    final ok = await usecase(ownerUid: 'u1', title: 'Geçerli başlık');
    expect(ok.when(ok: (_) => 'ok', err: (_) => 'err'), 'ok');

    final err = await usecase(ownerUid: 'u1', title: 'x');
    expect(err.when(ok: (_) => 'ok', err: (_) => 'err'), 'err');
  });

  test('IdGenerator: benzersiz ve istenen uzunlukta kimlik üretir', () {
    final gen = IdGenerator();
    final ids = {for (var i = 0; i < 100; i++) gen()};
    expect(ids, hasLength(100)); // çakışma yok
    expect(gen(length: 8), hasLength(8));
  });
}
