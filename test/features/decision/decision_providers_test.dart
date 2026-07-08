import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/error/failure.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('provider grafiği ayağa kalkar: tüm bağlama noktaları çözülür', () {
    expect(container.read(decisionRepositoryProvider), isNotNull);
    expect(container.read(idGeneratorProvider), isNotNull);
    expect(container.read(createDecisionProvider), isNotNull);
    expect(container.read(computeResultProvider), isNotNull);
    expect(container.read(currentUidProvider), 'local-user');
  });

  test('decisionListProvider: oluşturulan karar listede görünür', () async {
    final created = await container.read(createDecisionProvider)(
      ownerUid: container.read(currentUidProvider),
      title: 'Hangi laptopu almalıyım?',
    );
    final decision = switch (created) {
      Ok<Decision>(:final value) => value,
      Err<Decision>() => fail('Ok bekleniyordu'),
    };

    final list = await container.read(decisionListProvider.future);
    expect(list.map((d) => d.id), contains(decision.id));
  });

  test('liste updatedAt azalan sıradadır (en yeni üstte)', () async {
    final create = container.read(createDecisionProvider);
    final uid = container.read(currentUidProvider);

    await create(ownerUid: uid, title: 'Birinci karar');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await create(ownerUid: uid, title: 'İkinci karar');

    final list = await container.read(decisionListProvider.future);
    expect(list, hasLength(2));
    expect(list.first.title, 'İkinci karar');
    expect(
      list[0].updatedAt.isAfter(list[1].updatedAt) ||
          list[0].updatedAt.isAtSameMomentAs(list[1].updatedAt),
      isTrue,
    );
  });
}
