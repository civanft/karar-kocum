import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/services/analytics/analytics_service.dart';
import '../../../../core/services/crash_reporter.dart';
import '../../domain/entities/decision.dart';
import '../../domain/repositories/decision_repository.dart';
import '../../domain/validators/decision_validator.dart';
import 'decision_providers.dart';

/// Sürekli mutasyonların (slider) yazım birleştirme süresi — audit Y-2.
/// Testler kısa süreyle override eder.
final autosaveDebounceProvider =
    Provider<Duration>((_) => const Duration(milliseconds: 800));

/// Debounce'lu yazım başarısız olursa buraya düşer (UI snackbar'ı Sprint 3
/// cilasında bağlanacak); null = son yazım başarılı.
final autosaveFailureProvider = StateProvider<Failure?>((_) => null);

/// Taslak düzenleme durum makinesi — TEKNIK-MIMARI.md §6.1
/// Her mutasyon: state güncelle → repository'ye kaydet.
/// (Firestore'a geçişte 800 ms debounce eklenecek; in-memory'de gereksiz.)
class DecisionEditor extends AutoDisposeFamilyAsyncNotifier<Decision, String> {
  late DecisionRepository _repo;
  DecisionPatch? _pendingPatch;
  Timer? _debounceTimer;

  @override
  Future<Decision> build(String arg) async {
    final repo = ref.watch(decisionRepositoryProvider);
    _repo = repo;
    ref.onDispose(() {
      _debounceTimer?.cancel();
      // Ekrandan çıkarken bekleyen yazım kaybolmasın (fire-and-forget;
      // ref bu noktadan sonra kullanılamaz, repo alan olarak yakalandı).
      unawaited(_flushPending(silent: true));
    });

    // Audit K-2: tek seferlik okuma yerine canlı akış — harici yazımlar
    // (ikinci cihaz, Sprint 3'te aiAnalysis yazan Functions) editöre yansır.
    // Bayat emisyon koruması: mevcut durumdan ESKİ updatedAt taşıyan
    // emisyonlar yok sayılır (yerel iyimser güncellemeyi ezmesin).
    final sub = repo.watchById(arg).listen((incoming) {
      if (incoming == null) return; // silinme: navigasyon üst katmanın işi
      final current = state.valueOrNull;
      if (current == null || !incoming.updatedAt.isBefore(current.updatedAt)) {
        state = AsyncData(incoming);
      }
    });
    ref.onDispose(sub.cancel);

    final initial = await repo.getById(arg);
    if (initial == null) {
      throw StateError('Karar bulunamadı: $arg');
    }
    // Akış build tamamlanmadan daha yeni bir durum getirdiyse onu koru.
    final streamed = state.valueOrNull;
    if (streamed != null && streamed.updatedAt.isAfter(initial.updatedAt)) {
      return streamed;
    }
    return initial;
  }

  /// İyimser mutasyon (K-2 alan bazlı yazım + geri alma güvenliği):
  ///  1. state hemen güncellenir (UI bekletilmez)
  ///  2. YALNIZ değişen alanlar [DecisionPatch] ile depoya yazılır
  ///     (bekleyen debounce patch'i sıralama bozulmasın diye birleştirilir)
  ///  3. yazım başarısız olursa state geri alınır ve Failure döner
  ///     (audit Y-1: sessiz state/depo ayrışması imkânsız)
  Future<Failure?> _mutate(
    Decision Function(Decision) transform,
    DecisionPatch Function(Decision updated) patchOf,
  ) async {
    final previous = state.valueOrNull;
    if (previous == null) return null;
    final updated = transform(previous).copyWith(updatedAt: DateTime.now());
    state = AsyncData(updated);

    // Bekleyen debounce patch'ini bu yazıma katla — ayrı zamanlayıcıdan
    // sonra gelip daha yeni alanları ezmesin (state zinciri tek sıralı).
    final merged = _mergePatches(_takePending(), patchOf(updated));
    try {
      await ref
          .read(decisionRepositoryProvider)
          .applyPatch(previous.id, merged);
      _trackFunnel(previous, updated);
      return null;
    } catch (error, stackTrace) {
      state = AsyncData(previous); // iyimser güncellemeyi geri al
      unawaited(
        ref.read(crashReporterProvider).recordError(
              error,
              stackTrace,
              reason: 'decision_patch_failed',
            ),
      );
      return UnexpectedFailure(error, stackTrace);
    }
  }

  /// Aktivasyon hunisi (TEKNIK-MIMARI.md §9.1): eşik geçişinde tek atış.
  /// İçerik gönderilmez — yalnız sayısal meta.
  void _trackFunnel(Decision previous, Decision updated) {
    final analytics = ref.read(analyticsServiceProvider);
    if (previous.options.length < 2 && updated.options.length >= 2) {
      unawaited(
        analytics.logOptionsCompleted(optionCount: updated.options.length),
      );
    }
    if (previous.criteria.isEmpty && updated.criteria.isNotEmpty) {
      unawaited(
        analytics.logCriteriaCompleted(
          criterionCount: updated.criteria.length,
          aiSuggestedCount: updated.criteria
              .where((c) => c.source == CriterionSource.aiSuggested)
              .length,
        ),
      );
    }
    if (!previous.isScoreMatrixComplete && updated.isScoreMatrixComplete) {
      unawaited(analytics.logScoringCompleted());
    }
  }

  /// Sürekli mutasyonlar için debounce'lu yol (audit Y-2): state anında,
  /// yazım [autosaveDebounceProvider] süresi doluncaya dek birleştirilir.
  /// Slider onChangeEnd → [flushPendingWrites] anında yazdırır.
  void _mutateDebounced(
    Decision Function(Decision) transform,
    DecisionPatch Function(Decision updated) patchOf,
  ) {
    final previous = state.valueOrNull;
    if (previous == null) return;
    final updated = transform(previous).copyWith(updatedAt: DateTime.now());
    state = AsyncData(updated);

    _pendingPatch = _mergePatches(_pendingPatch, patchOf(updated));
    _trackFunnel(previous, updated);
    _debounceTimer?.cancel();
    _debounceTimer =
        Timer(ref.read(autosaveDebounceProvider), flushPendingWrites);
  }

  /// Bekleyen birleşik yazımı hemen gönderir (slider bırakıldığında,
  /// ekran kapanırken, ya da testlerde deterministik akış için).
  Future<void> flushPendingWrites() => _flushPending(silent: false);

  Future<void> _flushPending({required bool silent}) async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final patch = _takePending();
    if (patch == null || patch.isEmpty) return;
    try {
      await _repo.applyPatch(arg, patch);
    } catch (error, stackTrace) {
      if (silent) return; // dispose yolu: provider'lara erişilemez
      ref.read(autosaveFailureProvider.notifier).state =
          UnexpectedFailure(error, stackTrace);
      // Otoriter duruma yeniden hizalan (iyimser state depoyla ayrışmasın).
      final fresh = await _repo.getById(arg);
      if (fresh != null) state = AsyncData(fresh);
    }
  }

  DecisionPatch? _takePending() {
    final patch = _pendingPatch;
    _pendingPatch = null;
    return patch;
  }

  static DecisionPatch _mergePatches(
    DecisionPatch? older,
    DecisionPatch newer,
  ) {
    if (older == null) return newer;
    return DecisionPatch(
      title: newer.title ?? older.title,
      options: newer.options ?? older.options,
      criteria: newer.criteria ?? older.criteria,
      scores: newer.scores ?? older.scores,
      isFavorite: newer.isFavorite ?? older.isFavorite,
      status: newer.status ?? older.status,
    );
  }

  // ---- Seçenekler (US-A3) ----

  Future<Failure?> addOption(String title) async {
    final failure = DecisionValidator.optionTitle(title);
    if (failure != null) return failure;
    final current = state.valueOrNull;
    if (current == null || !DecisionValidator.canAddOption(current)) {
      return const ValidationFailure(
        field: 'options',
        message: 'En fazla 10 seçenek eklenebilir.',
      );
    }
    final id = ref.read(idGeneratorProvider)();
    return _mutate(
      (d) => d.copyWith(
        options: [...d.options, Option(id: id, title: title.trim())],
      ),
      (u) => DecisionPatch(options: u.options),
    );
  }

  Future<Failure?> removeOption(String optionId) => _mutate(
        (d) => d.copyWith(
          options: d.options.where((o) => o.id != optionId).toList(),
          scores: Map.of(d.scores)..remove(optionId),
        ),
        (u) => DecisionPatch(options: u.options, scores: u.scores),
      );

  Future<Failure?> updateOptionDescription(
    String optionId,
    String? description,
  ) =>
      _mutate(
        (d) => d.copyWith(
          options: [
            for (final o in d.options)
              o.id == optionId
                  ? o.copyWith(description: description?.trim())
                  : o,
          ],
        ),
        (u) => DecisionPatch(options: u.options),
      );

  // ---- Artı / Eksi (US-B1) ----

  Future<Failure?> addProCon(
    String optionId,
    String text, {
    required bool isPro,
  }) async {
    final failure = DecisionValidator.prosConsItem(text);
    if (failure != null) return failure;
    return _mutate(
      (d) => d.copyWith(
        options: [
          for (final o in d.options)
            o.id == optionId
                ? (isPro
                    ? o.copyWith(pros: [...o.pros, text.trim()])
                    : o.copyWith(cons: [...o.cons, text.trim()]))
                : o,
        ],
      ),
      (u) => DecisionPatch(options: u.options),
    );
  }

  Future<Failure?> removeProCon(
    String optionId,
    int index, {
    required bool isPro,
  }) =>
      _mutate(
        (d) => d.copyWith(
          options: [
            for (final o in d.options)
              o.id == optionId
                  ? (isPro
                      ? o.copyWith(
                          pros: [...o.pros]..removeAt(index),
                        )
                      : o.copyWith(cons: [...o.cons]..removeAt(index)))
                  : o,
          ],
        ),
        (u) => DecisionPatch(options: u.options),
      );

  // ---- Kriterler (US-B2) ----

  /// [source]: öneri chip'inden gelen kriter aiSuggested etiketlenir
  /// (PR-A2) — logCriteriaCompleted.aiSuggestedCount hunisi bununla ölçer.
  Future<Failure?> addCriterion(
    String name,
    int weight, {
    CriterionSource source = CriterionSource.user,
  }) async {
    if (name.trim().isEmpty) {
      return const ValidationFailure(
        field: 'criterionName',
        message: 'Kriter adı boş olamaz.',
      );
    }
    final failure = DecisionValidator.criterionWeight(weight);
    if (failure != null) return failure;
    final id = ref.read(idGeneratorProvider)();
    return _mutate(
      (d) => d.copyWith(
        criteria: [
          ...d.criteria,
          Criterion(id: id, name: name.trim(), weight: weight, source: source),
        ],
      ),
      (u) => DecisionPatch(criteria: u.criteria),
    );
  }

  /// Slider mutasyonu — debounce'lu (Y-2); bırakınca [flushPendingWrites].
  void setCriterionWeight(String criterionId, int weight) {
    if (DecisionValidator.criterionWeight(weight) != null) return;
    _mutateDebounced(
      (d) => d.copyWith(
        criteria: [
          for (final c in d.criteria)
            c.id == criterionId ? c.copyWith(weight: weight) : c,
        ],
      ),
      (u) => DecisionPatch(criteria: u.criteria),
    );
  }

  Future<Failure?> removeCriterion(String criterionId) => _mutate(
        (d) => d.copyWith(
          criteria: d.criteria.where((c) => c.id != criterionId).toList(),
          scores: {
            for (final e in d.scores.entries)
              e.key: Map.of(e.value)..remove(criterionId),
          },
        ),
        (u) => DecisionPatch(criteria: u.criteria, scores: u.scores),
      );

  // ---- Puan matrisi (US-B4) ----

  /// Slider mutasyonu — debounce'lu (Y-2); bırakınca [flushPendingWrites].
  void setScore(String optionId, String criterionId, int value) {
    if (DecisionValidator.cellScore(value) != null) return;
    _mutateDebounced(
      (d) {
        final scores = {
          for (final e in d.scores.entries) e.key: Map.of(e.value),
        };
        (scores[optionId] ??= {})[criterionId] = CellScore(value: value);
        return d.copyWith(scores: scores);
      },
      (u) => DecisionPatch(scores: u.scores),
    );
  }

  // ---- Diğer ----

  Future<Failure?> setTitle(String title) async {
    if (DecisionValidator.title(title) != null) return null;
    return _mutate(
      (d) => d.copyWith(title: title.trim()),
      (u) => DecisionPatch(title: u.title),
    );
  }

  Future<Failure?> toggleFavorite() => _mutate(
        (d) => d.copyWith(isFavorite: !d.isFavorite),
        (u) => DecisionPatch(isFavorite: u.isFavorite),
      );
}

final decisionEditorProvider = AsyncNotifierProvider.autoDispose
    .family<DecisionEditor, Decision, String>(DecisionEditor.new);

/// Sonuç ekranına geçiş kapısı: boş liste = hazır.
final resultReadinessProvider =
    Provider.autoDispose.family<List<ValidationFailure>, String>((ref, id) {
  final decision = ref.watch(decisionEditorProvider(id)).valueOrNull;
  if (decision == null) return const [];
  return DecisionValidator.readyForResult(decision);
});
