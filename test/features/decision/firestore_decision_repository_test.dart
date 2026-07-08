import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/data/dtos/decision_firestore_mapper.dart';
import 'package:karar_veriyorum/features/decision/data/dtos/timestamp_converter.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/firestore_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreDecisionRepository repo;

  const uid = 'test-user';
  final now = DateTime(2026, 7, 8, 12);

  Decision decision({String id = 'd1', String title = 'Telefon seçimi'}) =>
      Decision(
        id: id,
        ownerUid: uid,
        title: title,
        options: const [
          Option(id: 'a', title: 'iPhone', pros: ['Kamera'], cons: ['Fiyat']),
          Option(id: 'b', title: 'Samsung'),
        ],
        criteria: const [Criterion(id: 'c1', name: 'Fiyat', weight: 8)],
        scores: const {
          'a': {'c1': CellScore(value: 6)},
          'b': {'c1': CellScore(value: 9, source: ScoreSource.ai)},
        },
        createdAt: now,
        updatedAt: now,
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FirestoreDecisionRepository(firestore, uid: uid);
  });

  group('upsert + getById', () {
    test('gidiş-dönüş kayıpsız (iç içe yapılar dahil)', () async {
      await repo.upsert(decision());
      final restored = await repo.getById('d1');

      expect(restored, isNotNull);
      expect(restored!.title, 'Telefon seçimi');
      expect(restored.options, hasLength(2));
      expect(restored.options.first.pros, ['Kamera']);
      expect(restored.scores['b']!['c1']!.source, ScoreSource.ai);
      expect(restored.criteria.single.weight, 8);
    });

    test('ownerUid entity ne derse desin yazan kullanıcıya zorlanır (Y-5)',
        () async {
      final sahte = decision().copyWith(ownerUid: 'baskasi');
      await repo.upsert(sahte);

      final raw =
          await firestore.collection('users/$uid/decisions').doc('d1').get();
      expect(raw.data()!['ownerUid'], uid);
    });

    test('yazımda searchTokens üretilir, okumada entity\'ye sızmaz', () async {
      await repo.upsert(decision(title: 'iPhone mu Samsung mu?'));
      final raw =
          await firestore.collection('users/$uid/decisions').doc('d1').get();

      expect(
        List<String>.from(raw.data()!['searchTokens'] as List),
        containsAll(['iphone', 'samsung', 'mu']),
      );
      // okumada entity bozulmaz:
      expect(await repo.getById('d1'), isNotNull);
    });

    test('updatedAt Firestore Timestamp olarak yazılır (Y-4)', () async {
      await repo.upsert(decision());
      final raw =
          await firestore.collection('users/$uid/decisions').doc('d1').get();
      expect(raw.data()!['updatedAt'], isA<Timestamp>());
      expect(raw.data()!['createdAt'], isA<Timestamp>());
    });

    test('olmayan belge null döner', () async {
      expect(await repo.getById('yok'), isNull);
    });
  });

  group('applyPatch (K-2 alan bazlı yazım)', () {
    test('yalnız patch\'teki alanlar değişir, diğerleri korunur', () async {
      await repo.upsert(decision());

      await repo.applyPatch('d1', const DecisionPatch(isFavorite: true));
      final after = await repo.getById('d1');

      expect(after!.isFavorite, isTrue);
      expect(after.title, 'Telefon seçimi'); // dokunulmadı
      expect(after.options, hasLength(2)); // dokunulmadı
      expect(after.scores['a']!['c1']!.value, 6); // dokunulmadı
    });

    test('başlık patch\'i searchTokens\'ı da yeniler', () async {
      await repo.upsert(decision());
      await repo.applyPatch(
        'd1',
        const DecisionPatch(title: 'Araba mı motosiklet mi?'),
      );

      final raw =
          await firestore.collection('users/$uid/decisions').doc('d1').get();
      expect(
        List<String>.from(raw.data()!['searchTokens'] as List),
        containsAll(['araba', 'motosiklet']),
      );
      expect(raw.data()!['title'], 'Araba mı motosiklet mi?');
    });

    test('sunucu-sahipli alan patch yolundan YAZILAMAZ: patch şemasında yok',
        () async {
      // Derleme-zamanı garantisi: DecisionPatch'te latestAnalysisId alanı
      // bulunmaz. Çalışma-zamanı karşılığı: patch haritasında anahtar yok.
      final map = DecisionFirestoreMapper.patchToFirestore(
        const DecisionPatch(title: 'Yeni'),
      );
      expect(map.keys, isNot(contains('latestAnalysisId')));
      expect(map.keys, isNot(contains('status'))); // status patch'te verilmedi
    });

    test('olmayan belgeye patch StateError fırlatır', () async {
      expect(
        () => repo.applyPatch('yok', const DecisionPatch(isFavorite: true)),
        throwsStateError,
      );
    });

    test('boş patch yazım üretmez', () async {
      await repo.upsert(decision());
      final before =
          await firestore.collection('users/$uid/decisions').doc('d1').get();

      await repo.applyPatch('d1', const DecisionPatch());

      final after =
          await firestore.collection('users/$uid/decisions').doc('d1').get();
      expect(after.data()!['updatedAt'], before.data()!['updatedAt']);
    });
  });

  group('akışlar (K-2)', () {
    test('watchAll: abone olunca mevcut liste hemen gelir', () async {
      await repo.upsert(decision());
      await repo.upsert(decision(id: 'd2', title: 'İkinci karar'));

      final list = await repo.watchAll().first;
      expect(list.map((d) => d.id), containsAll(['d1', 'd2']));
    });

    test('watchById: harici yazım emisyon üretir', () async {
      await repo.upsert(decision());
      final emissions = <String>[];
      final sub = repo
          .watchById('d1')
          .listen((d) => emissions.add(d?.title ?? '(silindi)'));

      await Future<void>.delayed(Duration.zero);
      await repo.applyPatch('d1', const DecisionPatch(title: 'Güncellendi'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emissions.first, 'Telefon seçimi');
      expect(emissions.last, 'Güncellendi');
    });

    test('watchById: silinme null yayımlar', () async {
      await repo.upsert(decision());
      final emissions = <Decision?>[];
      final sub = repo.watchById('d1').listen(emissions.add);

      await Future<void>.delayed(Duration.zero);
      await repo.delete('d1');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emissions.first, isNotNull);
      expect(emissions.last, isNull);
    });
  });

  group('TimestampConverter', () {
    const converter = TimestampConverter();

    test('Timestamp, ISO string ve epoch ms okunur', () {
      final date = DateTime(2026, 7, 8, 12);
      expect(converter.fromJson(Timestamp.fromDate(date)), date);
      expect(converter.fromJson(date.toIso8601String()), date);
      expect(
        converter.fromJson(date.millisecondsSinceEpoch),
        date,
      );
    });

    test('null (bekleyen serverTimestamp) now yedeğine düşer', () {
      final before = DateTime.now();
      final result = converter.fromJson(null);
      expect(result.isBefore(before), isFalse);
    });

    test('bilinmeyen tip ArgumentError', () {
      expect(() => converter.fromJson(3.14), throwsArgumentError);
    });

    test('yazım Timestamp üretir', () {
      expect(converter.toJson(DateTime(2026)), isA<Timestamp>());
    });
  });
}
