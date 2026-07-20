import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';

/// Sprint B — editor commitDecision/revertDecision davranışı.
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
      title: 'Telefon kararı',
      initialOptions: const ['iPhone', 'Samsung'],
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    await container.read(decisionEditorProvider(decision.id).future);
    return decision.id;
  }

  test('commitDecision: geçerli seçenek → decided + chosenOptionId + decidedAt',
      () async {
    final id = await makeDecision();
    final editor = container.read(decisionEditorProvider(id).notifier);
    final optionId =
        container.read(decisionEditorProvider(id)).requireValue.options[1].id;

    await editor.commitDecision(optionId);

    final d = container.read(decisionEditorProvider(id)).requireValue;
    expect(d.isDecided, isTrue);
    expect(d.chosenOptionId, optionId);
    expect(d.decidedAt, isNotNull);
  });

  test('commitDecision: GEÇERSIZ seçenek id → dokunmaz (open kalır)', () async {
    final id = await makeDecision();
    final editor = container.read(decisionEditorProvider(id).notifier);

    await editor.commitDecision('olmayan-id');

    expect(
      container.read(decisionEditorProvider(id)).requireValue.isDecided,
      isFalse,
    );
  });

  test('revertDecision: decided → open, alanlar temizlenir', () async {
    final id = await makeDecision();
    final editor = container.read(decisionEditorProvider(id).notifier);
    final optionId =
        container.read(decisionEditorProvider(id)).requireValue.options[0].id;
    await editor.commitDecision(optionId);
    expect(
      container.read(decisionEditorProvider(id)).requireValue.isDecided,
      isTrue,
    );

    await editor.revertDecision();

    final d = container.read(decisionEditorProvider(id)).requireValue;
    expect(d.decisionStatus, DecisionCommitStatus.open);
    expect(d.chosenOptionId, isNull);
    expect(d.decidedAt, isNull);
  });

  test('seçim değiştirme: farklı seçeneğe yeniden commit', () async {
    final id = await makeDecision();
    final editor = container.read(decisionEditorProvider(id).notifier);
    final opts =
        container.read(decisionEditorProvider(id)).requireValue.options;

    await editor.commitDecision(opts[0].id);
    await editor.commitDecision(opts[1].id);

    expect(
      container.read(decisionEditorProvider(id)).requireValue.chosenOptionId,
      opts[1].id,
    );
  });
}
