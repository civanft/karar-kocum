import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/domain/usecases/suggest_criteria.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/criterion_suggestions.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';

/// criterionSuggestionsProvider (SPRINT-A §4.2): editör durumuna reaktif;
/// kriter eklenince öneri düşer; 6+ kriterde boş; dismiss ekran-ömrü.
void main() {
  late ProviderContainer container;

  Future<String> makeDecision({String title = 'iPhone mu Samsung mu?'}) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: title,
    );
    final decision =
        result.when(ok: (d) => d, err: (f) => fail('karar oluşmadı'));
    // editör durumunun oturması için ilk kareyi bekle
    await container.read(decisionEditorProvider(decision.id).future);
    return decision.id;
  }

  test('telefon başlığı → telefon kümesi önerilir', () async {
    final id = await makeDecision();
    final suggestions = container.read(criterionSuggestionsProvider(id));
    expect(suggestions, isNotEmpty);
    expect(suggestions.map((s) => s.name), contains('Fiyat'));
  });

  test('kriter eklenince öneri listesi reaktif küçülür', () async {
    final id = await makeDecision();
    final before = container.read(criterionSuggestionsProvider(id));
    expect(before.map((s) => s.name), contains('Fiyat'));

    await container
        .read(decisionEditorProvider(id).notifier)
        .addCriterion('Fiyat', 5);

    final after = container.read(criterionSuggestionsProvider(id));
    expect(after.map((s) => s.name), isNot(contains('Fiyat')));
    expect(after.length, before.length - 1);
  });

  test('6+ kriterde öneri listesi boşalır (gürültü freni)', () async {
    final id = await makeDecision();
    final editor = container.read(decisionEditorProvider(id).notifier);
    for (final name in ['K1', 'K2', 'K3', 'K4', 'K5', 'K6']) {
      await editor.addCriterion(name, 5);
    }
    expect(container.read(criterionSuggestionsProvider(id)), isEmpty);
  });

  test('dismiss: şerit gizlenir (ekran-ömrü state)', () async {
    final id = await makeDecision();
    expect(container.read(suggestionsDismissedProvider(id)), isFalse);
    container.read(suggestionsDismissedProvider(id).notifier).state = true;
    expect(container.read(suggestionsDismissedProvider(id)), isTrue);
  });

  test('templateId dolu kararda şablon kriterleri önde', () async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: 'Hangi telefonu almalıyım?',
      templateId: 'phone-purchase',
      initialCriteria: const [(name: 'Fiyat', weight: 8)],
    );
    final decision =
        result.when(ok: (d) => d, err: (f) => fail('karar oluşmadı'));
    await container.read(decisionEditorProvider(decision.id).future);

    // 'Fiyat' zaten ekli (şablondan) → önerilmez; şablonun eklenmemiş
    // kriterleri (Kamera, Pil ömrü...) template kaynaklı önde gelir.
    final suggestions =
        container.read(criterionSuggestionsProvider(decision.id));
    expect(suggestions.map((s) => s.name), isNot(contains('Fiyat')));
    expect(suggestions.first.origin, SuggestionOrigin.template);
  });
}
