import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../providers/ai_consent_providers.dart';
import 'ai_consent_sheet.dart';

/// Ayarlar > Gizlilik: AI işleme izninin GÖRÜNTÜLENMESİ ve GERİ ALINMASI.
///
/// Geri alma yalnız GELECEKTEKİ aktarımları durdurur; hâlihazırda üretilmiş
/// analizleri silmez. Silme ayrı bir üründür ve kullanıcı hesap silme
/// akışına yönlendirilir — burada "sildim" izlenimi verilmez.
class AiConsentTile extends ConsumerStatefulWidget {
  const AiConsentTile({super.key});

  @override
  ConsumerState<AiConsentTile> createState() => _AiConsentTileState();
}

class _AiConsentTileState extends ConsumerState<AiConsentTile> {
  bool _busy = false;

  Future<void> _grant() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final accepted = await AiConsentSheet.show(context);
      if (!accepted || !mounted) return;
      await ref.read(aiConsentRepositoryProvider).grant();
    } on Object {
      if (mounted) _error('İzin kaydedilemedi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI iznini geri al'),
        content: const Text(
          'Bundan sonra karar içeriğin analiz için OpenAI’ye gönderilmez.\n\n'
          'Daha önce üretilmiş analizler bu işlemle SİLİNMEZ. Verilerini '
          'silmek istersen “Hesabını ve tüm verilerini sil” akışını '
          'kullanabilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Geri al'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(aiConsentRepositoryProvider).withdraw();
    } on Object {
      if (mounted) _error('İzin güncellenemedi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(String message) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text('$message Tekrar dene.')));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allowed = ref.watch(aiTransferAllowedProvider);
    // Yükleniyor/hata da dâhil izin YOK sayılır (fail closed); durum metni
    // kullanıcıya ne olduğunu doğru anlatır, ham hata göstermez.
    final loading = ref.watch(aiConsentProvider).isLoading;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.smart_toy_outlined),
      title: const Text('AI analizi izni'),
      subtitle: Text(
        loading
            ? 'Durum yükleniyor…'
            : allowed
                ? 'Verildi — karar içeriğin analiz için OpenAI’ye '
                    'gönderilebilir.'
                : 'Verilmedi — AI analizi çalıştırılmaz.',
        style: theme.textTheme.bodySmall,
      ),
      trailing: _busy
          ? const SizedBox(
              width: AppTokens.s4,
              height: AppTokens.s4,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: allowed ? _withdraw : _grant,
              child: Text(allowed ? 'Geri al' : 'İzin ver'),
            ),
    );
  }
}
