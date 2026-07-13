import '../entities/decision_template.dart';

/// Şablon kataloğu sözleşmesi — decision_repository.dart kalıbı.
/// v1 implementasyonu statiktir (data/static_template_catalog.dart);
/// uzaktan katalog (Firestore templates/) v2'de bu arayüzü uygular.
abstract interface class TemplateCatalog {
  List<DecisionTemplate> all();

  DecisionTemplate? byId(String id);
}
