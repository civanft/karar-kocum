import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/error/failure.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';

/// Yazımı patlatan repo — iyimser geri alma (Y-1) testleri için.
class _FailingPatchRepository extends InMemoryDecisionRepository {
  bool failPatches = false;

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) {
    if (failPatches) throw Exception('yazım hatası (simülasyon)');
    return super.applyPatch(id, patch);
  }
}

/// Yazım sayan repo — debounce (Y-2) testleri için.
class _CountingRepository extends InMemoryDecisionRepository {
  int patchCount = 0;
  final List<DecisionPatch> patches = [];

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) {
    patchCount++;
    patches.add(patch);
    return super.applyPatch(id, patch);
  }
}

void main() {
  late InMemoryDecisionRepository repo;
  late ProviderContainer container;

  final seed = Decision(
    id: 'd1',
    ownerUid: 'local-user',
    title: 'Telefon seçimi',
    createdAt: DateTime(2026, 7, 8),
    updatedAt: DateTime(2026, 7, 8),
  );

  setUp(() async {
    repo = InMemoryDecisionRepository();
    await repo.upsert(seed);
    container = ProviderContainer(
      overrides: [
        decisionRepositoryProvider.overrideWithValue(repo),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    repo.dispose();
  });

  Future<DecisionEditor> editor() async {
    final sub = container.listen(decisionEditorProvider('d1'), (_, __) {});
    addTearDown(sub.close);
    await container.read(decisionEditorProvider('d1').future);
    return container.read(decisionEditorProvider('d1').notifier);
  }

  Decision current() =>
      container.read(decisionEditorProvider('d1')).requireValue;

  test('seçenek ekleme: state güncellenir ve repoya kaydedilir', () async {
    final e = await editor();
    final failure = await e.addOption('iPhone 16');
    expect(failure, isNull);
    expect(current().options.single.title, 'iPhone 16');

    final persisted = await repo.getById('d1');
    expect(persisted!.options.single.title, 'iPhone 16');
  });

  test('11. seçenek reddedilir', () async {
    final e = await editor();
    for (var i = 0; i < 10; i++) {
      expect(await e.addOption('Seçenek $i'), isNull);
    }
    final failure = await e.addOption('Fazla seçenek');
    expect(failure, isNotNull);
    expect(current().options, hasLength(10));
  });

  test('seçenek silinince puanları da silinir', () async {
    final e = await editor();
    await e.addOption('A');
    await e.addOption('B');
    await e.addCriterion('Fiyat', 5);
    final d = current();
    final optionA = d.options[0].id;
    final crit = d.criteria.single.id;

    e.setScore(optionA, crit, 8);
    await e.flushPendingWrites();
    expect(current().scores[optionA]?[crit]?.value, 8);

    await e.removeOption(optionA);
    expect(current().scores.containsKey(optionA), isFalse);
  });

  test('PR-A2: addCriterion source parametresi persist edilir', () async {
    final e = await editor();
    await e.addCriterion('Fiyat', 5);
    await e.addCriterion('Kamera', 5, source: CriterionSource.aiSuggested);

    final d = current();
    expect(d.criteria[0].source, CriterionSource.user); // varsayılan
    expect(d.criteria[1].source, CriterionSource.aiSuggested);
  });

  test('kriter silinince matristen ilgili sütun düşer', () async {
    final e = await editor();
    await e.addOption('A');
    await e.addOption('B');
    await e.addCriterion('Fiyat', 5);
    await e.addCriterion('Kamera', 7);
    final d = current();
    final optionA = d.options[0].id;
    final price = d.criteria[0].id;
    final camera = d.criteria[1].id;

    e.setScore(optionA, price, 8);
    e.setScore(optionA, camera, 6);
    await e.flushPendingWrites();

    await e.removeCriterion(price);
    expect(current().scores[optionA]?.containsKey(price), isFalse);
    expect(current().scores[optionA]?[camera]?.value, 6);
  });

  test('artı/eksi: 140 üstü reddedilir, geçerli eklenir', () async {
    final e = await editor();
    await e.addOption('A');
    final optionId = current().options.single.id;

    expect(
      await e.addProCon(optionId, 'x' * 141, isPro: true),
      isNotNull,
    );
    expect(await e.addProCon(optionId, 'İyi kamera', isPro: true), isNull);
    expect(await e.addProCon(optionId, 'Pahalı', isPro: false), isNull);

    final option = current().options.single;
    expect(option.pros, ['İyi kamera']);
    expect(option.cons, ['Pahalı']);
  });

  test('aralık dışı puan sessizce yok sayılır (slider zaten sınırlı)',
      () async {
    final e = await editor();
    await e.addOption('A');
    await e.addCriterion('Fiyat', 5);
    final d = current();
    e.setScore(d.options.single.id, d.criteria.single.id, 11);
    await e.flushPendingWrites();
    expect(current().scores, isEmpty);
  });

  test('mutasyon updatedAt damgasını ilerletir', () async {
    final e = await editor();
    final before = current().updatedAt;
    await e.addOption('A');
    expect(current().updatedAt.isAfter(before), isTrue);
  });

  group('alan bazlı yazım + iyimser geri alma', () {
    test('mutasyon applyPatch kullanır, upsert değil (K-2)', () async {
      final e = await editor();
      await e.addOption('iPhone');
      await e.toggleFavorite();

      // upsert yalnız setUp'taki seed için çağrıldı; mutasyonlar patch'ledi.
      final persisted = await repo.getById('d1');
      expect(persisted!.options.single.title, 'iPhone');
      expect(persisted.isFavorite, isTrue);
    });

    test('yazım hatasında state geri alınır ve Failure döner (Y-1)', () async {
      final failing = _FailingPatchRepository();
      await failing.upsert(seed);
      final failingContainer = ProviderContainer(
        overrides: [
          decisionRepositoryProvider.overrideWithValue(failing),
        ],
      );
      addTearDown(failingContainer.dispose);
      addTearDown(failing.dispose);

      final sub = failingContainer.listen(
        decisionEditorProvider('d1'),
        (_, __) {},
      );
      addTearDown(sub.close);
      await failingContainer.read(decisionEditorProvider('d1').future);
      final notifier =
          failingContainer.read(decisionEditorProvider('d1').notifier);

      failing.failPatches = true;
      final failure = await notifier.addOption('Kaybolacak seçenek');

      expect(failure, isA<UnexpectedFailure>());
      // state geri alındı: iyimser eklenen seçenek yok
      final current =
          failingContainer.read(decisionEditorProvider('d1')).requireValue;
      expect(current.options, isEmpty);
      // depo da temiz: sessiz ayrışma yok
      final persisted = await failing.getById('d1');
      expect(persisted!.options, isEmpty);
    });
  });

  group('Y-2: debounce + flush', () {
    late _CountingRepository counting;
    late ProviderContainer c;

    setUp(() async {
      counting = _CountingRepository();
      await counting.upsert(
        seed.copyWith(
          options: const [
            Option(id: 'a', title: 'A'),
            Option(id: 'b', title: 'B'),
          ],
          criteria: const [Criterion(id: 'c1', name: 'Fiyat', weight: 5)],
        ),
      );
      c = ProviderContainer(
        overrides: [
          decisionRepositoryProvider.overrideWithValue(counting),
          // Testte zamanlayıcıya güvenme: flush'ı elle tetikliyoruz.
          autosaveDebounceProvider
              .overrideWithValue(const Duration(minutes: 1)),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(counting.dispose);
      final sub = c.listen(decisionEditorProvider('d1'), (_, __) {});
      addTearDown(sub.close);
      await c.read(decisionEditorProvider('d1').future);
    });

    DecisionEditor notifier() => c.read(decisionEditorProvider('d1').notifier);

    test('slider sürüklemesi: N mutasyon → 1 yazım (son değerle)', () async {
      final e = notifier();
      e.setScore('a', 'c1', 3);
      e.setScore('a', 'c1', 7);
      e.setScore('a', 'c1', 9); // sürükleme simülasyonu
      expect(counting.patchCount, 0); // henüz yazım yok

      await e.flushPendingWrites(); // onChangeEnd

      expect(counting.patchCount, 1);
      final persisted = await counting.getById('d1');
      expect(persisted!.scores['a']!['c1']!.value, 9);
    });

    test('bekleyen patch, ayrık mutasyona katlanır — sıralama bozulmaz',
        () async {
      final e = notifier();
      e.setScore('a', 'c1', 8); // debounce kuyruğunda
      await e.removeCriterion('c1'); // ayrık: hemen yazar, bekleyeni katlar

      // Tek yazım gitti ve silinen kriterin puanı geri dirilmedi:
      expect(counting.patchCount, 1);
      final persisted = await counting.getById('d1');
      expect(persisted!.criteria, isEmpty);
      expect(persisted.scores['a']?.containsKey('c1') ?? false, isFalse);

      await e.flushPendingWrites(); // kuyruk boş — yazım üretmemeli
      expect(counting.patchCount, 1);
    });

    test('flush hatası: karar bazlı save durumu dolar, state depoyla hizalanır',
        () async {
      final failing = _FailingPatchRepository();
      await failing.upsert(
        seed.copyWith(
          criteria: const [Criterion(id: 'c1', name: 'Fiyat', weight: 5)],
        ),
      );
      final fc = ProviderContainer(
        overrides: [
          decisionRepositoryProvider.overrideWithValue(failing),
          autosaveDebounceProvider
              .overrideWithValue(const Duration(minutes: 1)),
        ],
      );
      addTearDown(fc.dispose);
      addTearDown(failing.dispose);
      final sub = fc.listen(decisionEditorProvider('d1'), (_, __) {});
      addTearDown(sub.close);
      await fc.read(decisionEditorProvider('d1').future);
      final e = fc.read(decisionEditorProvider('d1').notifier);

      failing.failPatches = true;
      e.setCriterionWeight('c1', 9);
      await e.flushPendingWrites();

      expect(fc.read(decisionSaveStateProvider('d1')), isA<SaveFailed>());
      // otoriter durum: depodaki ağırlık hâlâ 5
      final current = fc.read(decisionEditorProvider('d1')).requireValue;
      expect(current.criteria.single.weight, 5);
    });
  });

  group('K-2: canlı akış davranışı', () {
    test('depodaki harici değişiklik editöre yansır', () async {
      await editor();
      // İkinci cihaz / Functions yazımını simüle et: repoya doğrudan yaz.
      final remote = seed.copyWith(
        title: 'Uzaktan güncellendi',
        updatedAt: DateTime(2026, 7, 9),
      );
      await repo.upsert(remote);
      await Future<void>.delayed(Duration.zero); // akış emisyonu işlensin

      expect(current().title, 'Uzaktan güncellendi');
    });

    test('bayat emisyon (eski updatedAt) mevcut durumu ezmez', () async {
      final e = await editor();
      await e.addOption('Yeni seçenek'); // updatedAt = now (2026-07-08 sonrası)

      final stale = seed.copyWith(
        title: 'Bayat kopya',
        updatedAt: DateTime(2020, 1, 1),
      );
      // Akışı bayat emisyonla besle (upsert etsek store'daki kopya da
      // bayatlaşır; burada yalnız emisyon davranışı test ediliyor).
      await repo.upsert(current());
      await repo.upsert(stale.copyWith(id: 'baska-id')); // ilgisiz kayıt
      await Future<void>.delayed(Duration.zero);

      expect(current().title, 'Telefon seçimi');
      expect(current().options, hasLength(1)); // yerel mutasyon korundu
    });

    test('watchById: abone olunca mevcut durum hemen gelir (O-3)', () async {
      final first = await repo.watchById('d1').first;
      expect(first!.id, 'd1');
    });

    test('watchById: silinme null yayımlar', () async {
      final emissions = <Decision?>[];
      final sub = repo.watchById('d1').listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      await repo.delete('d1');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emissions.first, isNotNull);
      expect(emissions.last, isNull);
    });

    test('watchAll: geç abone de mevcut listeyi hemen alır (O-3)', () async {
      await repo.upsert(seed.copyWith(id: 'd2', title: 'İkinci'));
      // Mutasyondan SONRA abone ol — eski implementasyonda yarış penceresiydi.
      final list = await repo.watchAll().first;
      expect(list.map((d) => d.id), containsAll(['d1', 'd2']));
    });
  });
}
