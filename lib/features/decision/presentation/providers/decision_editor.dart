import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// KARAR BAŞINA kayıt durumu (İş Paketi 4 / Dilim C).
///
/// Eskiden tek bir global `autosaveFailureProvider` vardı: bir karardaki
/// hata teorik olarak başka bir kararda görünebiliyordu ve hiçbir UI onu
/// izlemediği için kullanıcı niyeti SESSİZCE kayboluyordu.
sealed class SaveState {
  const SaveState();
}

/// Bekleyen yazım yok — her şey kaydedildi.
class SaveIdle extends SaveState {
  const SaveIdle();
}

/// Yazım sürüyor.
class SaveInProgress extends SaveState {
  const SaveInProgress();
}

/// Yazım başarısız. [message] kullanıcıya gösterilebilir; ham exception
/// ASLA taşınmaz. Bekleyen niyet retry kuyruğunda DURUR.
class SaveFailed extends SaveState {
  const SaveFailed(this.message);
  final String message;
}

/// Başarısız yazım yeniden deneniyor.
class SaveRetrying extends SaveState {
  const SaveRetrying();
}

/// Kayıt durumlarının SINIRLI kayıt defteri (İş Paketi 4).
///
/// İki ayrı kısıt aynı anda karşılanmalıydı:
///
/// 1. **Yazan taraf dinleyicisiz olabilir.** Editör, kendisini kimse
///    dinlemezken de (dispose yolundaki son yazım, sonuç ekranından gelen
///    taahhüt) duruma yazar. `StateProvider.autoDispose.family`'ye
///    dinleyicisiz yazmak arkada bir dispose ZAMANLAYICISI bırakıyor ve
///    widget testlerini "A Timer is still pending" ile düşürüyordu.
/// 2. **Birikim sınırlı olmalı.** `autoDispose` olmayan bir aile ise
///    oturum boyunca açılan HER karar için kalıcı bir eleman bırakıyordu.
///
/// Çözüm: durum Riverpod ailesinde değil, düz bir kayıt defterinde tutulur.
/// Editör defteri `ref` üzerinden değil DOĞRUDAN tuttuğu için dispose
/// sonrası yazım güvenlidir ve hiçbir zamanlayıcı kurulmaz. Defter yalnız
/// IDLE OLMAYAN durumları saklar: bir yazım başarıyla bittiğinde girdi
/// SİLİNİR, dolayısıyla boyut "şu anda kaydedilememiş karar sayısı" ile
/// sınırlıdır — açılmış karar sayısıyla değil.
class SaveStateRegistry extends ChangeNotifier {
  final Map<String, SaveState> _states = <String, SaveState>{};
  bool _disposed = false;

  /// Yalnız IDLE OLMAYAN girdiler — testlerin sınırı kanıtlaması için.
  int get trackedCount => _states.length;

  SaveState stateOf(String decisionId) =>
      _states[decisionId] ?? const SaveIdle();

  @override
  void dispose() {
    _disposed = true;
    _states.clear();
    super.dispose();
  }

  void write(String decisionId, SaveState next) {
    // Kapsam kapandıktan sonra (ör. editörün dispose yolundaki son yazımı
    // konteyner kapanışının ARDINDAN tamamlanır) durum yazılmaz: izleyen
    // kimse yoktur ve `notifyListeners` atardı.
    if (_disposed) return;
    // `SaveState` alt sınıfları const kurulur; aynı değer kanonikleşir.
    if (stateOf(decisionId) == next) return;
    if (next is SaveIdle) {
      _states.remove(decisionId);
    } else {
      _states[decisionId] = next;
    }
    notifyListeners();
  }

  /// Ekran/editör kapanırken bekleyen ya da uçuşta iş YOKKEN çağrılır.
  void clear(String decisionId) => write(decisionId, const SaveIdle());
}

final saveStateRegistryProvider = ChangeNotifierProvider<SaveStateRegistry>(
  (_) => SaveStateRegistry(),
);

/// Karar bazında kayıt durumu — TÜREVDİR, yazılmaz.
///
/// `autoDispose` burada güvenli: bu provider'a hiç YAZILMAZ, yalnız
/// izlenir; dinleyicisiz yazım kaynaklı dispose zamanlayıcısı oluşamaz.
final decisionSaveStateProvider =
    Provider.autoDispose.family<SaveState, String>(
  (ref, decisionId) => ref.watch(saveStateRegistryProvider).stateOf(decisionId),
);

/// Taslak düzenleme durum makinesi — TEKNIK-MIMARI.md §6.1
/// Her mutasyon: state güncelle → repository'ye kaydet.
/// (Firestore'a geçişte 800 ms debounce eklenecek; in-memory'de gereksiz.)
class DecisionEditor extends AutoDisposeFamilyAsyncNotifier<Decision, String> {
  late DecisionRepository _repo;
  DecisionPatch? _pendingPatch;
  Timer? _debounceTimer;

  /// Aynı anda tek yazım: iki flush aynı patch'i bağımsız GÖNDEREMEZ.
  Future<Failure?>? _inFlight;

  /// Kayıt defteri DOĞRUDAN tutulur: dispose sonrası son yazımın sonucu da
  /// (Idle → girdi silinir) yazılabilsin diye `ref` üzerinden okunmaz.
  late final SaveStateRegistry _saveStates;

  /// `state`/`ref` erişimi dispose sonrası geçersiz — yerel bayrakla korunur.
  bool _disposed = false;

  @override
  Future<Decision> build(String arg) async {
    final repo = ref.watch(decisionRepositoryProvider);
    _repo = repo;
    _saveStates = ref.read(saveStateRegistryProvider);
    ref.onDispose(() {
      _disposed = true;
      _debounceTimer?.cancel();
      // Ekrandan çıkarken bekleyen yazım KAYBOLMAZ: yazımın KENDİSİ
      // gönderilir — eski `silent: true` yolu hatayı da yazımı da görünmeden
      // yutuyordu. Kayıt defteri `ref`ten bağımsız olduğu için sonucu
      // (Idle) yazmaya devam edebiliriz.
      final patch = _takePending();
      if (patch != null && !patch.isEmpty) {
        unawaited(
          _writePatch(patch).then<void>((_) {}, onError: (Object _) {}),
        );
      }
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
    _setSaveState(const SaveInProgress());
    try {
      await ref
          .read(decisionRepositoryProvider)
          .applyPatch(previous.id, merged);
      _trackFunnel(previous, updated);
      _setSaveState(const SaveIdle());
      return null;
    } catch (error, stackTrace) {
      state = AsyncData(previous); // iyimser güncellemeyi geri al
      // NİYET KAYBOLMAZ: başarısız patch kuyruğa geri konur ve "Tekrar Dene"
      // ile aynı niyet yeniden uygulanabilir (İş Paketi 4 / Dilim C).
      _pendingPatch = _mergePatches(merged, _pendingPatch ?? merged);
      _setSaveState(
        const SaveFailed(
          'Değişiklik kaydedilemedi. Bağlantını kontrol edip tekrar dene.',
        ),
      );
      unawaited(
        // Sabit reason; karar içeriği/UID/patch verisi GÖNDERİLMEZ.
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

  /// Bekleyen birleşik yazımı hemen gönderir ve SONUCU DÖNDÜRÜR.
  ///
  /// `null` = başarılı. Çağıran (ör. "Sonucu Gör") bunu bekleyip
  /// başarısızlıkta navigasyonu engelleyebilir.
  Future<Failure?> flushPendingWrites() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final existing = _inFlight;
    // Aynı anda ikinci flush AYNI işi paylaşır; çift yazım oluşmaz.
    if (existing != null) return existing;
    final patch = _takePending();
    if (patch == null || patch.isEmpty) {
      // Kaydedilmemiş niyet YOK (her başarısızlık yolu patch'i kuyruğa geri
      // koyar) → durum IDLE. Aksi halde boş kuyrukta `retrySave`
      // `SaveRetrying`de takılı kalırdı.
      _setSaveState(const SaveIdle());
      return Future<Failure?>.value();
    }
    final future = _writePatch(patch);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  /// Başarısız yazımı AYNI niyetle yeniden dener.
  Future<Failure?> retrySave() {
    _setSaveState(const SaveRetrying());
    return flushPendingWrites();
  }

  Future<Failure?> _writePatch(DecisionPatch patch) async {
    _setSaveState(const SaveInProgress());
    try {
      await _repo.applyPatch(arg, patch);
      _setSaveState(const SaveIdle());
      return null;
    } catch (error, stackTrace) {
      // NİYET KAYBOLMAZ: başarısız patch kuyruğa geri konur ve sonraki
      // değişikliklerle birleşerek yeniden denenebilir.
      _pendingPatch = _mergePatches(patch, _pendingPatch ?? patch);
      final failure = UnexpectedFailure(error, stackTrace);
      _setSaveState(
        const SaveFailed(
          'Değişiklik kaydedilemedi. Bağlantını kontrol edip tekrar dene.',
        ),
      );
      // Otoriter duruma yeniden hizalan (iyimser state depoyla ayrışmasın).
      if (!_disposed) {
        final fresh = await _repo.getById(arg);
        if (fresh != null) state = AsyncData(fresh);
      }
      return failure;
    }
  }

  /// Kayıt defterinin SINIRI buradan gelir.
  ///
  /// Ölü editörün durumu kimseye gösterilemez ve yeniden denenemez (niyet
  /// editörle birlikte gitti). Bu yüzden dispose SONRASI her sonuç deftere
  /// IDLE olarak düşer → girdi silinir. Böylece "ekran kapandıktan sonra
  /// defterde kalan durum" — birikimin tek kaynağı — mümkün değildir ve
  /// ölü editörün hatası bir sonraki editöre miras kalmaz.
  void _setSaveState(SaveState next) =>
      _saveStates.write(arg, _disposed ? const SaveIdle() : next);

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
      // Sprint B: taahhüt alanları da taşınmalı — aksi halde bekleyen
      // debounce yazımıyla birleşince commit/geri-alma DÜŞER ve patch
      // boşalıp applyPatch fırlatır (iyimser güncelleme geri alınır).
      decisionStatus: newer.decisionStatus ?? older.decisionStatus,
      chosenOptionId: newer.chosenOptionId ?? older.chosenOptionId,
      // Sprint C.2: aynı gerekçe — kontrol cevabı bekleyen debounce
      // yazımıyla birleşince DÜŞMEMELİ.
      checkInStatus: newer.checkInStatus ?? older.checkInStatus,
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

  // ---- Sprint B: "Kararımı Verdim" ----

  /// Kullanıcı bir seçeneğe karar verir. chosenOptionId geçerli bir
  /// seçenek olmalı; değilse dokunmadan geçer.
  Future<Failure?> commitDecision(String optionId) {
    final current = state.valueOrNull;
    if (current == null || !current.options.any((o) => o.id == optionId)) {
      return Future.value();
    }
    return _mutate(
      (d) => d.copyWith(
        decisionStatus: DecisionCommitStatus.decided,
        chosenOptionId: optionId,
        decidedAt: DateTime.now(),
      ),
      (_) => DecisionPatch(
        decisionStatus: DecisionCommitStatus.decided,
        chosenOptionId: optionId,
      ),
    );
  }

  // ---- Sprint C.2: 1 hafta kontrolü ----

  /// Kontrol cevabını yazar. Karar başına TEK kayıt: karar verilmemişse
  /// ya da zaten cevaplanmışsa sessizce geçer (rules de ayrıca zorlar).
  Future<Failure?> submitCheckIn(DecisionCheckIn status) {
    final current = state.valueOrNull;
    if (current == null || !current.canCheckIn) return Future.value();
    return _mutate(
      (d) => d.copyWith(checkInStatus: status, checkedInAt: DateTime.now()),
      (_) => DecisionPatch(checkInStatus: status),
    );
  }

  /// Kararı geri al — taahhüt alanları temizlenir.
  Future<Failure?> revertDecision() => _mutate(
        (d) => d.copyWith(
          decisionStatus: DecisionCommitStatus.open,
          chosenOptionId: null,
          decidedAt: null,
        ),
        (_) => const DecisionPatch(decisionStatus: DecisionCommitStatus.open),
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
