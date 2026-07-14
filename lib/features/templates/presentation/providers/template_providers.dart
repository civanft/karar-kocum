import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/static_template_catalog.dart';
import '../../domain/entities/decision_template.dart';
import '../../domain/repositories/template_catalog.dart';

/// v1: statik katalog. v2'de uzaktan katalog bu provider'ı override eder.
final templateCatalogProvider =
    Provider<TemplateCatalog>((_) => const StaticTemplateCatalog());

final templateByIdProvider = Provider.family<DecisionTemplate?, String>(
  (ref, id) => ref.watch(templateCatalogProvider).byId(id),
);
