import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/services/analytics/analytics_service.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/app_empty_hint.dart';
import '../../../../core/widgets/app_section_header.dart';
import '../../../ai_analysis/presentation/widgets/analysis_card.dart';
import '../../../decision/domain/entities/decision.dart';
import '../../../decision/presentation/providers/decision_editor.dart';
import '../../../decision/presentation/providers/decision_providers.dart';
import '../../../journey/presentation/providers/journey_providers.dart';
import '../../../scoring/domain/entities/scoring_types.dart';
import '../widgets/result_rank_tile.dart';
import '../widgets/result_winner_panel.dart';

/// Sonuç ekranı v1 — yerel ağırlıklı skor (US-C2).
/// Sprint 3'te eklenecekler: AI yorumu, riskler, what-if slider'ları, paylaşım.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({
    super.key,
    required this.decisionId,
    this.returnHomeOnBack = false,
  });
  final String decisionId;

  /// Check-in akışından gelindiğinde true: geri (AppBar butonu + sistem geri
  /// hareketi) Home'a döner. Bu akışta `context.go(result)` navigation
  /// yığınını değiştirdiğinden altta pop edilecek Home olmayabilir; salt
  /// pop uygulamayı kapatırdı. Varsayılan false → normal puanlama akışının
  /// mevcut geri davranışı (bir önceki rotaya pop) korunur.
  final bool returnHomeOnBack;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  String get decisionId => widget.decisionId;

  @override
  void initState() {
    super.initState();
    // v1 aktivasyon olayı (PRD kuzey yıldızı hunisinin son adımı).
    unawaited(ref.read(analyticsServiceProvider).logResultViewed());
  }

  /// Check-in kaynaklı geri: her durumda (loading/error/data) Home'a döner.
  void _goHome() {
    if (!mounted) return;
    context.go('/home');
  }

  /// returnHomeOnBack iken AppBar'da görünür, Home'a götüren geri butonu.
  /// Aksi halde null → AppBar varsayılan davranışını (koşullu pop) korur.
  Widget? get _leading =>
      widget.returnHomeOnBack ? BackButton(onPressed: _goHome) : null;

  @override
  Widget build(BuildContext context) {
    final decisionAsync = ref.watch(decisionEditorProvider(decisionId));

    return PopScope(
      // Check-in akışında sistem geri hareketini yakalayıp Home'a çeviririz;
      // aksi halde normal pop davranışına izin verilir.
      canPop: !widget.returnHomeOnBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return; // pop gerçekleştiyse ikinci navigation üretme
        _goHome();
      },
      child: decisionAsync.when(
        loading: () => Scaffold(
          // Yüklenirken de kullanıcı mahsur kalmasın: check-in akışında
          // görünür geri butonu; normal akışta eski davranış (appBar yok).
          appBar: widget.returnHomeOnBack ? AppBar(leading: _leading) : null,
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(leading: _leading),
          body: Center(child: Text('Yüklenemedi: $e')),
        ),
        data: (decision) {
          if (!decision.isScoreMatrixComplete) {
            // Derin bağlantıyla eksik karara gelinirse güvenli düşüş —
            // tasarım diliyle hizalı (AppEmptyHint). Metin/route/güvenli geri
            // davranışı korunur.
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  decision.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                leading: _leading,
              ),
              body: ListView(
                padding: const EdgeInsets.all(AppTokens.s4),
                children: [
                  AppEmptyHint(
                    icon: Icons.tune_outlined,
                    title: 'Puanlama tamamlanmadı',
                    message: 'Sonuç için önce tüm puanlamayı tamamla.',
                    actionLabel: 'Puanlamaya Dön',
                    actionIcon: Icons.arrow_back_rounded,
                    onAction: () => context.go('/decision/$decisionId/edit'),
                  ),
                ],
              ),
            );
          }

          final result = ref.read(computeResultProvider)(decision);
          final byId = {for (final o in decision.options) o.id: o};
          final winner = byId[result.recommendedOptionId]!;
          // Eşitlik YALNIZ sunum hesabı — domain/scoring değişmez.
          final tiedLeaderIds = _tiedLeaderIds(result);
          final isTie = tiedLeaderIds.isNotEmpty;
          final ranks = _competitionRanks(result);

          return Scaffold(
            appBar: AppBar(
              title: Text(
                decision.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              leading: _leading,
            ),
            bottomNavigationBar: _CommitSection(
              decision: decision,
              recommendedOptionId: result.recommendedOptionId,
              isTie: isTie,
              onCommit: (optionId) async {
                final failure = await ref
                    .read(decisionEditorProvider(decisionId).notifier)
                    .commitDecision(optionId);
                // Yazım başarısızsa taahhüt YOK: takip sözünü kurma, hatayı
                // sheet'e geri ver (sheet açık kalır, PromiseView'a geçmez).
                if (failure != null) return failure;
                // Sprint C.1: söz zaten verilmişse vade yeni taahhütten başlar.
                // (İlk kez karar verende tercih yok → no-op; sözü sheet sorar.)
                // BEKLENMEZ: takip motoru en iyi çabadır, yerel depolama yavaş
                // ya da erişilemez olduğunda kararın kaydını geciktirmemeli.
                unawaited(
                  ref.read(followUpCoordinatorProvider).onCommitted(
                        decisionId: decisionId,
                        decisionTitle: decision.title,
                      ),
                );
                return null;
              },
              onRevert: () async {
                final failure = await ref
                    .read(decisionEditorProvider(decisionId).notifier)
                    .revertDecision();
                // Geri alma yazımı başarısızsa taahhüt DURUYOR: sözü iptal etme,
                // hatayı sheet'e geri ver (sheet kapanmaz).
                if (failure != null) return failure;
                // Sprint C.1: taahhüt kalktı → tutulacak söz kalmadı.
                // Beklenmez (yukarıdaki gerekçe).
                unawaited(
                  ref.read(followUpCoordinatorProvider).onReverted(decisionId),
                );
                return null;
              },
              // Sprint C.1: tercih CİHAZDA saklanır (Firestore'a yazılmaz) ve
              // söz verildiyse +7 gün YEREL bildirim planlanır.
              onPromiseAnswer: (optIn) =>
                  ref.read(followUpCoordinatorProvider).answerPromise(
                        decisionId: decisionId,
                        decisionTitle: decision.title,
                        optIn: optIn,
                      ),
            ),
            body: ListView(
              padding: const EdgeInsets.all(AppTokens.s4),
              children: [
                // 1) Kazanan paneli — sakin, güçlü koç sonucu (eşitlikte
                // tarafsız "başa baş" görünümü).
                ResultWinnerPanel(
                  title: winner.title,
                  confidence: result.confidence,
                  isTie: isTie,
                ),
                const SizedBox(height: AppTokens.s5),
                // 2) Puan dağılımı — tüm seçenekler şeffaflık için listede.
                const AppSectionHeader(title: 'Puan dağılımı'),
                const SizedBox(height: AppTokens.s3),
                for (final (i, score) in result.ranking.indexed)
                  ResultRankTile(
                    rank: ranks[i],
                    title: byId[score.optionId]?.title ?? '—',
                    score: score.score,
                    // Eşitlikte hiçbir seçenek "önerilen" değildir.
                    isWinner:
                        !isTie && score.optionId == result.recommendedOptionId,
                    isTiedLeader: tiedLeaderIds.contains(score.optionId),
                    isChosen: score.optionId == decision.chosenOptionId,
                  ),
                const SizedBox(height: AppTokens.s5),
                // 3) Sahiplik — AI'dan bağımsız, her kullanıcıya görünür.
                const _OwnershipNote(),
                const SizedBox(height: AppTokens.s5),
                // 4) AI analiz bölümü (yerleşim korunur; iç tasarım değişmez).
                AnalysisSection(decisionId: decisionId),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Floating-point skor karşılaştırması için sabit epsilon (sunum).
const double _tieEpsilon = 1e-6;

/// En yüksek puanı [_tieEpsilon] içinde paylaşan seçeneklerin id kümesi.
/// Yalnız ≥2 lider varsa doludur (tie); tek lider veya <2 seçenek → boş.
/// Domain'e dokunmaz — yalnız [DecisionResult.ranking] üzerinden türetir.
Set<String> _tiedLeaderIds(DecisionResult result) {
  final ranking = result.ranking;
  if (ranking.length < 2) return const {};
  final top = ranking.first.score;
  final tied = <String>{
    for (final s in ranking)
      if ((s.score - top).abs() <= _tieEpsilon) s.optionId,
  };
  return tied.length >= 2 ? tied : const {};
}

/// Competition ranking (1224 stili): [_tieEpsilon] içinde eşit skorlar aynı
/// sıra numarasını alır, sonraki farklı skor konumdan devam eder (1,1,3).
List<int> _competitionRanks(DecisionResult result) {
  final ranking = result.ranking;
  final ranks = List<int>.filled(ranking.length, 1);
  for (var i = 1; i < ranking.length; i++) {
    final samePrev =
        (ranking[i].score - ranking[i - 1].score).abs() <= _tieEpsilon;
    ranks[i] = samePrev ? ranks[i - 1] : i + 1;
  }
  return ranks;
}

/// Karar sahipliği hatırlatıcısı (Görsel Dilim 3) — AI başarı durumundan
/// bağımsız, her kullanıcıya görünür sakin bilgi yüzeyi.
class _OwnershipNote extends StatelessWidget {
  const _OwnershipNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.s3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Text(
              'Bu bir öneri; son karar senin.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sprint B — alt bar: karar verilmediyse "Kararımı Verdim" CTA'sı,
/// verildiyse seçim + "Değiştir". Karar taahhüt anı burada kapanır.
class _CommitSection extends StatelessWidget {
  const _CommitSection({
    required this.decision,
    required this.recommendedOptionId,
    required this.isTie,
    required this.onCommit,
    required this.onRevert,
    required this.onPromiseAnswer,
  });

  final Decision decision;
  final String recommendedOptionId;

  /// Eşitlik: varsayılan seçim ve "önerilen ⭐" bastırılır (tarafsızlık).
  final bool isTie;
  final Future<Failure?> Function(String optionId) onCommit;
  final Future<Failure?> Function() onRevert;
  final Future<void> Function(bool optIn) onPromiseAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    // Sabit işlem yüzeyi: sıcak surface + ince üst ayırıcı + SafeArea
    // (2A/2B alt-bar diliyle hizalı). Davranış değişmez.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s4),
          child: decision.isDecided
              ? Row(
                  children: [
                    Icon(Icons.check_circle, color: semantic.success),
                    const SizedBox(width: AppTokens.s2),
                    Expanded(
                      child: Text(
                        '${_chosenTitle()} seçildi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openSheet(context),
                      child: const Text('Değiştir'),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.how_to_reg),
                    label: const Text('Kararımı Verdim'),
                    onPressed: () => _openSheet(context),
                  ),
                ),
        ),
      ),
    );
  }

  String _chosenTitle() {
    final chosen = decision.options
        .where((o) => o.id == decision.chosenOptionId)
        .map((o) => o.title);
    return chosen.isEmpty ? 'Seçimin' : chosen.first;
  }

  Future<void> _openSheet(BuildContext context) {
    // Önseçim: mevcut seçim; yoksa eşitlik-dışında önerilen, eşitlikte YOK
    // (kullanıcı bilinçli seçsin — tarafsızlık).
    final initial =
        decision.chosenOptionId ?? (isTie ? null : recommendedOptionId);
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetCtx) => _CommitSheet(
        options: decision.options,
        initialId: initial,
        recommendedOptionId: recommendedOptionId,
        isTie: isTie,
        canRevert: decision.isDecided,
        onPromiseAnswer: onPromiseAnswer,
        onCommit: onCommit,
        onRevert: onRevert,
      ),
    );
  }
}

class _CommitSheet extends ConsumerStatefulWidget {
  const _CommitSheet({
    required this.options,
    required this.initialId,
    required this.recommendedOptionId,
    required this.isTie,
    required this.canRevert,
    required this.onPromiseAnswer,
    required this.onCommit,
    required this.onRevert,
  });

  final List<Option> options;

  /// Önseçili seçenek id'si; eşitlik + açık durumda null (seçim yok).
  final String? initialId;
  final String recommendedOptionId;
  final bool isTie;
  final bool canRevert;
  final Future<Failure?> Function(String optionId) onCommit;
  final Future<Failure?> Function() onRevert;
  final Future<void> Function(bool optIn) onPromiseAnswer;

  @override
  ConsumerState<_CommitSheet> createState() => _CommitSheetState();
}

class _CommitSheetState extends ConsumerState<_CommitSheet> {
  late String? _selected = widget.initialId;
  bool _saving = false;

  /// Sprint C: taahhüt başarılı olunca sheet SÖZ fazına geçer.
  bool _committed = false;

  String get _selectedTitle =>
      widget.options
          .where((o) => o.id == _selected)
          .map((o) => o.title)
          .firstOrNull ??
      'Seçimin';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_committed) {
      return _PromiseView(
        chosenTitle: _selectedTitle,
        onAnswer: widget.onPromiseAnswer,
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        left: AppTokens.s4,
        right: AppTokens.s4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppTokens.s4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Hangisini seçtin?', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppTokens.s2),
          for (final option in widget.options)
            InkWell(
              onTap:
                  _saving ? null : () => setState(() => _selected = option.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.s2),
                child: Row(
                  children: [
                    Icon(
                      option.id == _selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: option.id == _selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppTokens.s3),
                    Expanded(child: Text(option.title)),
                    // Eşitlikte tarafsızlık: hiçbir seçenek "önerilen" değil.
                    if (!widget.isTie &&
                        option.id == widget.recommendedOptionId)
                      Text(
                        'önerilen ⭐',
                        style: theme.textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppTokens.s2),
          FilledButton(
            // Eşitlikte kullanıcı bir seçenek seçene dek pasif.
            onPressed: (_saving || _selected == null) ? null : _commit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Bu kararı veriyorum'),
          ),
          if (widget.canRevert)
            TextButton(
              onPressed: _saving ? null : _revert,
              child: const Text('Kararı geri al'),
            ),
        ],
      ),
    );
  }

  Future<void> _commit() async {
    final selected = _selected;
    if (selected == null) return; // buton pasif olmalıydı; güvenlik.
    setState(() => _saving = true);
    final failure = await widget.onCommit(selected);
    if (!mounted) return;
    if (failure != null) {
      // Yazım başarısız: taahhüt yok. Sheet açık kalır, PromiseView'a
      // geçilmez, buton yeniden denenebilir; hata kullanıcıya gösterilir.
      setState(() => _saving = false);
      _showFailure(failure);
      return;
    }
    // Sprint C: kapatmak yerine SÖZ ekranına geç — journey'nin sözleşmesi
    // taahhüt anında kurulur (Decision Journey §Aşama 3).
    setState(() {
      _saving = false;
      _committed = true;
    });
  }

  Future<void> _revert() async {
    setState(() => _saving = true);
    final failure = await widget.onRevert();
    if (!mounted) return;
    if (failure != null) {
      // Geri alma başarısız: taahhüt duruyor. Sheet kapanmaz, tekrar
      // denenebilir; hata kullanıcıya gösterilir.
      setState(() => _saving = false);
      _showFailure(failure);
      return;
    }
    Navigator.of(context).pop();
  }

  /// Tek seferde tek hata: yeni hatadan önce birikeni temizle. Ham exception
  /// değil, kullanıcı dostu [Failure.userMessage] gösterilir.
  void _showFailure(Failure failure) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(failure.userMessage)));
  }
}

/// SÖZ EKRANI (Sprint C, Decision Journey §Aşama 3).
///
/// Taahhüt anının hemen ardından gelir ve journey'nin SÖZLEŞMESİNİ kurar:
/// koç "1 hafta sonra soracağım" der. Tercih CİHAZDA saklanır — Firestore'a
/// yazılmaz (bildirimler yerel planlanacak; maliyet artmaz).
///
/// Kutlama yok (konfeti değil mühür): ciddi karar ürününde sakin onay
/// güveni korur.
class _PromiseView extends StatefulWidget {
  const _PromiseView({required this.chosenTitle, required this.onAnswer});

  final String chosenTitle;

  /// true = "Evet, sor" (takip sözü verildi), false = "Şimdi değil".
  final Future<void> Function(bool optIn) onAnswer;

  @override
  State<_PromiseView> createState() => _PromiseViewState();
}

class _PromiseViewState extends State<_PromiseView> {
  bool _busy = false;

  void _answer({required bool optIn}) {
    if (_busy) return;
    setState(() => _busy = true);
    // Tercih YEREL bir kayıt; yazımı beklemek kullanıcıyı sheet'te tutmamalı
    // (depolama erişilemezse ekran kilitlenirdi). Kapat, yazımı arkada bırak.
    unawaited(widget.onAnswer(optIn));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s6,
        AppTokens.s4,
        AppTokens.s6,
        AppTokens.s6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: AppTokens.s3),
          Text(
            'Kararın kaydedildi.',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.s1),
          Text(
            widget.chosenTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.s6),
          Text(
            '1 hafta sonra nasıl gittiğini sorayım mı?',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.s4),
          FilledButton(
            onPressed: _busy ? null : () => _answer(optIn: true),
            child: const Text('Evet, sor'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _answer(optIn: false),
            child: const Text('Şimdi değil'),
          ),
        ],
      ),
    );
  }
}
