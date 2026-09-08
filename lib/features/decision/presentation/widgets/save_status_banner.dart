import 'package:flutter/material.dart';

import '../providers/decision_editor.dart';

/// Kayıt durumunun GÖRÜNÜR yüzeyi (İş Paketi 4 / Dilim D).
///
/// Eskiden kayıt hatası hiçbir yerde izlenmeyen global bir provider'a
/// düşüyordu: kullanıcı değişikliğinin kaydedilmediğini HİÇ öğrenemiyordu.
/// Kısa süreli bir SnackBar da yeterli değildir — kullanıcı ekrana sonra
/// baksa hatayı kaçırırdı. Bu yüzden yüzey KALICIDIR.
///
/// Erişilebilirlik: `liveRegion` ile ekran okuyucuya duyurulur, renk TEK
/// BAŞINA anlam taşımaz (ikon + metin), dar ekran ve büyük yazı ölçeğinde
/// taşmaz.
class SaveStatusBanner extends StatelessWidget {
  const SaveStatusBanner({super.key, required this.state, this.onRetry});

  final SaveState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: switch (state) {
        // Hata yokken kalıcı gürültü oluşturmaz.
        SaveIdle() => const SizedBox.shrink(),
        SaveInProgress() || SaveRetrying() => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text('Kaydediliyor…', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        SaveFailed(:final message) => Container(
            width: double.infinity,
            color: theme.colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                if (onRetry != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onRetry,
                      child: const Text('Tekrar Dene'),
                    ),
                  ),
              ],
            ),
          ),
      },
    );
  }
}
