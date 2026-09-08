import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';

/// İŞ PAKETİ 4 / DİLİM D — "Sonucu Gör" flush kapısı.
///
/// Eskiden düğme doğrudan navigasyon yapıyordu: debounce'lu bir skor
/// değişikliği henüz yazılmamışken sonuç ekranı ESKİ veriyle açılabiliyordu.
class _FakeRepository implements DecisionRepository {
  _FakeRepository(this._decision);
  Decision _decision;
  bool failNextPatch = false;
  int patchCalls = 0;
  Completer<void>? gate;

  @override
  Future<Decision?> getById(String id) async => _decision;

  @override
  Stream<Decision?> watchById(String id) => const Stream.empty();

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) async {
    patchCalls++;
    if (gate != null) await gate!.future;
    if (failNextPatch) {
      failNextPatch = false;
      throw StateError('offline');
    }
    _decision = _decision.copyWith(updatedAt: DateTime.now());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeRepository repo;

  Future<DecisionEditor> editor(ProviderContainer c) async {
    final sub = c.listen(decisionEditorProvider('d1'), (_, __) {});
    addTearDown(sub.close);
    await c.read(decisionEditorProvider('d1').future);
    return c.read(decisionEditorProvider('d1').notifier);
  }

  ProviderContainer make() {
    repo = _FakeRepository(
      Decision(
        id: 'd1',
        ownerUid: 'u1',
        title: 'Karar',
        options: const [],
        criteria: const [],
        scores: const {},
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    final c = ProviderContainer(
      overrides: [
        decisionRepositoryProvider.overrideWithValue(repo),
        autosaveDebounceProvider.overrideWithValue(
          const Duration(minutes: 5), // debounce KENDİLİĞİNDEN tetiklenmesin
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('flush BAŞARISIZ ise gate açılmaz (failure döner)', () async {
    final c = make();
    final e = await editor(c);
    e.setCriterionWeight('c1', 5);
    repo.failNextPatch = true;

    final failure = await e.flushPendingWrites();

    expect(failure, isNotNull);
    expect(c.read(decisionSaveStateProvider('d1')), isA<SaveFailed>());
  });

  test('flush BAŞARILI ise gate açılır (null döner) ve TEK yazım olur',
      () async {
    final c = make();
    final e = await editor(c);
    e.setCriterionWeight('c1', 5);

    expect(await e.flushPendingWrites(), isNull);
    expect(repo.patchCalls, 1);
  });

  test('bekleyen niyet yokken flush yazım YAPMAZ', () async {
    final c = make();
    final e = await editor(c);
    expect(await e.flushPendingWrites(), isNull);
    expect(repo.patchCalls, 0);
  });

  test('AYNI niyet için eşzamanlı iki flush TEK yazım üretir', () async {
    final c = make();
    final e = await editor(c);
    e.setCriterionWeight('c1', 5);
    repo.gate = Completer<void>();

    final a = e.flushPendingWrites();
    final b = e.flushPendingWrites();
    repo.gate!.complete();
    final results = await Future.wait([a, b]);

    expect(repo.patchCalls, 1);
    expect(results.every((r) => r == null), isTrue);
  });
}
