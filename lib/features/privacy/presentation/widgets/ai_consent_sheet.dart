import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';

/// AI işleme izni disclosure'ı — İLK aktarımdan ÖNCE (İş Paketi 5 / Dilim B).
///
/// Varsayılan durum İZİN VERİLMEMİŞTİR: önceden işaretli kutu yoktur ve
/// yalnız metni görüntülemek izin sayılmaz. Kapatma/geri hareketi de
/// "Şimdi değil" ile aynıdır.
///
/// `true` döner = kullanıcı KABUL ETTİ ve analizin başlamasını istiyor.
class AiConsentSheet extends StatelessWidget {
  const AiConsentSheet({super.key});

  static const acceptLabel = 'Kabul et ve analizi başlat';
  static const declineLabel = 'Şimdi değil';

  /// Disclosure maddeleri — gizlilik politikasıyla SENKRON tutulur
  /// (`test/release/privacy_consistency_test.dart`).
  static const bullets = <(IconData, String)>[
    (
      Icons.cloud_upload_outlined,
      'Kararının başlığı, seçenekleri (açıklama, artı ve eksileriyle) ve '
          'kriterlerin önem ağırlıkları analiz için sunucumuz üzerinden '
          'OpenAI API’ye gönderilir.',
    ),
    (
      Icons.grid_off_outlined,
      'Verdiğin puanlar gönderilmez; puan matrisi yalnız cihazındaki '
          'sıralama hesabında kullanılır.',
    ),
    (
      Icons.vpn_key_off_outlined,
      'API anahtarı cihazında değildir; istek her zaman sunucudan çıkar.',
    ),
    (
      Icons.save_outlined,
      'Üretilen analiz, karara bağlı olarak hesabında saklanır; hesabını '
          'silersen analiz de silinir.',
    ),
    (
      Icons.error_outline,
      'AI çıktısı hatalı veya eksik olabilir. Sağlık, hukuk ve finans '
          'kararlarında profesyonel tavsiyenin yerine geçmez.',
    ),
    (
      Icons.pause_circle_outline,
      '“Şimdi değil” dersen uygulamanın AI dışındaki tüm işlevleri '
          'çalışmaya devam eder. İzni sonra Ayarlar’dan verebilir ya da '
          'geri alabilirsin.',
    ),
  ];

  /// Modal olarak açar. Kapatma = izin YOK.
  static Future<bool> show(BuildContext context) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AiConsentSheet(),
    );
    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'AI analizi için izin',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: AppTokens.s2),
                  Text(
                    'Analizi başlatmadan önce ne gönderildiğini bilmeni '
                    'istiyoruz.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTokens.s4),
                  for (final (icon, text) in bullets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.s3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // İkon TEK BAŞINA anlam taşımaz: metin tamdır ve
                          // ekran okuyucudan gizlenir.
                          ExcludeSemantics(
                            child: Icon(
                              icon,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppTokens.s3),
                          Expanded(
                            child:
                                Text(text, style: theme.textTheme.bodyMedium),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.s2),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(acceptLabel),
            ),
            const SizedBox(height: AppTokens.s2),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(declineLabel),
            ),
          ],
        ),
      ),
    );
  }
}
