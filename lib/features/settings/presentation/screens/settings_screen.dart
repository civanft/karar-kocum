import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/app_section_header.dart';
import '../providers/settings_providers.dart';

/// Ayarlar — yalnız "Hesap ve Veriler" (PR-R1, mağaza zorunluluğu).
///
/// Bilinçli olarak MİNİMUM: sahte legal bağlantı, placeholder satır ya da
/// henüz çalışmayan hiçbir seçenek yok. Mağaza incelemesi çalışmayan
/// bağlantıyı reddeder.
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
    final failure = await ref
        .read(deleteAccountControllerProvider.notifier)
        .deleteAccount();

    if (!context.mounted) return;

    if (failure == null) {
      router.go('/home');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Hesabın ve tüm verilerin silindi. '
            'Yeni ve boş bir misafir oturumu başlattık.',
          ),
        ),
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
