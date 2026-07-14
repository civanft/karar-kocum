import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/services/analytics/analytics_service.dart';
import 'package:karar_veriyorum/core/services/id_generator.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/usecases/create_decision.dart';
import 'package:karar_veriyorum/features/templates/data/static_template_catalog.dart';
import 'package:karar_veriyorum/features/templates/presentation/providers/template_decision_creator.dart';

/// Sheet'ten AYRILAN iş mantığı (coverage kapanışı): şablondan karar
/// oluşturma + analytics + 'Boş başla' rotası — widget'sız birim testler.
class _RecordingAnalytics extends NoopAnalyticsService {
  final events = <String>[];

  @override
  Future<void> logTemplateSelected({required String templateId}) async {
    events.add('template_selected:$templateId');
  }

  @override
  Future<void> logDecisionCreated({required String source}) async {
    events.add('decision_created:$source');
  }
}

void main() {
  final template = const StaticTemplateCatalog().byId('phone-purchase')!;

  late InMemoryDecisionRepository repo;
  late _RecordingAnalytics analytics;
  late TemplateDecisionCreator creator;

  setUp(() {
    repo = InMemoryDecisionRepository();
    analytics = _RecordingAnalytics();
    creator = TemplateDecisionCreator(
      CreateDecision(repo, IdGenerator()),
      analytics,
    );
  });

  tearDown(() => repo.dispose());

  test('başarı: karar şablon içeriğiyle oluşur, id döner', () async {
    final id = await creator(
      ownerUid: 'u1',
      title: 'Pixel mi iPhone mu?',
      template: template,
    );

    expect(id, isNotNull);
    final decision = await repo.getById(id!);
    expect(decision, isNotNull);
    expect(decision!.title, 'Pixel mi iPhone mu?');
    expect(decision.templateId, 'phone-purchase');
    expect(decision.criteria.length, template.criteria.length);
    expect(
      decision.criteria.map((c) => c.name),
      template.criteria.map((c) => c.name),
    );
    expect(
      decision.criteria.map((c) => c.weight),
      template.criteria.map((c) => c.weight),
    );
    expect(
      decision.options.map((o) => o.title),
      template.sampleOptions,
    );
  });

  test('başarı: analytics olayları doğru sırayla loglanır', () async {
    await creator(ownerUid: 'u1', title: 'Geçerli başlık', template: template);

    expect(analytics.events, [
      'template_selected:phone-purchase',
      'decision_created:template',
    ]);
  });

  test('hata: geçersiz başlıkta null döner, yazım YOK, analytics YOK',
      () async {
    final id = await creator(
      ownerUid: 'u1',
      title: 'ab', // < min 3
      template: template,
    );

    expect(id, isNull);
    expect(analytics.events, isEmpty);

    var count = 0;
    final sub = repo.watchAll().listen((list) => count = list.length);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(count, 0);
  });

  group('blankStartLocation (Boş başla rotası)', () {
    test('başlığı query parametresiyle /decision/new rotası kurar', () {
      expect(
        TemplateDecisionCreator.blankStartLocation('Tatil planı'),
        '/decision/new?title=Tatil+plan%C4%B1',
      );
    });

    test('Türkçe karakter ve soru işareti güvenle kodlanır', () {
      final location =
          TemplateDecisionCreator.blankStartLocation('iPhone mu Samsung mu?');
      final uri = Uri.parse(location);
      expect(uri.path, '/decision/new');
      expect(uri.queryParameters['title'], 'iPhone mu Samsung mu?');
    });
  });
}
