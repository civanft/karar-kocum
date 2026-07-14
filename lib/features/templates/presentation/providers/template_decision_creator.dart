import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/analytics/analytics_service.dart';
import '../../../decision/domain/usecases/create_decision.dart';
import '../../../decision/presentation/providers/decision_providers.dart';
import '../../domain/entities/decision_template.dart';

/// Şablondan karar oluşturma İŞ MANTIĞI — sheet'ten ayrık (Sprint A
/// kapanış denetimi: widget yaşam döngüsüne hapsolmuş mantık birim
/// testlenemiyordu). Sheet yalnız durum + navigasyon tutar; kayıt
/// kurulumu, oluşturma çağrısı ve analytics burada yaşar.
class TemplateDecisionCreator {
  const TemplateDecisionCreator(this._createDecision, this._analytics);

  final CreateDecision _createDecision;
  final AnalyticsService _analytics;

  /// Başarıda oluşturulan kararın id'si, hatada null (sheet hata metnini
  /// kendisi gösterir — davranış birebir korunur).
  Future<String?> call({
    required String ownerUid,
    required String title,
    required DecisionTemplate template,
  }) async {
    final result = await _createDecision(
      ownerUid: ownerUid,
      title: title,
      templateId: template.id,
      initialCriteria: [
        for (final c in template.criteria) (name: c.name, weight: c.weight),
      ],
      initialOptions: template.sampleOptions,
    );

    return result.when(
      ok: (decision) {
        unawaited(_analytics.logTemplateSelected(templateId: template.id));
        unawaited(_analytics.logDecisionCreated(source: 'template'));
        return decision.id;
      },
      err: (_) => null,
    );
  }

  /// 'Boş başla' hedef rotası — başlık query-encode edilir (saf, testli).
  static String blankStartLocation(String title) => Uri(
        path: '/decision/new',
        queryParameters: {'title': title},
      ).toString();
}

final templateDecisionCreatorProvider = Provider<TemplateDecisionCreator>(
  (ref) => TemplateDecisionCreator(
    ref.watch(createDecisionProvider),
    ref.watch(analyticsServiceProvider),
  ),
);
