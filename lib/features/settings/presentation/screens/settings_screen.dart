import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/legal_links.dart';
import '../../../../core/services/analytics/analytics_service.dart';
import '../../../../core/services/external_link_launcher.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/app_section_header.dart';
import '../../domain/account_deletion.dart';
import '../providers/settings_providers.dart';

/// Ayarlar — "Hesap ve Veriler" (PR-R1) ve "Yasal" (PR-LEGAL-1).
///
/// Bilinçli olarak MİNİMUM: placeholder satır ya da henüz çalışmayan hiçbir
/// seçenek yok. Yasal bağlantılar yayımlanmış gerçek sayfalara gider;
/// mağaza incelemesi çalışmayan bağlantıyı reddeder.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDeleting = ref.watch(deleteAccountControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.s4),
          children: [
            const AppSectionHeader(title: 'Hesap ve Veriler'),
            _DeleteAccountTile(
              isDeleting: isDeleting,
              onPressed: () => _confirmAndDelete(context, ref),
            ),
            const SizedBox(height: AppTokens.s4),
            const AppSectionHeader(title: 'Yasal'),
            const _LegalTile(
              icon: Icons.privacy_tip_outlined,
              document: 'privacy',
              title: 'Gizlilik Politikası',
              url: LegalLinks.privacy,
            ),
            const _LegalTile(
              icon: Icons.description_outlined,
              document: 'terms',
              title: 'Kullanım Koşulları',
              url: LegalLinks.terms,
            ),
            const _LegalTile(
              icon: Icons.help_outline,
              document: 'support',
              title: 'Destek',
              url: LegalLinks.support,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    // Guard controller'da da var; burada da erken çıkılır ki sürerken
    // ikinci onay dialogu hiç açılmasın.
    if (ref.read(deleteAccountControllerProvider)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _ConfirmDeleteDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    // Spinner'ı kapatmayı garanti eden tek yer: controller finally bloğu.
    final report = await ref
        .read(deleteAccountControllerProvider.notifier)
        .deleteAccount();

    if (!context.mounted) return;

    final failure = report.failure;
    if (failure == null) {
      // Her iki başarı durumunda da eski hesabın ekranından çıkılır.
      router.go('/home');
      messenger.showSnackBar(
        SnackBar(content: Text(_successMessage(report.outcome!))),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(failure.message),
        // Geçici hatada kullanıcı akışı baştan kurmak zorunda kalmasın.
        action: failure.isRetryable
            ? SnackBarAction(
                label: 'Tekrar dene',
                onPressed: () => _confirmAndDelete(context, ref),
              )
            : null,
      ),
    );
  }

  /// Kurulmamış bir oturumu "başlattık" diye duyurmamak için iki metin.
  static String _successMessage(AccountDeletionOutcome outcome) =>
      switch (outcome) {
        AccountDeletionOutcome.deletedAndReady =>
          'Hesabın ve tüm verilerin silindi. '
              'Yeni ve boş bir misafir oturumu başlattık.',
        AccountDeletionOutcome.deletedNeedsRestart =>
          'Hesabın ve verilerin silindi. Yeni oturum başlatılamadı; '
              'uygulamayı yeniden aç.',
      };
}

/// Yasal belge satırı — bağlantıyı HARİCİ tarayıcıda açar.
///
/// Bilinçli olarak yükleme durumu YOK: `launchUrl` uygulamayı arka plana
/// atar ve dönüşte ekran zaten yeniden çizilir; burada bir spinner açmak
/// kullanıcı geri geldiğinde takılı kalma riski yaratırdı.
class _LegalTile extends ConsumerWidget {
  const _LegalTile({
    required this.icon,
    required this.title,
    required this.url,
    required this.document,
  });

  final IconData icon;
  final String title;
  final String url;

  /// Analytics ayrımı: privacy|terms|support. URL veya içerik gönderilmez.
  final String document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: '$title sayfasını tarayıcıda aç',
      child: ListTile(
        onTap: () => _open(context, ref),
        minTileHeight: 56,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s2,
        ),
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.open_in_new, size: 18),
      ),
    );
  }

  /// Sıra ÖNEMLİ: olay yalnız gerçekten açıldıktan sonra gönderilir.
  /// Önce göndermek, açılmayan sayfayı "açıldı" diye sayar ve metriği bozar.
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final analytics = ref.read(analyticsServiceProvider);

    var opened = false;
    try {
      opened = await ref.read(externalLinkLauncherProvider).open(url);
    } catch (_) {
      // Adapter normalde yutar; yine de burada da savunma var ki bir
      // sızıntı kullanıcıya yakalanmamış hata olarak yansımasın.
      opened = false;
    }

    if (!opened) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('$title açılamadı. Lütfen daha sonra dene.')),
      );
      return;
    }

    // Analytics telemetridir: hatası kullanıcı akışını ETKİLEMEZ.
    unawaited(
      analytics
          .logLegalLinkOpened(document: document)
          .catchError((Object _) {}),
    );
  }
}

/// Yıkıcı aksiyon satırı — ListTile en az 48dp dokunma alanı verir.
class _DeleteAccountTile extends StatelessWidget {
  const _DeleteAccountTile({required this.isDeleting, required this.onPressed});

  final bool isDeleting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;

    return Semantics(
      button: true,
      enabled: !isDeleting,
      label: 'Hesabımı ve verilerimi kalıcı olarak sil',
      child: ListTile(
        // İşlem sürerken null → hem görsel hem davranışsal olarak kapalı.
        onTap: isDeleting ? null : onPressed,
        minTileHeight: 56,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s2,
        ),
        leading: Icon(Icons.delete_forever_outlined, color: error),
        title: Text(
          'Hesabımı ve Verilerimi Sil',
          style: theme.textTheme.titleMedium?.copyWith(color: error),
        ),
        subtitle: const Text(
          'Kararların, AI analizlerin ve hesabın kalıcı olarak silinir.',
        ),
        trailing: isDeleting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
    );
  }
}

/// Geri alınamaz işlem için açık onay. Yıkıcı buton varsayılan/odaklı
/// DEĞİLDİR: kazara "enter/onayla" yıkıcı olanı seçmemeli.
class _ConfirmDeleteDialog extends StatelessWidget {
  const _ConfirmDeleteDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Hesabını ve tüm verilerini sil'),
      content: const Text(
        'Kararların, AI analizlerin ve mevcut hesabın kalıcı olarak silinir. '
        'Bu işlem geri alınamaz. Uygulamayı kullanmaya devam edebilmen için '
        'sonrasında yeni ve boş bir misafir oturumu oluşturulur.',
      ),
      actions: [
        TextButton(
          autofocus: true, // güvenli seçenek odakta
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          child: const Text('Kalıcı Olarak Sil'),
        ),
      ],
    );
  }
}
