import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/error/failure.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';

/// İŞ PAKETİ 4 / DİLİM C — kayıt durum makinesi.
///
/// Eski davranış: debounce yazımı başarısız olunca hata GLOBAL bir
/// `autosaveFailureProvider`'a düşüyordu, hiçbir UI bunu izlemiyordu ve
/// kullanıcı niyeti sessizce kayboluyordu. Dispose yolundaki
/// `silent: true` ise başarısız yazımı hiç görünmeden yutuyordu.
class _FakeRepository implements DecisionRepository {
  _FakeRepository(this._decisions);

  final Map<String, Decision> _decisions;
  final _controllers = <String, StreamController<Decision?>>{};

  /// Bir sonraki applyPatch çağrısını çökertir.
  bool failNextPatch = false;
  int patchCalls = 0;
  final List<DecisionPatch> applied = <DecisionPatch>[];
  Completer<void>? gate;

  @override
  Future<Decision?> getById(String id) async => _decisions[id];

  @override
  Stream<Decision?> watchById(String id) => _controllers
      .putIfAbsent(id, StreamController<Decision?>.broadcast)
      .stream;

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) async {
    patchCalls++;
    if (gate != null) await gate!.future;
    if (failNextPatch) {
      failNextPatch = false;
      throw StateError('firestore unavailable: users/uid/decisions/$id');
    }
    applied.add(patch);
    final current = _decisions[id]!;
    _decisions[id] = current.copyWith(
      title: patch.title ?? current.title,
      isFavorite: patch.isFavorite ?? current.isFavorite,
      updatedAt: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Decision _decision(String id) => Decision(
      id: id,
      ownerUid: 'u1',
      title: 'Başlangıç $id',
      options: const [],
      criteria: const [],
      scores: const {},
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  late _FakeRepository repo;

  ProviderContainer make() {
    repo = _FakeRepository({'d1': _decision('d1'), 'd2': _decision('d2')});
    final container = ProviderContainer(
      overrides: [
        decisionRepositoryProvider.overrideWithValue(repo),
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<DecisionEditor> editor(ProviderContainer c, String id) async {
    final sub = c.listen(decisionEditorProvider(id), (_, __) {});
    addTearDown(sub.close);
    await c.read(decisionEditorProvider(id).future);
    return c.read(decisionEditorProvider(id).notifier);
  }

  SaveState saveState(ProviderContainer c, String id) =>
      c.read(decisionSaveStateProvider(id));

  test('başarısız yazım GÖRÜNÜR failed durumuna düşer, raw exception SIZMAZ',
      () async {
    final c = make();
    final e = await editor(c, 'd1');
    repo.failNextPatch = true;

    await e.toggleFavorite();

    final s = saveState(c, 'd1');
    expect(s, isA<SaveFailed>());
    final message = (s as SaveFailed).message;
    expect(message, isNot(contains('firestore')));
    expect(message, isNot(contains('users/')));
    expect(message, isNotEmpty);
  });

  test('retry başarılı olursa hata yüzeyi KAPANIR ve patch uygulanır',
      () async {
    final c = make();
    final e = await editor(c, 'd1');
    repo.failNextPatch = true;
    await e.toggleFavorite();
    expect(saveState(c, 'd1'), isA<SaveFailed>());

    await e.retrySave();

    expect(saveState(c, 'd1'), isA<SaveIdle>());
    expect(repo.applied.last.isFavorite, isTrue);
  });

  test('iki kararın save durumu birbirine SIZMAZ', () async {
    final c = make();
    final e1 = await editor(c, 'd1');
    await editor(c, 'd2');
    repo.failNextPatch = true;
    await e1.toggleFavorite();

    expect(saveState(c, 'd1'), isA<SaveFailed>());
    expect(saveState(c, 'd2'), isA<SaveIdle>());
  });

  test('flushPendingWrites sonucu GÖZLENEBİLİR biçimde döner', () async {
    final c = make();
    final e = await editor(c, 'd1');
    repo.failNextPatch = true;
    e.setCriterionWeight('c1', 5);

    final failure = await e.flushPendingWrites();

    expect(failure, isA<Failure>());
    expect(saveState(c, 'd1'), isA<SaveFailed>());
  });

  test('başarılı flush null döner', () async {
    final c = make();
    final e = await editor(c, 'd1');
    e.setCriterionWeight('c1', 5);
    expect(await e.flushPendingWrites(), isNull);
    expect(saveState(c, 'd1'), isA<SaveIdle>());
  });

  test('başarısız patch RETRY KUYRUĞUNDA kalır; yeni patch ile BİRLEŞİR',
      () async {
    final c = make();
    final e = await editor(c, 'd1');
    repo.failNextPatch = true;
    await e.toggleFavorite();
    expect(saveState(c, 'd1'), isA<SaveFailed>());

    // Yeni niyet: kriter ağırlığı. Eski başarısız favori DÜŞMEMELİ.
    e.setCriterionWeight('c1', 5);
    await e.flushPendingWrites();

    final last = repo.applied.last;
    expect(last.isFavorite, isTrue);
  });

  test('eşzamanlı iki flush AYNI patch için ÇİFT yazım üretmez', () async {
    final c = make();
    final e = await editor(c, 'd1');
    e.setCriterionWeight('c1', 5);
    repo.gate = Completer<void>();

    final first = e.flushPendingWrites();
    final second = e.flushPendingWrites();
    repo.gate!.complete();
    await Future.wait([first, second]);

    expect(repo.patchCalls, 1);
  });

  test('dispose sırasında bekleyen patch SESSİZCE kaybolmaz', () async {
    final c = make();
    final sub = c.listen(decisionEditorProvider('d1'), (_, __) {});
    await c.read(decisionEditorProvider('d1').future);
    final e = c.read(decisionEditorProvider('d1').notifier);
    e.setCriterionWeight('c1', 5);

    sub.close(); // provider atılır
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Yazım gerçekten gönderilmiş olmalı.
    expect(
      repo.applied.any((p) => p.scores != null || p.criteria != null),
      isTrue,
    );
  });
}
