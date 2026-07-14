import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/scoring_progress.dart';

/// scoringProgressProvider (SPRINT-A §4.2): sayılar doğru türetilir;
/// select sayesinde AYNI hücrede değer değişimi rebuild ÜRETMEZ.
void main() {
  late ProviderContainer container;

  Future<String> makeDecision() async {
    container = ProviderContainer(
      overrides: [
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: 'Puanlama testi',
      initialCriteria: const [(name: 'K1', weight: 5), (name: 'K2', weight: 5)],
      initialOptions: const ['A', 'B'],
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    await container.read(decisionEditorProvider(decision.id).future);
    return decision.id;
  }

  test('başlangıç: 0/4', () async {
    final id = await makeDecision();
    final progress = container.read(scoringProgressProvider(id));
    expect(progress.filled, 0);
    expect(progress.total, 4);
  });

  test('setScore sonrası filled artar; aynı hücreye ikinci yazım artırmaz',
      () async {
    final id = await makeDecision();
    final editor = container.read(decisionEditorProvider(id).notifier);
    final d = container.read(decisionEditorProvider(id)).requireValue;
    final optionA = d.options[0].id;
    final k1 = d.criteria[0].id;

    editor.setScore(optionA, k1, 7);
    expect(container.read(scoringProgressProvider(id)).filled, 1);

    editor.setScore(optionA, k1, 9); // aynı hücre — sayı değişmez
    expect(container.read(scoringProgressProvider(id)).filled, 1);
  });

  test('removeCriterion: filled ve total birlikte düşer', () async {
    final id = await makeDecision();
    final editor = container.read(decisionEditorProvider(id).notifier);
    final d = container.read(decisionEditorProvider(id)).requireValue;
    editor.setScore(d.options[0].id, d.criteria[0].id, 7);
    expect(container.read(scoringProgressProvider(id)).filled, 1);

    await editor.removeCriterion(d.criteria[0].id);

    final progress = container.read(scoringProgressProvider(id));
    expect(progress.total, 2); // 2 seçenek × 1 kriter
    expect(progress.filled, 0); // puan kriteriyle birlikte gitti
  });

  test('select: aynı hücrede değer değişimi provider\'ı YENİDEN üretmez',
      () async {
    final id = await makeDecision();
    final editor = container.read(decisionEditorProvider(id).notifier);
    final d = container.read(decisionEditorProvider(id)).requireValue;
    final optionA = d.options[0].id;
    final k1 = d.criteria[0].id;

    editor.setScore(optionA, k1, 5);

    var rebuilds = 0;
    final sub = container.listen(
      scoringProgressProvider(id),
      (_, __) => rebuilds++,
    );
    addTearDown(sub.close);

    // Aynı hücrede 6→7→8: sayı (1/4) değişmiyor → sıfır bildirim.
    // (Riverpod dinleyici bildirimi mikrotask'ta — flush için bekle.)
    editor.setScore(optionA, k1, 6);
    editor.setScore(optionA, k1, 7);
    editor.setScore(optionA, k1, 8);
    await Future<void>.delayed(Duration.zero);
    expect(rebuilds, 0);

    // Yeni hücre: 2/4 → tek bildirim.
    editor.setScore(optionA, d.criteria[1].id, 5);
    await Future<void>.delayed(Duration.zero);
    expect(rebuilds, 1);
  });
}
