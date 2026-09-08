import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/tokens.dart';
import '../providers/decision_editor.dart';
import '../providers/scoring_progress.dart';
import '../widgets/criteria_tab.dart';
import '../widgets/options_tab.dart';
import '../widgets/save_status_banner.dart';
import '../widgets/scores_tab.dart';

/// Ekrandan çıkış yolları. Hepsi TEK kapıdan (`_exit`) geçer.
enum _ExitRoute { back, result }

/// Sekmeli düzenleme ekranı: Seçenekler / Kriterler / Puanlar.
/// "Sonucu Gör" yalnız matris tamamlanınca aktifleşir (US-C2 kapısı).
///
/// İŞ PAKETİ 4 — TEK ÇIKIŞ KAPISI:
/// Sistem geri hareketi, Android geri tuşu, AppBar geri butonu ve
/// "Sonucu Gör" AYNI `_exit` kapısını kullanır. Paralel ve farklı davranan
/// iki mekanizma YOK: hepsi bekleyen yazımı önce flush eder, flush
/// başarısızsa ekrandan ÇIKMAZ ve hata yüzeyi (SaveStatusBanner) görünür
/// kalır. `_exiting` bayrağı ilk `await`ten ÖNCE kurulduğu için çift
/// dokunuş / çift geri hareketi tek flush ve tek navigasyon üretir.
class DecisionEditScreen extends ConsumerStatefulWidget {
  const DecisionEditScreen({super.key, required this.decisionId});
  final String decisionId;

  @override
  ConsumerState<DecisionEditScreen> createState() => _DecisionEditScreenState();
}

class _DecisionEditScreenState extends ConsumerState<DecisionEditScreen>
    with WidgetsBindingObserver {
  /// Tek çıkış kapısının meşguliyet bayrağı.
  bool _exiting = false;

  String get decisionId => widget.decisionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Uygulama ön plandan çıkarken bekleyen debounce yazımı KAYBOLMAZ.
  ///
  /// `flushPendingWrites` bekleyen yamayı atomik olarak alır; ikinci bir
  /// lifecycle olayı geldiğinde alınacak yama kalmadığı için İKİNCİ bir
  /// yazım üretilmez. Hata YUTULMAZ: durum makinesi `SaveFailed`e düşer,
  /// niyet kuyrukta kalır ve kullanıcı "Tekrar Dene" ile sürdürebilir.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_flushForBackground());
      case AppLifecycleState.resumed:
        break;
    }
  }

  /// Lifecycle geri çağrısında UNHANDLED async exception bırakılmaz.
  Future<void> _flushForBackground() async {
    try {
      await ref
          .read(decisionEditorProvider(decisionId).notifier)
          .flushPendingWrites();
    } catch (_) {
      // Yutulmuş gibi görünmesin: hata durumu zaten save state makinesine
      // yazıldı. Burada yalnız zone'a sızmasını engelliyoruz.
    }
  }

  /// TEK çıkış kapısı — tüm çıkış yolları buradan geçer.
  ///
  /// Kapı, çıkış GERÇEKLEŞMEDİĞİ sürece yeniden açılır. Başarıyla
  /// çıkıldığında KAPALI kalır: aksi halde flush hızlı tamamlandığında
  /// bayrak aynı karede serbest kalıyor ve gerçek bir çift dokunuş üst
  /// üste iki sonuç ekranı açabiliyordu.
  Future<void> _exit(_ExitRoute route) async {
    if (_exiting) return; // çift dokunuş / çift geri koruması
    setState(() => _exiting = true);
    final failure = await ref
        .read(decisionEditorProvider(decisionId).notifier)
        .flushPendingWrites();
    if (!mounted) return;
    if (failure != null) {
      // ÇIKILMAZ: hata yüzeyi görünür kalır, kapı yeniden denenebilir.
      setState(() => _exiting = false);
      return;
    }
    switch (route) {
      case _ExitRoute.back:
        if (context.canPop()) {
          context.pop(); // ekran yok oluyor; kapı kapalı kalır
        } else {
          setState(() => _exiting = false);
        }
      case _ExitRoute.result:
        // Sonuç ekranı kapanana dek kapı kapalı.
        await context.push<void>('/decision/$decisionId/result');
        if (mounted) setState(() => _exiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final decisionAsync = ref.watch(decisionEditorProvider(decisionId));
    final blockers = ref.watch(resultReadinessProvider(decisionId));

    // canPop: false — sistem geri, Android geri ve AppBar geri butonunun
    // tamamı `_exit` kapısına yönlenir.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_exit(_ExitRoute.back));
      },
      child: decisionAsync.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        // Ham exception ASLA gösterilmez (İş Paketi 4 / Dilim D).
        error: (_, __) => Scaffold(
          appBar: AppBar(),
          body: _LoadErrorView(
            onRetry: () => ref.invalidate(decisionEditorProvider(decisionId)),
          ),
        ),
        data: (decision) {
          final semantic = _semanticOf(context);
          return DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  decision.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      decision.isFavorite ? Icons.star : Icons.star_border,
                      color: decision.isFavorite ? semantic.warning : null,
                    ),
                    tooltip: 'Favori',
                    onPressed: () => ref
                        .read(decisionEditorProvider(decisionId).notifier)
                        .toggleFavorite(),
                  ),
                ],
                bottom: TabBar(
                  tabs: [
                    const Tab(text: 'Seçenekler'),
                    const Tab(text: 'Kriterler'),
                    Tab(child: _ScoresTabLabel(decisionId: decisionId)),
                  ],
                ),
              ),
              body: Column(
                children: [
                  // Kayıt hatası KALICI olarak görünür (İş Paketi 4 / Dilim D).
                  // Tüm mutasyonlar (favori, seçenek, kriter, açıklama,
                  // artı/eksi, skor, taahhüt) merkezi save durumuna düştüğü
                  // için widget'lara ayrı hata kodu KOPYALANMAZ.
                  SaveStatusBanner(
                    state: ref.watch(decisionSaveStateProvider(decisionId)),
                    onRetry: () => ref
                        .read(decisionEditorProvider(decisionId).notifier)
                        .retrySave(),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        OptionsTab(decisionId: decisionId),
                        CriteriaTab(decisionId: decisionId),
                        ScoresTab(decisionId: decisionId),
                      ],
                    ),
                  ),
                ],
              ),
              // Sabit işlem yüzeyi: sıcak surface + ince üst ayırıcı + SafeArea.
              bottomNavigationBar: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (blockers.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppTokens.s2),
                            child: Text(
                              _blockerMessage(ref, decisionId, blockers.first),
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        _ResultButton(
                          enabled: blockers.isEmpty,
                          busy: _exiting,
                          onPressed: () => unawaited(_exit(_ExitRoute.result)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Tema hep sağlar; kurulmamış bağlamda moda uygun güvenli varsayılan.
AppSemanticColors _semanticOf(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<AppSemanticColors>() ??
      (theme.brightness == Brightness.dark
          ? AppSemanticColors.dark
          : AppSemanticColors.light);
}

/// PR-A3: puanlama engeli NİCELİKSEL mesaja zenginleşir; validator
/// sözleşmesi DEĞİŞMEDİ — yalnız sunum katmanı mesajı türetiyor.
String _blockerMessage(
  WidgetRef ref,
  String decisionId,
  ValidationFailure blocker,
) {
  if (blocker.field != 'scores') return blocker.message;
  final progress = ref.watch(scoringProgressProvider(decisionId));
  if (progress.total == 0) return blocker.message;
  final remaining = progress.total - progress.filled;
  return 'Puanlama: ${progress.filled}/${progress.total} — '
      '$remaining hücre kaldı';
}

/// "Puanlar" sekme etiketi + kalan-sayısı rozeti. Kendi Consumer'ında —
/// TabBar'ın tamamı değil yalnız rozet rebuild olur.
class _ScoresTabLabel extends ConsumerWidget {
  const _ScoresTabLabel({required this.decisionId});

  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(scoringProgressProvider(decisionId));
    final remaining = progress.total - progress.filled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Puanlar'),
        if (progress.total > 0 && remaining > 0) ...[
          const SizedBox(width: AppTokens.s1),
          CircleAvatar(
            radius: 9,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              '$remaining',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Ham exception yerine güvenli, tekrar denenebilir yükleme hatası.
class _LoadErrorView extends StatelessWidget {
  const _LoadErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Karar yüklenemedi. Bağlantını kontrol edip tekrar dene.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
          ],
        ),
      ),
    );
  }
}

/// "Sonucu Gör" — kendi flush mantığı YOKTUR.
///
/// Eskiden burada ayrı bir flush + çift-dokunma koruması vardı; geri
/// navigasyonu ise korumasızdı. Artık tek kapı (`_exit`) kullanılıyor:
/// buton yalnız kapının meşguliyetini yansıtır.
class _ResultButton extends StatelessWidget {
  const _ResultButton({
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled && !busy ? onPressed : null,
      icon: const Icon(Icons.insights),
      label: const Text('Sonucu Gör'),
    );
  }
}
